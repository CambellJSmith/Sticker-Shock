#!/usr/bin/env python3
from __future__ import annotations

import shutil
import subprocess
import tkinter as tk
from datetime import datetime

from sticker_creator import FixedRarityStickerCreatorApp
from sticker_creator_app import GENERATED_PATHS, run_command


class StickerCreatorEntryApp(FixedRarityStickerCreatorApp):
    def perform_commit_workflow(self) -> str:
        if shutil.which("git") is None:
            raise RuntimeError("git is required for Commit.")
        if shutil.which("gh") is None:
            raise RuntimeError("GitHub CLI (gh) is required for Commit.")
        run_command(["gh", "auth", "status"])
        current_branch: str = run_command(["git", "branch", "--show-current"]).stdout.strip()
        if current_branch != "main":
            raise RuntimeError("Commit requires the local checkout to be on main. Run the updater first, then try again.")

        generated_changes: list[str] = [
            line
            for line in run_command(
                ["git", "status", "--porcelain", "--untracked-files=all", "--", *GENERATED_PATHS]
            ).stdout.splitlines()
            if line.strip()
        ]
        if not generated_changes:
            raise RuntimeError("There are no new sticker-tool changes to commit.")

        branch_name: str = "sticker-content-" + datetime.now().strftime("%Y%m%d-%H%M%S")
        run_command(["git", "switch", "-c", branch_name])
        run_command(["git", "add", "--", *GENERATED_PATHS])
        run_command(["git", "commit", "-m", "Add sticker content"])
        run_command(["git", "push", "-u", "origin", branch_name])
        pr_result: subprocess.CompletedProcess[str] = run_command([
            "gh", "pr", "create",
            "--base", "main",
            "--head", branch_name,
            "--title", "Add sticker content",
            "--body", "Adds sticker content created by the standalone Sticker-Shock sticker tool.",
        ])
        pr_url: str = pr_result.stdout.strip().splitlines()[-1]
        run_command(["gh", "pr", "merge", pr_url, "--squash", "--delete-branch"])
        run_command(["git", "switch", "main"])
        run_command(["git", "fetch", "origin", "main"])
        run_command(["git", "pull", "--ff-only", "origin", "main"])
        return "Sticker content committed, PR created, and merged into main."


def main() -> None:
    root: tk.Tk = tk.Tk()
    StickerCreatorEntryApp(root)
    root.mainloop()


if __name__ == "__main__":
    main()
