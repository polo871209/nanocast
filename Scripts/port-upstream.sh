#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

[ $# -gt 0 ] || { echo "usage: port-upstream.sh <kept upstream commit>..." >&2; exit 2; }
git rev-parse -q --verify REBASE_HEAD >/dev/null || {
    echo "✗ No rebase is stopped on a conflict." >&2
    exit 1
}

KEPT=()
while IFS= read -r commit; do KEPT+=("$commit"); done < <(git rev-list --no-walk=sorted --reverse "$@")
SCRATCH="$(mktemp -d)"
trap 'rm -rf "$SCRATCH"' EXIT

upstream_path() { sed -e 's/Nanocast/Tinycast/g' -e 's/nanocast/tinycast/g' <<<"$1"; }
renamed() { git show "$1" | ./Scripts/rename-upstream.sh --stdin; }

git diff --name-only --diff-filter=U | while IFS= read -r path; do
    state="$(git status --porcelain -- "$path" | cut -c1-2)"
    case "$path" in
    *.xcodeproj/*)
        echo "skip      $path  (regenerate with xcodegen)"
        continue
        ;;
    esac
    case "$state" in
    UD)
        git rm -q -- "$path"
        echo "deleted   $path"
        continue
        ;;
    UU | AA) ;;
    *)
        echo "by hand   $path  ($state)"
        continue
        ;;
    esac

    git checkout -q --theirs -- "$path"
    upstream="$(upstream_path "$path")"
    ported=()
    conflicts=0
    for commit in "${KEPT[@]}"; do
        git diff-tree --no-commit-id --name-only -r "$commit" -- "$upstream" | grep -q . || continue
        if ! git cat-file -e "$commit^:$upstream" 2>/dev/null || ! git cat-file -e "$commit:$upstream" 2>/dev/null; then
            ported+=("${commit:0:8}(added-or-deleted)")
            conflicts=$((conflicts + 1))
            continue
        fi
        renamed "$commit^:$upstream" >"$SCRATCH/base"
        renamed "$commit:$upstream" >"$SCRATCH/other"
        status=0
        git merge-file --diff3 -L fork -L "${commit:0:8}^" -L "${commit:0:8}" \
            "$path" "$SCRATCH/base" "$SCRATCH/other" || status=$?
        conflicts=$((conflicts + status))
        ported+=("${commit:0:8}")
    done

    if [ "$conflicts" -eq 0 ]; then
        git add -- "$path"
        echo "fork${ported[*]+ + ${ported[*]}}  $path"
    else
        echo "CONFLICT  $path  fork + ${ported[*]-}: $conflicts left"
    fi
done
