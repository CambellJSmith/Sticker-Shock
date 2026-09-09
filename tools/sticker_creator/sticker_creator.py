#!/usr/bin/env python3
import threading
import tkinter as tk
from pathlib import Path
from tkinter import filedialog, messagebox, ttk

from sticker_creator_app import (
    ART_ROOT,
    DEFINITION_ROOT,
    DEFINITION_SCRIPT_PATH,
    StickerCreatorApp,
    atomic_write,
    godot_quote,
    quantize_png,
    slugify,
    valid_png,
)
from vision_flavour import ensure_model_cached, generate_flavour_text, load_base_prompt, save_base_prompt

RARITIES: tuple[str, ...] = ("Common", "Uncommon", "Rare", "Elite", "Legendary", "Unique")
BATCH_RARITIES: tuple[str, ...] = ("Common", "Uncommon", "Rare", "Elite", "Legendary")


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
        self.edit_prompt_button: ttk.Button = ttk.Button(
            self.description_text.master,
            text="edit ai prompt",
            command=self.edit_ai_prompt,
        )
        self.edit_prompt_button.grid(row=4, column=3, sticky="new", padx=(8, 0), pady=(0, 4))
        self.batch_import_button: ttk.Button = ttk.Button(
            self.description_text.master,
            text="batch import folder",
            command=self.open_batch_import,
        )
        self.batch_import_button.grid(row=5, column=3, sticky="new", padx=(8, 0), pady=4)
        self._vision_ready: bool = False
        self._vision_busy: bool = False
        self._batch_busy: bool = False
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

    def edit_ai_prompt(self) -> None:
        prompt_window: tk.Toplevel = tk.Toplevel(self.root)
        prompt_window.title("Sticker Creator · AI flavour prompt")
        prompt_window.geometry("720x420")
        prompt_window.minsize(520, 300)
        prompt_window.transient(self.root)
        prompt_window.grab_set()
        prompt_frame: ttk.Frame = ttk.Frame(prompt_window, padding=12)
        prompt_frame.pack(fill="both", expand=True)
        prompt_label: ttk.Label = ttk.Label(prompt_frame, text="Base prompt used for every generated description")
        prompt_label.pack(anchor="w", pady=(0, 8))
        prompt_text: tk.Text = tk.Text(prompt_frame, wrap="word", undo=True)
        prompt_text.pack(fill="both", expand=True)
        prompt_text.insert("1.0", load_base_prompt())
        button_frame: ttk.Frame = ttk.Frame(prompt_frame)
        button_frame.pack(fill="x", pady=(10, 0))
        cancel_button: ttk.Button = ttk.Button(button_frame, text="cancel", command=prompt_window.destroy)
        cancel_button.pack(side="right")
        save_button: ttk.Button = ttk.Button(
            button_frame,
            text="save prompt",
            command=lambda: self._save_ai_prompt(prompt_window, prompt_text),
        )
        save_button.pack(side="right", padx=(0, 8))

    def _save_ai_prompt(self, prompt_window: tk.Toplevel, prompt_text: tk.Text) -> None:
        prompt: str = prompt_text.get("1.0", tk.END).strip()
        if not prompt:
            messagebox.showerror("Sticker Creator", "The AI base prompt cannot be empty.", parent=prompt_window)
            return
        try:
            save_base_prompt(prompt)
        except OSError as error:
            messagebox.showerror("Sticker Creator", f"Could not save the AI prompt.\n\n{error}", parent=prompt_window)
            return
        prompt_window.destroy()
        self.status_var.set("ai flavour prompt saved · future generations will use it")

    def open_batch_import(self) -> None:
        if self._batch_busy:
            return
        if not self._vision_ready:
            messagebox.showerror(
                "Sticker Creator",
                "The local vision model must be ready before batch import can start.",
                parent=self.root,
            )
            return
        selected_folder: str = filedialog.askdirectory(parent=self.root, title="select folder of named PNG stickers")
        if not selected_folder:
            return
        folder_path: Path = Path(selected_folder)
        png_paths: list[Path] = sorted(
            [path for path in folder_path.iterdir() if valid_png(path)],
            key=lambda path: path.name.casefold(),
        )
        if not png_paths:
            messagebox.showerror("Sticker Creator", "The selected folder contains no valid PNG files.", parent=self.root)
            return
        if not self.lists["packs"]:
            messagebox.showerror("Sticker Creator", "Create at least one pack before batch importing.", parent=self.root)
            return
        if not self.lists["artists"]:
            messagebox.showerror("Sticker Creator", "Create at least one artist before batch importing.", parent=self.root)
            return

        batch_window: tk.Toplevel = tk.Toplevel(self.root)
        batch_window.title("Sticker Creator · Batch Import")
        batch_window.geometry("620x330")
        batch_window.minsize(520, 300)
        batch_window.transient(self.root)
        batch_window.grab_set()

        frame: ttk.Frame = ttk.Frame(batch_window, padding=14)
        frame.pack(fill="both", expand=True)
        frame.columnconfigure(1, weight=1)
        ttk.Label(frame, text="folder").grid(row=0, column=0, sticky="w", padx=(0, 12), pady=5)
        ttk.Label(frame, text=str(folder_path)).grid(row=0, column=1, sticky="w", pady=5)
        ttk.Label(frame, text="png files").grid(row=1, column=0, sticky="w", padx=(0, 12), pady=5)
        ttk.Label(frame, text=str(len(png_paths))).grid(row=1, column=1, sticky="w", pady=5)

        pack_var: tk.StringVar = tk.StringVar(value=self.pack_var.get() if self.pack_var.get() in self.lists["packs"] else self.lists["packs"][0])
        artist_var: tk.StringVar = tk.StringVar(value=self.artist_var.get() if self.artist_var.get() in self.lists["artists"] else self.lists["artists"][0])
        ttk.Label(frame, text="pack").grid(row=2, column=0, sticky="w", padx=(0, 12), pady=5)
        pack_combo: ttk.Combobox = ttk.Combobox(frame, textvariable=pack_var, state="readonly", values=self.lists["packs"])
        pack_combo.grid(row=2, column=1, sticky="ew", pady=5)
        ttk.Label(frame, text="artist").grid(row=3, column=0, sticky="w", padx=(0, 12), pady=5)
        artist_combo: ttk.Combobox = ttk.Combobox(frame, textvariable=artist_var, state="readonly", values=self.lists["artists"])
        artist_combo.grid(row=3, column=1, sticky="ew", pady=5)

        rarity_text: str = " → ".join(BATCH_RARITIES) + " → repeat"
        ttk.Label(frame, text="rarity cycle").grid(row=4, column=0, sticky="nw", padx=(0, 12), pady=5)
        ttk.Label(frame, text=rarity_text, wraplength=400).grid(row=4, column=1, sticky="w", pady=5)
        ttk.Label(
            frame,
            text="Names come from filenames. Each image is quantized to 256 colors and analysed by the local AI before its sticker is created.",
            wraplength=560,
        ).grid(row=5, column=0, columnspan=2, sticky="w", pady=(10, 12))

        button_frame: ttk.Frame = ttk.Frame(frame)
        button_frame.grid(row=6, column=0, columnspan=2, sticky="ew", pady=(8, 0))
        ttk.Button(button_frame, text="cancel", command=batch_window.destroy).pack(side="right")
        ttk.Button(
            button_frame,
            text=f"import {len(png_paths)} stickers",
            style="Accent.TButton",
            command=lambda: self._start_batch_import(batch_window, png_paths, pack_var.get(), artist_var.get()),
        ).pack(side="right", padx=(0, 8))

    def _start_batch_import(
        self,
        batch_window: tk.Toplevel,
        png_paths: list[Path],
        pack_name: str,
        artist_name: str,
    ) -> None:
        if pack_name not in self.lists["packs"] or artist_name not in self.lists["artists"]:
            messagebox.showerror("Sticker Creator", "Choose a valid pack and artist.", parent=batch_window)
            return
        batch_window.destroy()
        self._batch_busy = True
        self.batch_import_button.state(["disabled"])
        self.generate_description_button.state(["disabled"])
        self.status_var.set(f"batch import · 0/{len(png_paths)}")
        worker: threading.Thread = threading.Thread(
            target=self._batch_import_worker,
            args=(png_paths, pack_name, artist_name),
            daemon=True,
        )
        worker.start()

    def _batch_import_worker(self, png_paths: list[Path], pack_name: str, artist_name: str) -> None:
        created_count: int = 0
        starting_id: int = self.next_sticker_id()
        try:
            for index, source_art in enumerate(png_paths):
                sticker_id: int = starting_id + index
                sticker_name: str = source_art.stem
                rarity: str = BATCH_RARITIES[index % len(BATCH_RARITIES)]
                self.root.after(
                    0,
                    lambda current=index + 1, total=len(png_paths), name=sticker_name, current_rarity=rarity: self.status_var.set(
                        f"batch import · {current}/{total} · {name} · {current_rarity} · generating description…"
                    ),
                )
                description: str = generate_flavour_text(source_art, sticker_name, pack_name, rarity)
                if not description:
                    raise RuntimeError(f"AI returned no description for {source_art.name}.")
                self._create_batch_sticker(
                    sticker_id=sticker_id,
                    sticker_name=sticker_name,
                    source_art=source_art,
                    description=description,
                    pack_name=pack_name,
                    artist_name=artist_name,
                    rarity=rarity,
                )
                created_count += 1
        except Exception as error:
            self.root.after(0, lambda: self._batch_import_failed(created_count, str(error)))
            return
        self.root.after(0, lambda: self._batch_import_complete(created_count))

    def _create_batch_sticker(
        self,
        sticker_id: int,
        sticker_name: str,
        source_art: Path,
        description: str,
        pack_name: str,
        artist_name: str,
        rarity: str,
    ) -> None:
        base_name: str = f"{sticker_id:06d}_{slugify(sticker_name)}"
        art_filename: str = base_name + ".png"
        destination_art: Path = ART_ROOT / art_filename
        destination_definition: Path = DEFINITION_ROOT / (base_name + ".tres")
        quantize_png(source_art, destination_art)
        definition_text: str = (
            '[gd_resource type="Resource" script_class="StickerDefinition" load_steps=3 format=3]\n\n'
            f'[ext_resource type="Script" path="{DEFINITION_SCRIPT_PATH}" id="1_definition"]\n'
            f'[ext_resource type="Texture2D" path="res://assets/stickers/art/{art_filename}" id="2_art"]\n\n'
            '[resource]\nscript = ExtResource("1_definition")\n'
            f'id = {sticker_id}\n'
            f'name = {godot_quote(sticker_name)}\n'
            'art = ExtResource("2_art")\n'
            f'description = {godot_quote(description)}\n'
            f'pack = {godot_quote(pack_name)}\n'
            f'artist = {godot_quote(artist_name)}\n'
            f'rarity = {godot_quote(rarity)}\n'
        )
        try:
            atomic_write(destination_definition, definition_text)
        except OSError:
            destination_art.unlink(missing_ok=True)
            raise

    def _batch_import_complete(self, created_count: int) -> None:
        self._batch_busy = False
        self.batch_import_button.state(["!disabled"])
        if self._vision_ready and not self._vision_busy:
            self.generate_description_button.state(["!disabled"])
        self.refresh_existing_stickers()
        self.status_var.set(f"batch import complete · created {created_count} stickers")
        messagebox.showinfo(
            "Sticker Creator · Batch Import",
            f"Created {created_count} stickers.\n\nEach PNG was named from its filename, assigned a cycling rarity, quantized, and given an AI-generated description.",
            parent=self.root,
        )

    def _batch_import_failed(self, created_count: int, error_message: str) -> None:
        self._batch_busy = False
        self.batch_import_button.state(["!disabled"])
        if self._vision_ready and not self._vision_busy:
            self.generate_description_button.state(["!disabled"])
        self.refresh_existing_stickers()
        self.status_var.set(f"batch import stopped · {created_count} stickers created")
        messagebox.showerror(
            "Sticker Creator · Batch Import",
            f"Batch import stopped after creating {created_count} stickers.\n\n{error_message}",
            parent=self.root,
        )

    def generate_description(self) -> None:
        if self._vision_busy or self._batch_busy or not self._vision_ready:
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
        if not self._batch_busy:
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
        if not self._batch_busy:
            self.generate_description_button.state(["!disabled"])
        if not description:
            self.status_var.set("vision model returned no description")
            return
        self.description_text.delete("1.0", tk.END)
        self.description_text.insert("1.0", description)
        self.status_var.set("description generated locally · edit it freely before creating the sticker")

    def _description_generation_failed(self, error_message: str) -> None:
        self._vision_busy = False
        if self._vision_ready and not self._batch_busy:
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
