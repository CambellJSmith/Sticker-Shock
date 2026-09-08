#!/usr/bin/env python3
import threading
import tkinter as tk
from pathlib import Path
from tkinter import messagebox, ttk

from sticker_creator_app import StickerCreatorApp
from vision_flavour import ensure_model_cached, generate_flavour_text

RARITIES: tuple[str, ...] = ("Common", "Uncommon", "Rare", "Elite", "Legendary", "Unique")


class FixedRarityStickerCreatorApp(StickerCreatorApp):
    def __init__(self, root: tk.Tk) -> None:
        super().__init__(root)
        self.generate_description_button: ttk.Button = ttk.Button(
            self.description_text.master,
            text="generate from art",
            command=self.generate_description,
        )
        self.generate_description_button.grid(row=3, column=3, sticky="ns", padx=(8, 0), pady=4)
        self.generate_description_button.state(["disabled"])
        self._vision_ready: bool = False
        self._vision_busy: bool = False
        self._start_vision_setup()

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

    def generate_description(self) -> None:
        if self._vision_busy or not self._vision_ready:
            return
        art_path: Path = Path(self.art_var.get())
        if not art_path.is_file() or art_path.suffix.lower() != ".png":
            messagebox.showerror("Sticker Creator", "Select a valid PNG before generating a description.", parent=self.root)
            return
        self._vision_busy = True
        self.generate_description_button.state(["disabled"])
        self.status_var.set("local vision model is reading the sticker art…")
        worker: threading.Thread = threading.Thread(
            target=self._generate_description_worker,
            args=(art_path, self.name_var.get(), self.pack_var.get(), self.rarity_var.get()),
            daemon=True,
        )
        worker.start()

    def _start_vision_setup(self) -> None:
        self.status_var.set("setting up local vision model on this computer…")
        worker: threading.Thread = threading.Thread(target=self._vision_setup_worker, daemon=True)
        worker.start()

    def _vision_setup_worker(self) -> None:
        try:
            ensure_model_cached()
        except Exception as error:
            self.root.after(0, self._vision_setup_failed, str(error))
            return
        self.root.after(0, self._vision_setup_complete)

    def _vision_setup_complete(self) -> None:
        self._vision_ready = True
        self.generate_description_button.state(["!disabled"])
        self.status_var.set("ready · local vision flavour generator available")

    def _vision_setup_failed(self, error_message: str) -> None:
        self._vision_ready = False
        self.generate_description_button.state(["disabled"])
        self.status_var.set("vision setup failed · sticker creation still works normally")
        messagebox.showerror(
            "Sticker Creator · vision setup",
            "The local vision model could not be prepared.\n\nSticker creation still works normally.\n\n" + error_message,
            parent=self.root,
        )

    def _generate_description_worker(self, art_path: Path, sticker_name: str, pack_name: str, rarity: str) -> None:
        try:
            description: str = generate_flavour_text(art_path, sticker_name, pack_name, rarity)
        except Exception as error:
            self.root.after(0, self._description_generation_failed, str(error))
            return
        self.root.after(0, self._description_generation_complete, description)

    def _description_generation_complete(self, description: str) -> None:
        self._vision_busy = False
        self.generate_description_button.state(["!disabled"])
        if not description:
            self.status_var.set("vision model returned no description")
            return
        self.description_text.delete("1.0", tk.END)
        self.description_text.insert("1.0", description)
        self.status_var.set("description generated locally · edit it freely before creating the sticker")

    def _description_generation_failed(self, error_message: str) -> None:
        self._vision_busy = False
        if self._vision_ready:
            self.generate_description_button.state(["!disabled"])
        self.status_var.set("description generation failed")
        messagebox.showerror(
            "Sticker Creator · description generation",
            "The local vision model could not generate flavour text.\n\n" + error_message,
            parent=self.root,
        )


def main() -> None:
    root: tk.Tk = tk.Tk()
    FixedRarityStickerCreatorApp(root)
    root.mainloop()


if __name__ == "__main__":
    main()
