#!/usr/bin/env python3
import tkinter as tk
from pathlib import Path

from sticker_creator_app import StickerCreatorApp

RARITIES: tuple[str, ...] = ("Common", "Uncommon", "Rare", "Elite", "Legendary", "Unique")


class FixedRarityStickerCreatorApp(StickerCreatorApp):
    def load_lists(self) -> dict[str, list[str]]:
        lists: dict[str, list[str]] = super().load_lists()
        lists["rarities"] = list(RARITIES)
        return lists

    def build_list_editor(self, parent: tk.Misc, key: str) -> None:
        if key == "rarities":
            return
        super().build_list_editor(parent, key)

    def browse_art(self) -> None:
        super().browse_art()
        selected_art_path: str = self.art_var.get()
        if selected_art_path:
            self.name_var.set(Path(selected_art_path).stem)


def main() -> None:
    root: tk.Tk = tk.Tk()
    FixedRarityStickerCreatorApp(root)
    root.mainloop()


if __name__ == "__main__":
    main()
