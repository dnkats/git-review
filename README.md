# git review

Review a long run of commits hunk by hunk, in place, using the git index as
the checklist and VS Code's Changes view (or any tool that shows the working
tree against the index) as the UI.

Made for reviewing what a coding agent did over a long session: the agent
keeps committing normally, you review the net result later, accept hunks one
at a time, edit directly while reviewing, and nothing you have accepted comes
back the next time. The agent's commit history is left untouched.

## How it works

`git review start` sets the index of your current checkout to the review base
without touching HEAD or the working tree. The base is `refs/reviewed/<branch>`
if the branch was reviewed before, otherwise the merge-base with `main` or
`master` (or `--base <ref>`). From then on:

- The Changes view shows every net change since the base, hunk by hunk.
- Staging a hunk accepts it (VS Code: Stage Selected Ranges). The index
  persists across sittings, so you can stop and continue tomorrow.
- Your own edits are ordinary working-tree edits. An agent working in the same
  checkout sees them at once.
- The Staged view shows the inverse diff base -> HEAD during a review. Ignore
  it; it is the mirror of the checklist.

Commits are refused while a review is open, by a small guard the tool appends
to the checkout's `pre-commit` hook, because a commit would snapshot the
checklist instead of the code. To commit mid-review, `git review pause`,
commit, `git review resume`; the new commits then show up as pending hunks.

`git review done` needs an empty Changes view. It moves
`refs/reviewed/<branch>` to HEAD and, if you edited anything, commits those
edits as one "review edits on <branch>" commit. `git review abort` drops the
checklist and keeps your edits as working-tree changes.

## Commands

```
git review start [--base <ref>]   begin: the index becomes the checklist
git review status                 what's pending / accepted (the default)
git review pause                  park the checklist so commits are allowed
git review resume                 bring the checklist back
git review done                   record reviewed/<branch>; commit your edits
git review abort                  drop the checklist (your edits stay as edits)
```

## Install

Put `git-review` somewhere on your `PATH`; git then finds it as `git review`.

```
git clone https://github.com/dnkats/git-review
ln -s "$PWD/git-review/git-review" ~/bin/git-review
```

Bash and git are the only requirements.

## Working with an agent

Rules that make this work in a shared checkout: the agent keeps committing
normally during a session; it never commits while a review is open (the guard
enforces this; it can `pause`, commit, `resume` if it must); and it checks
`git review status` at the start of any task after you reviewed, because
your review edits are in the working tree.

## State

Everything lives inside `.git` and is per worktree: `review-active` (the
marker with the base), `refs/reviewed/<branch>` (where the last review ended),
`refs/review-index/<branch>` (a parked checklist during `pause`), and the
guard block in `hooks/pre-commit`. Delete those and the tool has never been
there.
