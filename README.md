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

## Scenarios

**The agent committed on a feature branch in your checkout.** The normal
case. On that branch, `git review start`. The base is the merge-base with
main the first time and `refs/reviewed/<branch>` after that. Accept hunks,
edit, `git review done`.

**The agent worked in a separate worktree.** Review there: `cd` into the
worktree, `git review start`. All state is per worktree, so a review open in
the worktree does not block commits in your main checkout and vice versa.
`refs/reviewed/<branch>` is shared, which is what you want: it is keyed by
branch, not by directory. Don't try to review a branch from a checkout that
doesn't have it checked out; git refuses to check out a branch that another
worktree holds.

**The agent committed directly on main.** `git review start` alone says
"nothing to review", because the merge-base with main is HEAD. Give the base
once: `git review start --base origin/main`, or `--base HEAD~5`, or the
commit you last saw. After `done`, `refs/reviewed/main` exists and the next
`git review start` needs no `--base`.

**The agent left uncommitted changes.** Ask it to commit first; that keeps
its history and gives the review a base. If you review without a commit, the
tool adds nothing: the Changes view already shows the working tree against
HEAD, staging a hunk accepts it, and you commit yourself when Changes is empty.
Committed and uncommitted work together is fine: `git review start` shows
both as pending hunks.

**Several sittings.** Stop whenever. The index persists; `git review status`
tells you where you are. `done` only when Changes is empty. The next review
of the same branch starts at the tree recorded by the last `done`, so
anything already accepted is invisible, even if the agent has since amended
or rebased its commits: the comparison is between trees, not commits.

**The agent needs to keep working while you review.** In the same checkout,
its edits appear among your pending hunks and its commits are refused by the
guard until you `pause`. Better: let it work in another worktree or wait.
If it must commit in this checkout, `git review pause`, commit, `git review
resume`; the new commits show up as pending hunks. Resume on the same branch
you paused on: the parked checklist is keyed by branch and `resume` fails
loudly on any other.

**Rejecting a hunk.** Revert it in the working tree (VS Code: Revert Selected
Ranges, or `git checkout -p`). Now it is your edit, and `done` commits it
with everything else you changed as one "review edits" commit. Reject by
reverting, accept by staging; nothing else empties the Changes view.

**Rebasing or merging main during a review.** Don't; `done` or `abort` first.
A rebase after `done` is fine, but the next review will show main's changes
as pending hunks too, because they were not in the last reviewed tree. Either
review before you rebase, or accept the upstream hunks quickly; they are not
the agent's.

**Switching branches.** Git refuses to switch while the review's pending
changes would be overwritten, which is most of the time. `pause`, switch,
come back, `resume`.

**A branch the agent pushed from elsewhere.** `git fetch`, check the branch
out, `git review start`. Same as the first scenario.

**After the branch is merged.** `refs/reviewed/<branch>` stays behind and is
harmless. `git update-ref -d refs/reviewed/<branch>` removes it.

## Rules for the agent

The agent commits normally during a session; small, frequent commits are
what the review wants. It never commits while a review is open (the guard
enforces this; `pause`, commit, `resume` if it must). At the start of any
task after you reviewed it runs `git review status`, because your review
edits are in the working tree or in the last "review edits" commit, and they
are the truth. It does not run `done` or `abort`; those are yours.

## State

Everything lives inside `.git` and is per worktree: `review-active` (the
marker with the base), `refs/reviewed/<branch>` (where the last review ended),
`refs/review-index/<branch>` (a parked checklist during `pause`), and the
guard block in `hooks/pre-commit`. Delete those and the tool has never been
there.
