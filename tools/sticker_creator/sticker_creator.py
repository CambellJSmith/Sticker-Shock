#!/usr/bin/env python3
import re
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
    read_field,
    slugify,
    valid_png,
)

RARITIES: tuple[str, ...] = ("Common", "Uncommon", "Rare", "Elite", "Legendary", "Unique")
BATCH_RARITIES: tuple[str, ...] = ("Common", "Uncommon", "Rare", "Elite", "Legendary")


class FixedRarityStickerCreatorApp(StickerCreatorApp):
    def __init__(self, root: tk.Tk) -> None:
        super().__init__(root)
        self.batch_import_button: ttk.Button = ttk.Button(
            self.description_text.master,
            text="batch import folder",
            command=self.open_batch_import,
        )
        self.batch_import_button.grid(row=3, column=3, sticky="new", padx=(8, 0), pady=4)
        self._editing_id: int | None = None
        self._editing_definition_path: Path | None = None
        self._editing_art_path: Path | None = None
        self._batch_busy: bool = False
        self._add_existing_sticker_controls()

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

    def next_sticker_id(self) -> int:
        used_ids: set[int] = self.existing_ids()
        candidate: int = 1
        while candidate in used_ids:
            candidate += 1
        return candidate

    def _add_existing_sticker_controls(self) -> None:
        parent: tk.Misc = self.sticker_tree.master
        controls: ttk.Frame = ttk.Frame(parent, style="Panel.TFrame")
        controls.grid(row=1, column=0, columnspan=2, sticky="ew", pady=(7, 0))
        ttk.Label(controls, text="select a sticker to edit or delete", style="Muted.TLabel").pack(side="left")
        ttk.Button(controls, text="delete", command=self.delete_selected_sticker).pack(side="right")
        ttk.Button(controls, text="edit", command=self.edit_selected_sticker).pack(side="right", padx=(0, 6))
        self.sticker_tree.bind("<Double-1>", lambda _event: self.edit_selected_sticker())

    def _selected_sticker_id(self) -> int | None:
        selection: tuple[str, ...] = self.sticker_tree.selection()
        if not selection:
            return None
        values: tuple[object, ...] = tuple(self.sticker_tree.item(selection[0], "values"))
        if not values:
            return None
        try:
            return int(str(values[0]))
        except ValueError:
            return None

    def _resource_for_id(self, sticker_id: int) -> Path | None:
        for resource_path in DEFINITION_ROOT.glob("*.tres"):
            try:
                resource_text: str = resource_path.read_text(encoding="utf-8")
            except OSError:
                continue
            if read_field(resource_text, "id") == str(sticker_id):
                return resource_path
        return None

    def _art_path_from_resource(self, resource_text: str) -> Path | None:
        match: re.Match[str] | None = re.search(
            r'\[ext_resource type="Texture2D" path="res://assets/stickers/art/([^"]+)"',
            resource_text,
        )
        if match is None:
            return None
        return ART_ROOT / match.group(1)

    def edit_selected_sticker(self) -> None:
        sticker_id: int | None = self._selected_sticker_id()
        if sticker_id is None:
            messagebox.showerror("Sticker Creator", "Select a sticker first.", parent=self.root)
            return
        resource_path: Path | None = self._resource_for_id(sticker_id)
        if resource_path is None:
            messagebox.showerror("Sticker Creator", "The selected sticker resource could not be found.", parent=self.root)
            return
        try:
            resource_text: str = resource_path.read_text(encoding="utf-8")
        except OSError as error:
            messagebox.showerror("Sticker Creator", str(error), parent=self.root)
            return
        art_path: Path | None = self._art_path_from_resource(resource_text)
        if art_path is None or not art_path.is_file():
            messagebox.showerror("Sticker Creator", "The selected sticker art could not be found.", parent=self.root)
            return
        self._editing_id = sticker_id
        self._editing_definition_path = resource_path
        self._editing_art_path = art_path
        self.next_id_var.set(str(sticker_id))
        self.name_var.set(read_field(resource_text, "name"))
        self.art_var.set(str(art_path))
        self.description_text.delete("1.0", tk.END)
        self.description_text.insert("1.0", read_field(resource_text, "description"))
        self.pack_var.set(read_field(resource_text, "pack"))
        self.artist_var.set(read_field(resource_text, "artist"))
        self.rarity_var.set(read_field(resource_text, "rarity"))
        self.status_var.set(f"editing #{sticker_id:06d} · create sticker will save changes")

    def delete_selected_sticker(self) -> None:
        sticker_id: int | None = self._selected_sticker_id()
        if sticker_id is None:
            messagebox.showerror("Sticker Creator", "Select a sticker first.", parent=self.root)
            return
        resource_path: Path | None = self._resource_for_id(sticker_id)
        if resource_path is None:
            messagebox.showerror("Sticker Creator", "The selected sticker resource could not be found.", parent=self.root)
            return
        try:
            resource_text: str = resource_path.read_text(encoding="utf-8")
        except OSError as error:
            messagebox.showerror("Sticker Creator", str(error), parent=self.root)
            return
        sticker_name: str = read_field(resource_text, "name")
        if not messagebox.askyesno(
            "Delete sticker",
            f"Delete #{sticker_id:06d} · {sticker_name}?\n\nIts resource and PNG art will both be removed, and this ID will become available for the next created sticker.",
            parent=self.root,
        ):
            return
        art_path: Path | None = self._art_path_from_resource(resource_text)
        try:
            resource_path.unlink(missing_ok=True)
            if art_path is not None:
                art_path.unlink(missing_ok=True)
        except OSError as error:
            messagebox.showerror("Sticker Creator", f"Could not delete the sticker.\n\n{error}", parent=self.root)
            return
        if self._editing_id == sticker_id:
            self._clear_edit_state()
        self.refresh_existing_stickers()
        self.clear_form()
        self.status_var.set(f"deleted #{sticker_id:06d} · id is available again")

    def create_sticker(self) -> None:
        if self._editing_id is None:
            super().create_sticker()
            return
        self._save_edited_sticker()

    def _save_edited_sticker(self) -> None:
        error: str = self.validate_form()
        if error:
            messagebox.showerror("cannot save sticker", error, parent=self.root)
            return
        sticker_id: int = int(self._editing_id)
        old_definition: Path | None = self._editing_definition_path
        old_art: Path | None = self._editing_art_path
        sticker_name: str = self.name_var.get().strip()
        source_art: Path = Path(self.art_var.get())
        description: str = self.description_text.get("1.0", tk.END).strip()
        base_name: str = f"{sticker_id:06d}_{slugify(sticker_name)}"
        art_filename: str = base_name + ".png"
        destination_art: Path = ART_ROOT / art_filename
        destination_definition: Path = DEFINITION_ROOT / (base_name + ".tres")
        try:
            if old_art is not None and source_art.resolve() == old_art.resolve():
                if destination_art != old_art:
                    destination_art.write_bytes(old_art.read_bytes())
            else:
                quantize_png(source_art, destination_art)
        except (OSError, ValueError) as art_error:
            messagebox.showerror("art processing failed", str(art_error), parent=self.root)
            return
        definition_text: str = self._build_definition_text(
            sticker_id,
            sticker_name,
            art_filename,
            description,
            self.pack_var.get(),
            self.artist_var.get(),
            self.rarity_var.get(),
        )
        try:
            atomic_write(destination_definition, definition_text)
            if old_definition is not None and old_definition != destination_definition:
                old_definition.unlink(missing_ok=True)
            if old_art is not None and old_art != destination_art:
                old_art.unlink(missing_ok=True)
        except OSError as error:
            messagebox.showerror("save failed", str(error), parent=self.root)
            return
        self._clear_edit_state()
        self.refresh_existing_stickers()
        self.clear_form()
        self.status_var.set(f"saved changes to #{sticker_id:06d}")

    def _build_definition_text(
        self,
        sticker_id: int,
        sticker_name: str,
        art_filename: str,
        description: str,
        pack_name: str,
        artist_name: str,
        rarity: str,
    ) -> str:
        return (
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

    def clear_form(self) -> None:
        self._clear_edit_state()
        super().clear_form()

    def _clear_edit_state(self) -> None:
        self._editing_id = None
        self._editing_definition_path = None
        self._editing_art_path = None

    def open_batch_import(self) -> None:
        if self._batch_busy:
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
        ttk.Combobox(frame, textvariable=pack_var, state="readonly", values=self.lists["packs"]).grid(row=2, column=1, sticky="ew", pady=5)
        ttk.Label(frame, text="artist").grid(row=3, column=0, sticky="w", padx=(0, 12), pady=5)
        ttk.Combobox(frame, textvariable=artist_var, state="readonly", values=self.lists["artists"]).grid(row=3, column=1, sticky="ew", pady=5)
        rarity_text: str = " → ".join(BATCH_RARITIES) + " → repeat"
        ttk.Label(frame, text="rarity cycle").grid(row=4, column=0, sticky="nw", padx=(0, 12), pady=5)
        ttk.Label(frame, text=rarity_text, wraplength=400).grid(row=4, column=1, sticky="w", pady=5)
        ttk.Label(
            frame,
            text="Names come from filenames. Each image is quantized to 256 colors. Descriptions are left blank for manual editing.",
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

    def _start_batch_import(self, batch_window: tk.Toplevel, png_paths: list[Path], pack_name: str, artist_name: str) -> None:
        if pack_name not in self.lists["packs"] or artist_name not in self.lists["artists"]:
            messagebox.showerror("Sticker Creator", "Choose a valid pack and artist.", parent=batch_window)
            return
        batch_window.destroy()
        self._batch_busy = True
        self.batch_import_button.state(["disabled"])
        self.status_var.set(f"batch import · 0/{len(png_paths)}")
        threading.Thread(
            target=self._batch_import_worker,
            args=(png_paths, pack_name, artist_name),
            daemon=True,
        ).start()

    def _batch_import_worker(self, png_paths: list[Path], pack_name: str, artist_name: str) -> None:
        created_count: int = 0
        try:
            for index, source_art in enumerate(png_paths):
                sticker_id: int = self.next_sticker_id()
                sticker_name: str = source_art.stem
                rarity: str = BATCH_RARITIES[index % len(BATCH_RARITIES)]
                self.root.after(
                    0,
                    lambda current=index + 1, total=len(png_paths), name=sticker_name, current_rarity=rarity: self.status_var.set(
                        f"batch import · {current}/{total} · {name} · {current_rarity}"
                    ),
                )
                self._create_batch_sticker(sticker_id, sticker_name, source_art, pack_name, artist_name, rarity)
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
        pack_name: str,
        artist_name: str,
        rarity: str,
    ) -> None:
        base_name: str = f"{sticker_id:06d}_{slugify(sticker_name)}"
        art_filename: str = base_name + ".png"
        destination_art: Path = ART_ROOT / art_filename
        destination_definition: Path = DEFINITION_ROOT / (base_name + ".tres")
        quantize_png(source_art, destination_art)
        try:
            atomic_write(
                destination_definition,
                self._build_definition_text(sticker_id, sticker_name, art_filename, "", pack_name, artist_name, rarity),
            )
        except OSError:
            destination_art.unlink(missing_ok=True)
            raise

    def _batch_import_complete(self, created_count: int) -> None:
        self._batch_busy = False
        self.batch_import_button.state(["!disabled"])
        self.refresh_existing_stickers()
        self.status_var.set(f"batch import complete · created {created_count} stickers")
        messagebox.showinfo(
            "Sticker Creator · Batch Import",
            f"Created {created_count} stickers.\n\nEach PNG was named from its filename, assigned a cycling rarity, quantized, and created with a blank description.",
            parent=self.root,
        )

    def _batch_import_failed(self, created_count: int, error_message: str) -> None:
        self._batch_busy = False
        self.batch_import_button.state(["!disabled"])
        self.refresh_existing_stickers()
        self.status_var.set(f"batch import stopped · {created_count} stickers created")
        messagebox.showerror(
            "Sticker Creator · Batch Import",
            f"Batch import stopped after creating {created_count} stickers.\n\n{error_message}",
            parent=self.root,
        )


def main() -> None:
    root: tk.Tk = tk.Tk()
    FixedRarityStickerCreatorApp(root)
    root.mainloop()


if __name__ == "__main__":
    main()
