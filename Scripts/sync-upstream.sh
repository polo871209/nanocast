#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

INIT=false
[ "${1:-}" = "--init" ] && INIT=true

if ! $INIT && { ! git diff --quiet || ! git diff --cached --quiet; }; then
    echo "✗ Commit or stash your changes first." >&2
    exit 1
fi

git config rerere.enabled true
git config rerere.autoupdate true
git fetch --quiet origin main

OLD_SNAPSHOT="$(git log --first-parent -1 --format=%H --grep='^Rename upstream [0-9a-f]* to Nanocast$' HEAD)"
if $INIT; then
    if [ -n "$OLD_SNAPSHOT" ]; then
        echo "✗ This branch already sits on a snapshot. Run without --init." >&2
        exit 1
    fi
    SOURCE="$(git merge-base HEAD origin/main)"
else
    if [ -z "$OLD_SNAPSHOT" ]; then
        echo "✗ No renamed snapshot in this branch's history. Run with --init once." >&2
        exit 1
    fi
    SOURCE="$(git rev-parse origin/main)"
    if [ "$(git rev-parse "$OLD_SNAPSHOT^")" = "$SOURCE" ]; then
        echo "✓ Already on upstream ${SOURCE:0:12}."
        exit 0
    fi
fi

WORKTREE="$(mktemp -d)/tree"
trap 'git worktree remove --force "$WORKTREE" 2>/dev/null || true' EXIT
git worktree add --quiet --detach "$WORKTREE" "$SOURCE"
./Scripts/rename-upstream.sh "$WORKTREE"
git -C "$WORKTREE" add -A
TREE="$(git -C "$WORKTREE" write-tree)"
SNAPSHOT="$(git commit-tree "$TREE" -p "$SOURCE" -m "Rename upstream ${SOURCE:0:12} to Nanocast")"

if $INIT; then
    git reset --quiet "$SNAPSHOT"
    echo "✓ The branch now sits on the snapshot of ${SOURCE:0:12}. Commit your changes on top of it."
    exit 0
fi

echo "Old snapshot: $OLD_SNAPSHOT"
echo "New snapshot: $SNAPSHOT"
if ! git rebase --onto "$SNAPSHOT" "$OLD_SNAPSHOT"; then
    cat >&2 <<'EOF'
✗ The rebase stopped on a conflict. Run ./Scripts/port-upstream.sh <kept upstream commit>...,
  resolve what it reports, then run: git rebase --continue
  If Nanocast.xcodeproj conflicts, do not resolve it by hand. Run:
    git checkout --ours Nanocast.xcodeproj && xcodegen generate && git add Nanocast.xcodeproj
EOF
    exit 1
fi
echo "✓ Rebased onto upstream ${SOURCE:0:12}. Run ./Scripts/run-tests.sh, then: git push --force-with-lease"
