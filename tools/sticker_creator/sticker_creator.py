#!/usr/bin/env python3

from __future__ import annotations

import json
import re
import shutil
import tkinter as tk
from pathlib import Path
from tkinter import filedialog, messagebox, simpledialog, ttk

REPO_ROOT: Path = Path(__file__).resolve().parents[2]
TOOL_ROOT: Path = Path(__file__).resolve().parent
LISTS_JSON_PATH: Path = TOOL_ROOT / "sticker_lists.json"
LISTS_RESOURCE_PATH: Path = REPO_ROOT / "data" / "sticker_lists.tres"
DEFINITION_ROOT: Path = REPO_ROOT / "data" / "stickers"
ART_ROOT: Path = REPO_ROOT / "assets" / "stickers" / "art"
DEFINITION_SCRIPT_PATH: str = "res://scripts/data/sticker_definition.gd"
LISTS_SCRIPT_PATH: str = "res://scripts/data/sticker_lists.gd"
PNG_SIGNATURE: bytes = b"\x89PNG\r\n\x1a\n"


def _godot_quote(value: str) -> str:
    return json.dumps(value, ensure_ascii=False)


def _godot_string_array(values: list[str]) -> str:
    quoted_values: str = ", ".join(_godot_quote(value) for value in values)
    return f"PackedStringArray([{quoted_values}])"


def _slugify(value: str) -> str:
    normalized: str = value.strip().lower()
    normalized = re.sub(r"[^a-z0-9]+", "_", normalized)
    normalized = normalized.strip("_")
    return normalized if normalized else "sticker"


def _atomic_write_text(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary_path: Path = path.with_suffix(path.suffix + ".tmp")
    temporary_path.write_text(content, encoding="utf-8")
    temporary_path.replace(path)


def _is_png(path: Path) -> bool:
    if path.suffix.lower() != ".png" or not path.is_file():
        return False
    try:
        with path.open("rb") as source_file:
            return source_file.read(len(PNG_SIGNATURE)) == PNG_SIGNATURE
    except OSError:
        return False


def _read_generated_field(resource_text: str, field_name: str) -> str:
    match: re.Match[str] | None = re.search(rf"^{re.escape(field_name)} = (.+)$", resource_text, re.MULTILINE)
    if match is None:
        return ""
    raw_value: str = match.group(1).strip()
    try:
        decoded_value: object = json.loads(raw_value)
        return str(decoded_value)
    except json.JSONDecodeError:
        return raw_value.strip('"')


class StickerCreatorApp:
    def __init__(self, root: tk.Tk) -> None:
        self.root: tk.Tk = root
        self.root.title("Sticker-Shock Sticker Creator")
        self.root.geometry("1180x760")
        self.root.minsize(980, 650)
        self.lists: dict[str, list[str]] = self._load_lists()
        self.listboxes: dict[str, tk.Listbox] = {}
        self.comboboxes: dict[str, ttk.Combobox] = {}
        self.id_var: tk.StringVar = tk.StringVar()
        self.name_var: tk.StringVar = tk.StringVar()
        self.art_var: tk.StringVar = tk.StringVar()
        self.pack_var: tk.StringVar = tk.StringVar()
        self.artist_var: tk.StringVar = tk.StringVar()
        self.rarity_var: tk.StringVar = tk.StringVar()
        self.status_var: tk.StringVar = tk.StringVar(value="ready")
        self.description_text: tk.Text
        self.sticker_tree: ttk.Treeview
        self._ensure_project_folders()
        self._configure_style()
        self._build_ui()
        self._refresh_lists_ui()
        self._refresh_existing_stickers()

    def _ensure_project_folders(self) -> None:
        DEFINITION_ROOT.mkdir(parents=True, exist_ok=True)
        ART_ROOT.mkdir(parents=True, exist_ok=True)

    def _configure_style(self) -> None:
        self.root.configure(bg="#202124")
        style: ttk.Style = ttk.Style(self.root)
        try:
            style.theme_use("clam")
        except tk.TclError:
            pass
        style.configure("TFrame", background="#202124")
        style.configure("Panel.TFrame", background="#2b2d30")
        style.configure("TLabel", background="#202124", foreground="#e8eaed")
        style.configure("Panel.TLabel", background="#2b2d30", foreground="#e8eaed")
        style.configure("TButton", padding=(8, 5))
        style.configure("TEntry", fieldbackground="#35373b", foreground="#f1f3f4")
        style.configure("TCombobox", fieldbackground="#35373b", foreground="#f1f3f4")
        style.configure("Treeview", background="#2b2d30", foreground="#e8eaed", fieldbackground="#2b2d30", rowheight=25)
        style.configure("Treeview.Heading", background="#35373b", foreground="#e8eaed")

    def _build_ui(self) -> None:
        main: ttk.Frame = ttk.Frame(self.root, padding=12)
        main.pack(fill=tk.BOTH, expand=True)
        main.columnconfigure(0, weight=0, minsize=290)
        main.columnconfigure(1, weight=1)
        main.rowconfigure(0, weight=1)

        lists_panel: ttk.Frame = ttk.Frame(main, style="Panel.TFrame", padding=12)
        lists_panel.grid(row=0, column=0, sticky="nsew", padx=(0, 10))
        ttk.Label(lists_panel, text="metadata_lists", style="Panel.TLabel").pack(anchor=tk.W, pady=(0, 8))
        self._build_list_editor(lists_panel, "packs", "packs")
        self._build_list_editor(lists_panel, "artists", "artists")
        self._build_list_editor(lists_panel, "rarities", "rarities")

        right_panel: ttk.Frame = ttk.Frame(main)
        right_panel.grid(row=0, column=1, sticky="nsew")
        right_panel.columnconfigure(0, weight=1)
        right_panel.rowconfigure(1, weight=1)

        form_panel: ttk.Frame = ttk.Frame(right_panel, style="Panel.TFrame", padding=12)
        form_panel.grid(row=0, column=0, sticky="ew", pady=(0, 10))
        form_panel.columnconfigure(1, weight=1)
        ttk.Label(form_panel, text="new_sticker", style="Panel.TLabel").grid(row=0, column=0, columnspan=3, sticky="w", pady=(0, 8))
        self._add_entry_row(form_panel, 1, "id", self.id_var)
        self._add_entry_row(form_panel, 2, "name", self.name_var)
        self._add_art_row(form_panel, 3)
        self._add_description_row(form_panel, 4)
        self._add_combo_row(form_panel, 5, "pack", self.pack_var, "packs")
        self._add_combo_row(form_panel, 6, "artist", self.artist_var, "artists")
        self._add_combo_row(form_panel, 7, "rarity", self.rarity_var, "rarities")

        button_bar: ttk.Frame = ttk.Frame(form_panel, style="Panel.TFrame")
        button_bar.grid(row=8, column=0, columnspan=3, sticky="e", pady=(12, 0))
        ttk.Button(button_bar, text="clear", command=self._clear_form).pack(side=tk.LEFT, padx=(0, 8))
        ttk.Button(button_bar, text="create_sticker", command=self._create_sticker).pack(side=tk.LEFT)

        existing_panel: ttk.Frame = ttk.Frame(right_panel, style="Panel.TFrame", padding=12)
        existing_panel.grid(row=1, column=0, sticky="nsew")
        existing_panel.columnconfigure(0, weight=1)
        existing_panel.rowconfigure(1, weight=1)
        ttk.Label(existing_panel, text="existing_stickers", style="Panel.TLabel").grid(row=0, column=0, sticky="w", pady=(0, 8))
        columns: tuple[str, ...] = ("id", "name", "pack", "artist", "rarity")
        self.sticker_tree = ttk.Treeview(existing_panel, columns=columns, show="headings")
        for column in columns:
            self.sticker_tree.heading(column, text=column)
            self.sticker_tree.column(column, width=110, anchor=tk.W)
        self.sticker_tree.column("id", width=70, stretch=False)
        self.sticker_tree.grid(row=1, column=0, sticky="nsew")
        scrollbar: ttk.Scrollbar = ttk.Scrollbar(existing_panel, orient=tk.VERTICAL, command=self.sticker_tree.yview)
        scrollbar.grid(row=1, column=1, sticky="ns")
        self.sticker_tree.configure(yscrollcommand=scrollbar.set)

        status_bar: ttk.Label = ttk.Label(self.root, textvariable=self.status_var, anchor=tk.W, padding=(12, 5))
        status_bar.pack(fill=tk.X)

    def _build_list_editor(self, parent: ttk.Frame, key: str, label: str) -> None:
        section: ttk.Frame = ttk.Frame(parent, style="Panel.TFrame")
        section.pack(fill=tk.BOTH, expand=True, pady=(0, 10))
        ttk.Label(section, text=label, style="Panel.TLabel").pack(anchor=tk.W)
        listbox: tk.Listbox = tk.Listbox(section, height=5, bg="#35373b", fg="#f1f3f4", selectbackground="#4d5156", borderwidth=0, highlightthickness=0)
        listbox.pack(fill=tk.BOTH, expand=True, pady=4)
        self.listboxes[key] = listbox
        controls: ttk.Frame = ttk.Frame(section, style="Panel.TFrame")
        controls.pack(fill=tk.X)
        ttk.Button(controls, text="add", command=lambda selected_key=key: self._add_list_value(selected_key)).pack(side=tk.LEFT)
        ttk.Button(controls, text="remove", command=lambda selected_key=key: self._remove_list_value(selected_key)).pack(side=tk.LEFT, padx=(6, 0))

    def _add_entry_row(self, parent: ttk.Frame, row: int, label: str, variable: tk.StringVar) -> None:
        ttk.Label(parent, text=label, style="Panel.TLabel").grid(row=row, column=0, sticky="w", padx=(0, 10), pady=4)
        ttk.Entry(parent, textvariable=variable).grid(row=row, column=1, columnspan=2, sticky="ew", pady=4)

    def _add_art_row(self, parent: ttk.Frame, row: int) -> None:
        ttk.Label(parent, text="art_png", style="Panel.TLabel").grid(row=row, column=0, sticky="w", padx=(0, 10), pady=4)
        ttk.Entry(parent, textvariable=self.art_var, state="readonly").grid(row=row, column=1, sticky="ew", pady=4)
        ttk.Button(parent, text="browse", command=self._browse_art).grid(row=row, column=2, sticky="e", padx=(8, 0), pady=4)

    def _add_description_row(self, parent: ttk.Frame, row: int) -> None:
        ttk.Label(parent, text="description", style="Panel.TLabel").grid(row=row, column=0, sticky="nw", padx=(0, 10), pady=4)
        self.description_text = tk.Text(parent, height=5, bg="#35373b", fg="#f1f3f4", insertbackground="#f1f3f4", wrap=tk.WORD, borderwidth=0, highlightthickness=0)
        self.description_text.grid(row=row, column=1, columnspan=2, sticky="ew", pady=4)

    def _add_combo_row(self, parent: ttk.Frame, row: int, label: str, variable: tk.StringVar, list_key: str) -> None:
        ttk.Label(parent, text=label, style="Panel.TLabel").grid(row=row, column=0, sticky="w", padx=(0, 10), pady=4)
        combobox: ttk.Combobox = ttk.Combobox(parent, textvariable=variable, state="readonly")
        combobox.grid(row=row, column=1, columnspan=2, sticky="ew", pady=4)
        self.comboboxes[list_key] = combobox

    def _load_lists(self) -> dict[str, list[str]]:
        default_lists: dict[str, list[str]] = {"packs": [], "artists": [], "rarities": []}
        if not LISTS_JSON_PATH.exists():
            return default_lists
        try:
            parsed: object = json.loads(LISTS_JSON_PATH.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            return default_lists
        if not isinstance(parsed, dict):
            return default_lists
        result: dict[str, list[str]] = {}
        for key in default_lists:
            values: object = parsed.get(key, [])
            if isinstance(values, list):
                result[key] = self._normalize_values([str(value) for value in values])
            else:
                result[key] = []
        return result

    def _normalize_values(self, values: list[str]) -> list[str]:
        result: list[str] = []
        seen: set[str] = set()
        for raw_value in values:
            value: str = raw_value.strip()
            if not value or value in seen:
                continue
            seen.add(value)
            result.append(value)
        return result

    def _save_lists(self) -> None:
        normalized_lists: dict[str, list[str]] = {key: self._normalize_values(values) for key, values in self.lists.items()}
        self.lists = normalized_lists
        _atomic_write_text(LISTS_JSON_PATH, json.dumps(self.lists, indent=2, ensure_ascii=False) + "\n")
        resource_text: str = (
            '[gd_resource type="Resource" script_class="StickerLists" load_steps=2 format=3]\n\n'
            f'[ext_resource type="Script" path="{LISTS_SCRIPT_PATH}" id="1_lists"]\n\n'
            '[resource]\n'
            'script = ExtResource("1_lists")\n'
            f'packs = {_godot_string_array(self.lists["packs"])}\n'
            f'artists = {_godot_string_array(self.lists["artists"])}\n'
            f'rarities = {_godot_string_array(self.lists["rarities"])}\n'
        )
        _atomic_write_text(LISTS_RESOURCE_PATH, resource_text)

    def _refresh_lists_ui(self) -> None:
        for key, listbox in self.listboxes.items():
            listbox.delete(0, tk.END)
            for value in self.lists[key]:
                listbox.insert(tk.END, value)
        for key, combobox in self.comboboxes.items():
            combobox.configure(values=self.lists[key])
        self._clear_invalid_combo_selection("packs", self.pack_var)
        self._clear_invalid_combo_selection("artists", self.artist_var)
        self._clear_invalid_combo_selection("rarities", self.rarity_var)

    def _clear_invalid_combo_selection(self, key: str, variable: tk.StringVar) -> None:
        if variable.get() not in self.lists[key]:
            variable.set("")

    def _add_list_value(self, key: str) -> None:
        value: str | None = simpledialog.askstring("add_value", f"new_{key[:-1] if key.endswith('s') else key}", parent=self.root)
        if value is None:
            return
        normalized_value: str = value.strip()
        if not normalized_value:
            return
        if normalized_value in self.lists[key]:
            messagebox.showinfo("already_exists", f"{normalized_value} already exists in {key}.", parent=self.root)
            return
        self.lists[key].append(normalized_value)
        self._save_lists()
        self._refresh_lists_ui()
        self.status_var.set(f"added {normalized_value} to {key}")

    def _remove_list_value(self, key: str) -> None:
        selection: tuple[int, ...] = self.listboxes[key].curselection()
        if not selection:
            return
        value: str = str(self.listboxes[key].get(selection[0]))
        if self._list_value_in_use(key, value):
            messagebox.showerror("value_in_use", f"{value} is used by an existing sticker and cannot be removed.", parent=self.root)
            return
        self.lists[key].remove(value)
        self._save_lists()
        self._refresh_lists_ui()
        self.status_var.set(f"removed {value} from {key}")

    def _list_value_in_use(self, key: str, value: str) -> bool:
        field_name: str = {"packs": "pack", "artists": "artist", "rarities": "rarity"}[key]
        for resource_path in DEFINITION_ROOT.glob("*.tres"):
            try:
                resource_text: str = resource_path.read_text(encoding="utf-8")
            except OSError:
                continue
            if _read_generated_field(resource_text, field_name) == value:
                return True
        return False

    def _browse_art(self) -> None:
        selected_path: str = filedialog.askopenfilename(parent=self.root, title="select_png", filetypes=[("PNG image", "*.png")])
        if selected_path:
            self.art_var.set(selected_path)

    def _create_sticker(self) -> None:
        validation_error: str = self._validate_form()
        if validation_error:
            messagebox.showerror("cannot_create_sticker", validation_error, parent=self.root)
            return
        sticker_id: int = int(self.id_var.get().strip())
        sticker_name: str = self.name_var.get().strip()
        source_art_path: Path = Path(self.art_var.get())
        description: str = self.description_text.get("1.0", tk.END).strip()
        art_filename: str = f"{sticker_id:06d}_{_slugify(sticker_name)}.png"
        definition_filename: str = f"{sticker_id:06d}_{_slugify(sticker_name)}.tres"
        destination_art_path: Path = ART_ROOT / art_filename
        definition_path: Path = DEFINITION_ROOT / definition_filename
        shutil.copy2(source_art_path, destination_art_path)
        art_resource_path: str = f"res://assets/stickers/art/{art_filename}"
        definition_text: str = self._build_definition_resource(sticker_id, sticker_name, art_resource_path, description)
        try:
            _atomic_write_text(definition_path, definition_text)
        except OSError as error:
            destination_art_path.unlink(missing_ok=True)
            messagebox.showerror("write_failed", str(error), parent=self.root)
            return
        self._refresh_existing_stickers()
        self._clear_form()
        self.status_var.set(f"created sticker {sticker_id}: {sticker_name}")

    def _validate_form(self) -> str:
        raw_id: str = self.id_var.get().strip()
        if not raw_id.isdigit() or int(raw_id) <= 0:
            return "id must be a positive whole number."
        if int(raw_id) in self._existing_ids():
            return f"sticker id {raw_id} already exists."
        if not self.name_var.get().strip():
            return "name is required."
        art_path: Path = Path(self.art_var.get())
        if not _is_png(art_path):
            return "art must be a valid PNG file."
        if self.pack_var.get() not in self.lists["packs"]:
            return "choose a pack from the pack list."
        if self.artist_var.get() not in self.lists["artists"]:
            return "choose an artist from the artist list."
        if self.rarity_var.get() not in self.lists["rarities"]:
            return "choose a rarity from the rarity list."
        return ""

    def _existing_ids(self) -> set[int]:
        result: set[int] = set()
        for resource_path in DEFINITION_ROOT.glob("*.tres"):
            try:
                resource_text: str = resource_path.read_text(encoding="utf-8")
            except OSError:
                continue
            raw_id: str = _read_generated_field(resource_text, "id")
            if raw_id.isdigit():
                result.add(int(raw_id))
        return result

    def _build_definition_resource(self, sticker_id: int, sticker_name: str, art_resource_path: str, description: str) -> str:
        return (
            '[gd_resource type="Resource" script_class="StickerDefinition" load_steps=3 format=3]\n\n'
            f'[ext_resource type="Script" path="{DEFINITION_SCRIPT_PATH}" id="1_definition"]\n'
            f'[ext_resource type="Texture2D" path="{art_resource_path}" id="2_art"]\n\n'
            '[resource]\n'
            'script = ExtResource("1_definition")\n'
            f'id = {sticker_id}\n'
            f'sticker_name = {_godot_quote(sticker_name)}\n'
            'art = ExtResource("2_art")\n'
            f'description = {_godot_quote(description)}\n'
            f'pack = {_godot_quote(self.pack_var.get())}\n'
            f'artist = {_godot_quote(self.artist_var.get())}\n'
            f'rarity = {_godot_quote(self.rarity_var.get())}\n'
        )

    def _refresh_existing_stickers(self) -> None:
        for item_id in self.sticker_tree.get_children():
            self.sticker_tree.delete(item_id)
        rows: list[tuple[int, str, str, str, str]] = []
        for resource_path in DEFINITION_ROOT.glob("*.tres"):
            try:
                resource_text: str = resource_path.read_text(encoding="utf-8")
            except OSError:
                continue
            raw_id: str = _read_generated_field(resource_text, "id")
            if not raw_id.isdigit():
                continue
            rows.append((
                int(raw_id),
                _read_generated_field(resource_text, "sticker_name"),
                _read_generated_field(resource_text, "pack"),
                _read_generated_field(resource_text, "artist"),
                _read_generated_field(resource_text, "rarity"),
            ))
        rows.sort(key=lambda row: row[0])
        for row in rows:
            self.sticker_tree.insert("", tk.END, values=row)

    def _clear_form(self) -> None:
        self.id_var.set("")
        self.name_var.set("")
        self.art_var.set("")
        self.description_text.delete("1.0", tk.END)
        self.pack_var.set("")
        self.artist_var.set("")
        self.rarity_var.set("")


def main() -> None:
    root: tk.Tk = tk.Tk()
    StickerCreatorApp(root)
    root.mainloop()


if __name__ == "__main__":
    main()
