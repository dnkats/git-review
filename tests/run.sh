#!/usr/bin/env bash
# Scenario tests for git-review. Each case builds a scratch repo, runs the
# tool, and checks the state git shows the reviewer. Run: tests/run.sh
set -euo pipefail
here=$(cd "$(dirname "$0")/.." && pwd)
export PATH="$here:$PATH"
export GIT_CONFIG_GLOBAL=/dev/null GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
fails=0
check() { if [[ "$2" == "$3" ]]; then echo "ok   $1"; else echo "FAIL $1: got '$2', want '$3'"; fails=$((fails+1)); fi; }
fresh() {  # a repo with main (f h k) and feat (f+d, k+K), both branched from base
  local d; d=$(mktemp -d); cd "$d"; git init -q -b main
  printf 'a\nb\nc\n' > f; echo m > h; echo k > k; git add .; git commit -qm base
  git checkout -qb feat; echo d >> f; echo K >> k; git commit -qam feat-work
  if [[ "${1:-}" == ahead ]]; then git checkout -q main; echo z >> h; git commit -qam main-work; git checkout -q feat; fi
}
porcelain() { git status --porcelain | sort | tr '\n' '|'; }
pending() { git diff --name-only | sort | tr '\n' ' '; }
base() { sed -n 's/^base //p' "$(git rev-parse --git-dir)/review-active"; }
accepted() { git diff --cached --name-only "$(base)" | sort | tr '\n' ' '; }

fresh
git review start >/dev/null
check "start: net changes pending" "$(pending)" "f k "
git add k
check "accept = stage" "$(accepted)" "k "
git commit -q --allow-empty -m x 2>/dev/null && r=0 || r=$?
check "commit refused during review" "$r" "1"
git review pause >/dev/null; git commit -q --allow-empty -m x; git review resume >/dev/null
check "pause/commit/resume keeps the checklist" "$(accepted)|$(pending)" "k |f "
echo mine >> h; git add f h
git review done >/dev/null
check "done commits review edits" "$(git log -1 --format=%s)" "review edits on feat"
check "done records reviewed/feat" "$(git rev-parse refs/reviewed/feat)" "$(git rev-parse HEAD)"
git review start >/dev/null && r=0 || r=$?
check "start after done: nothing to review" "$(git review start)" "nothing to review: HEAD is at reviewed/feat ($(git rev-parse HEAD | cut -c1-12))"

fresh ahead                                   # main only touched h, so a switch is allowed
git review start >/dev/null; git add k
git checkout -q main
check "stray switch went through" "$(git branch --show-current)|$(porcelain)" "main| M f|"
check "wrong branch refused" "$(git review pause 2>&1 || true)" "review open on feat, not on main; 'git review back' returns to it"
git review back >/dev/null
check "back: HEAD on the review branch" "$(git branch --show-current)" "feat"
check "back: untouched path clean, touched branch path pending again" "$(porcelain)" "MM f|MM k|"
check "back: worktree kept the branch's content" "$(tr '\n' ' ' < k)|$(tr '\n' ' ' < h)" "k K |m "
git review abort >/dev/null

fresh
git review start >/dev/null; git add k
git review pause >/dev/null; git checkout -q main; echo z >> h; git commit -qam m1; git checkout -q feat; git review resume >/dev/null
git review rebase >/dev/null 2>&1
check "rebase: branch on new main" "$(git merge-base HEAD main)" "$(git rev-parse main)"
check "rebase: accepted stays accepted, pending stays pending, main's change absent" "$(accepted)|$(pending)" "k |f "
git review abort >/dev/null

fresh
git review start >/dev/null; git add f k     # accept everything
git review pause >/dev/null; git checkout -q main; printf 'a\nb\nc\nE\n' > f; git commit -qam m1; git checkout -q feat; git review resume >/dev/null
git review rebase >/dev/null 2>&1 && r=0 || r=$?
check "rebase stops on a conflict" "$r|$(git review status 2>&1)" "1|review paused for a rebase that stopped; finish it (git rebase --continue / --abort), then 'git review resume'"
git rebase --abort; git review resume >/dev/null
check "rebase --abort then resume: unchanged" "$(accepted)|$(pending)" "f k |"
git review rebase >/dev/null 2>&1 || true
printf 'a\nb\nc\nE\nd\n' > f; git add f; GIT_EDITOR=true git rebase --continue >/dev/null 2>&1
out=$(git review resume 2>&1)
check "carry conflict: file named, pending again" "$(echo "$out" | grep -c '  f$')|$(pending)" "1|f "
check "carry conflict: only main's part pending" "$(git diff f | grep '^+[^+]' | tr '\n' ' ')" "+E "
git review abort >/dev/null

fresh
git review start >/dev/null; git add -A; git review done >/dev/null
git checkout -q main; echo z >> h; git commit -qam m1; git checkout -q feat; git rebase -q main; echo y >> k; git commit -qam feat-more
check "start after a rebase between sittings carries the base" "$(git review start | head -1)" "review open on feat: reviewed/feat carried onto main ($(base | cut -c1-12)) -> HEAD ($(git rev-parse --short=12 HEAD))"
check "only the new work pending" "$(pending)" "k "
git review abort >/dev/null
git merge -q -m merge main 2>/dev/null || true; git checkout -q main; echo z2 >> h; git commit -qam m2; git checkout -q feat; git merge -q -m merge main
check "start after a merge from main: only the new work pending" "$(git review start >/dev/null; pending)" "k "

fresh
wt=$(mktemp -d -u); git worktree add -q "$wt" -b other
(cd "$wt" && echo w > w && git add w && git commit -qm w1 && git review start >/dev/null)
check "worktree review does not block the main checkout" "$(git commit -q --allow-empty -m ok && echo committed)" "committed"
(cd "$wt" && git review abort >/dev/null)

cd /; echo; if (( fails )); then echo "$fails failure(s)"; exit 1; else echo "all passed"; fi
