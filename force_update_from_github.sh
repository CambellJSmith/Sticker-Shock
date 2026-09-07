#!/usr/bin/env bash
set -Eeuo pipefail

# Destructively replace this local working copy with the latest version of a remote branch.
# Usage: ./force_update_from_github.sh [branch]
# Default branch: main
# Set FORCE_UPDATE_YES=1 to skip the interactive confirmation.

REMOTE="${REMOTE:-origin}"
BRANCH="${1:-main}"

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "Error: this script must be run from inside a Git repository." >&2
    exit 1
fi

REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT"

if ! git remote get-url "$REMOTE" >/dev/null 2>&1; then
    echo "Error: Git remote '$REMOTE' does not exist." >&2
    exit 1
fi

REMOTE_URL="$(git remote get-url "$REMOTE")"

echo "Repository: $REPO_ROOT"
echo "Remote:     $REMOTE ($REMOTE_URL)"
echo "Branch:     $BRANCH"
echo
echo "WARNING: this is destructive."
echo "It will permanently discard ALL local tracked changes, untracked files,"
echo "ignored files, and directories in the working tree so it exactly matches"
echo "$REMOTE/$BRANCH. Local commits that are not on the remote will no longer"
echo "be checked out. The .git directory itself is not deleted."
echo

if [[ "${FORCE_UPDATE_YES:-0}" != "1" ]]; then
    read -r -p "Type FORCE to continue: " CONFIRMATION
    if [[ "$CONFIRMATION" != "FORCE" ]]; then
        echo "Cancelled."
        exit 0
    fi
fi

echo "Fetching latest remote state..."
git fetch "$REMOTE" --prune --tags

if ! git show-ref --verify --quiet "refs/remotes/$REMOTE/$BRANCH"; then
    echo "Error: remote branch '$REMOTE/$BRANCH' does not exist." >&2
    exit 1
fi

REMOTE_COMMIT="$(git rev-parse "$REMOTE/$BRANCH")"
echo "Remote commit: $REMOTE_COMMIT"

echo "Removing all untracked and ignored working-tree files..."
git clean -ffdx

echo "Forcing local branch '$BRANCH' to '$REMOTE/$BRANCH'..."
git checkout -f -B "$BRANCH" "$REMOTE/$BRANCH"
git reset --hard "$REMOTE/$BRANCH"

echo "Cleaning the working tree again..."
git clean -ffdx

if [[ -f .gitmodules ]]; then
    echo "Synchronizing submodules..."
    git submodule sync --recursive
    git submodule update --init --recursive --force
    git submodule foreach --recursive 'git reset --hard && git clean -ffdx'
fi

git branch --set-upstream-to="$REMOTE/$BRANCH" "$BRANCH" >/dev/null 2>&1 || true

echo
echo "Force update complete."
echo "Local '$BRANCH' now matches '$REMOTE/$BRANCH' at $REMOTE_COMMIT."
git status --short --branch
