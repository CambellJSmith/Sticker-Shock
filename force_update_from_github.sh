#!/usr/bin/env bash
set -Eeuo pipefail

# Destructively replaces this local working copy with the latest version of a remote branch.
# Sticker-maker generated content and local authoring settings are preserved across the update.
# Usage: ./force_update_from_github.sh [branch]
# Default branch: main

REMOTE="${REMOTE:-origin}"
BRANCH="${1:-main}"

STICKER_CONTENT_PATHS=(
    "assets/stickers/art"
    "data/stickers"
    "data/sticker_lists.tres"
    "tools/sticker_creator/sticker_lists.json"
    "tools/sticker_creator/flavour_prompt.txt"
)

show_popup() {
    local title="$1"
    local message="$2"

    if command -v zenity >/dev/null 2>&1; then
        zenity --info --title="$title" --text="$message" >/dev/null 2>&1 || true
        return
    fi

    if command -v kdialog >/dev/null 2>&1; then
        kdialog --title "$title" --msgbox "$message" >/dev/null 2>&1 || true
        return
    fi

    if command -v python3 >/dev/null 2>&1; then
        POPUP_TITLE="$title" POPUP_MESSAGE="$message" python3 - <<'PY' >/dev/null 2>&1 || true
import os
import tkinter as tk
from tkinter import messagebox

root = tk.Tk()
root.withdraw()
messagebox.showinfo(os.environ["POPUP_TITLE"], os.environ["POPUP_MESSAGE"])
root.destroy()
PY
        return
    fi

    printf '%s\n%s\n' "$title" "$message"
}

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    show_popup "Sticker-Shock updater" "Update failed: this script must be run from inside a Git repository."
    exit 1
fi

REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT"

if ! git remote get-url "$REMOTE" >/dev/null 2>&1; then
    show_popup "Sticker-Shock updater" "Update failed: Git remote '$REMOTE' does not exist."
    exit 1
fi

REMOTE_URL="$(git remote get-url "$REMOTE")"
PRESERVE_ROOT="$(mktemp -d)"
trap 'rm -rf "$PRESERVE_ROOT"' EXIT

echo "Repository: $REPO_ROOT"
echo "Remote:     $REMOTE ($REMOTE_URL)"
echo "Branch:     $BRANCH"
echo
echo "Preserving sticker-maker content..."
for content_path in "${STICKER_CONTENT_PATHS[@]}"; do
    if [[ -e "$content_path" ]]; then
        mkdir -p "$PRESERVE_ROOT/$(dirname "$content_path")"
        cp -a "$content_path" "$PRESERVE_ROOT/$content_path"
    fi
done

echo "Fetching latest remote state..."
git fetch "$REMOTE" --prune --tags

if ! git show-ref --verify --quiet "refs/remotes/$REMOTE/$BRANCH"; then
    show_popup "Sticker-Shock updater" "Update failed: remote branch '$REMOTE/$BRANCH' does not exist."
    exit 1
fi

REMOTE_COMMIT="$(git rev-parse "$REMOTE/$BRANCH")"
echo "Remote commit: $REMOTE_COMMIT"

echo "Removing non-sticker untracked and ignored working-tree files..."
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

echo "Restoring sticker-maker content..."
for content_path in "${STICKER_CONTENT_PATHS[@]}"; do
    preserved_path="$PRESERVE_ROOT/$content_path"
    if [[ -e "$preserved_path" ]]; then
        rm -rf "$content_path"
        mkdir -p "$(dirname "$content_path")"
        cp -a "$preserved_path" "$content_path"
    fi
done

git branch --set-upstream-to="$REMOTE/$BRANCH" "$BRANCH" >/dev/null 2>&1 || true

echo
echo "Force update complete."
echo "Local '$BRANCH' now matches '$REMOTE/$BRANCH' at $REMOTE_COMMIT, with local sticker-maker content preserved."
git status --short --branch

show_popup "Sticker-Shock updater" "Update complete.\n\nLocal '$BRANCH' now matches '$REMOTE/$BRANCH'.\nSticker-maker content and AI prompt were preserved.\n\nCommit: $REMOTE_COMMIT"
