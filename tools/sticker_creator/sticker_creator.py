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

BG: str = "#1d1f21"
PANEL: str = "#282a2e"
PANEL_ALT: str = "#303238"
FIELD: str = "#3a3d43"
FIELD_HOVER: str = "#45484f"
TEXT: str = "#d9d9d9"
TEXT_MUTED: str = "#9b9b9b"
ACCENT: str = "#4772b3"
ACCENT_ACTIVE: str = "#5686cc"
SEPARATOR: str = "#161719"
SELECT: str = "#4b6e99"


def godot_quote(value: str) -> str:
    return json.dumps(value, ensure_ascii=False)


def godot_string_array(values: list[str]) -> str:
    return "PackedStringArray([%s])" % ", ".join(godot_quote(value) for value in values)


def slugify(value: str) -> str:
    result: str = re.sub(r"[^a-z0-9]+", "_", value.strip().lower()).strip("_")
    return result if result else "sticker"


def atomic_write(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary_path: Path = path.with_suffix(path.suffix + ".tmp")
    temporary_path.write_text(content, encoding="utf-8")
    temporary_path.replace(path)


def valid_png(path: Path) -> bool:
    if path.suffix.lower() != ".png" or not path.is_file():
        return False
    try:
        with path.open("rb") as source_file:
            return source_file.read(len(PNG_SIGNATURE)) == PNG_SIGNATURE
    except OSError:
        return False


def read_field(resource_text: str, field_name: str) -> str:
    match: re.Match[str] | None = re.search(rf"^{re.escape(field_name)} = (.+)$", resource_text, re.MULTILINE)
    if match is None:
        return ""
    raw_value: str = match.group(1).strip()
    try:
        return str(json.loads(raw_value))
    except json.JSONDecodeError:
        return raw_value.strip('"')


class StickerCreatorApp:
    def __init__(self, root: tk.Tk) -> None:
        self.root: tk.Tk = root
        self.root.title("Sticker-Shock · Sticker Creator")
        self.root.geometry("1240x800")
        self.root.minsize(1040, 680)

        self.lists: dict[str, list[str]] = self.load_lists()
        self.listboxes: dict[str, tk.Listbox] = {}
        self.comboboxes: dict[str, ttk.Combobox] = {}

        self.next_id_var: tk.StringVar = tk.StringVar()
        self.name_var: tk.StringVar = tk.StringVar()
        self.art_var: tk.StringVar = tk.StringVar()
        self.pack_var: tk.StringVar = tk.StringVar()
        self.artist_var: tk.StringVar = tk.StringVar()
        self.rarity_var: tk.StringVar = tk.StringVar()
        self.status_var: tk.StringVar = tk.StringVar(value="ready")

        self.description_text: tk.Text
        self.sticker_tree: ttk.Treeview

        DEFINITION_ROOT.mkdir(parents=True, exist_ok=True)
        ART_ROOT.mkdir(parents=True, exist_ok=True)

        self.configure_style()
        self.build_ui()
        self.refresh_lists_ui()
        self.refresh_existing_stickers()
        self.refresh_next_id()

    def configure_style(self) -> None:
        self.root.configure(bg=BG)
        style: ttk.Style = ttk.Style(self.root)
        try:
            style.theme_use("clam")
        except tk.TclError:
            pass

        style.configure(".", font=("Sans", 10))
        style.configure("TFrame", background=BG)
        style.configure("Panel.TFrame", background=PANEL)
        style.configure("Header.TFrame", background=PANEL_ALT)
        style.configure("TLabel", background=BG, foreground=TEXT)
        style.configure("Panel.TLabel", background=PANEL, foreground=TEXT)
        style.configure("Header.TLabel", background=PANEL_ALT, foreground=TEXT, font=("Sans", 10, "bold"))
        style.configure("Muted.TLabel", background=PANEL, foreground=TEXT_MUTED)

        style.configure(
            "TButton",
            background=FIELD,
            foreground=TEXT,
            bordercolor=SEPARATOR,
            lightcolor=FIELD,
            darkcolor=FIELD,
            padding=(9, 4),
        )
        style.map(
            "TButton",
            background=[("active", FIELD_HOVER), ("pressed", ACCENT)],
            foreground=[("disabled", TEXT_MUTED)],
        )

        style.configure(
            "Accent.TButton",
            background=ACCENT,
            foreground="#ffffff",
            bordercolor=ACCENT,
            lightcolor=ACCENT,
            darkcolor=ACCENT,
            padding=(12, 5),
            font=("Sans", 10, "bold"),
        )
        style.map("Accent.TButton", background=[("active", ACCENT_ACTIVE), ("pressed", ACCENT)])

        style.configure(
            "TEntry",
            fieldbackground=FIELD,
            foreground=TEXT,
            insertcolor=TEXT,
            bordercolor=SEPARATOR,
            lightcolor=FIELD,
            darkcolor=FIELD,
            padding=(6, 4),
        )
        style.configure(
            "Readonly.TEntry",
            fieldbackground=PANEL_ALT,
            foreground=TEXT_MUTED,
            bordercolor=SEPARATOR,
            lightcolor=PANEL_ALT,
            darkcolor=PANEL_ALT,
            padding=(6, 4),
        )
        style.map("Readonly.TEntry", fieldbackground=[("readonly", PANEL_ALT)])

        style.configure(
            "TCombobox",
            fieldbackground=FIELD,
            background=FIELD,
            foreground=TEXT,
            arrowcolor=TEXT_MUTED,
            bordercolor=SEPARATOR,
            lightcolor=FIELD,
            darkcolor=FIELD,
            padding=(6, 4),
        )
        style.map(
            "TCombobox",
            fieldbackground=[("readonly", FIELD)],
            background=[("active", FIELD_HOVER), ("readonly", FIELD)],
            foreground=[("readonly", TEXT)],
        )

        style.configure(
            "Treeview",
            background=PANEL,
            foreground=TEXT,
            fieldbackground=PANEL,
            bordercolor=SEPARATOR,
            lightcolor=PANEL,
            darkcolor=PANEL,
            rowheight=24,
        )
        style.map("Treeview", background=[("selected", SELECT)], foreground=[("selected", "#ffffff")])
        style.configure(
            "Treeview.Heading",
            background=PANEL_ALT,
            foreground=TEXT,
            bordercolor=SEPARATOR,
            lightcolor=PANEL_ALT,
            darkcolor=PANEL_ALT,
            padding=(6, 4),
            font=("Sans", 9, "bold"),
        )
        style.map("Treeview.Heading", background=[("active", FIELD)])

        style.configure("Vertical.TScrollbar", background=FIELD, troughcolor=PANEL, bordercolor=SEPARATOR, arrowcolor=TEXT_MUTED)

        self.root.option_add("*TCombobox*Listbox.background", FIELD)
        self.root.option_add("*TCombobox*Listbox.foreground", TEXT)
        self.root.option_add("*TCombobox*Listbox.selectBackground", SELECT)
        self.root.option_add("*TCombobox*Listbox.selectForeground", "#ffffff")

    def build_ui(self) -> None:
        top_bar: ttk.Frame = ttk.Frame(self.root, style="Header.TFrame", padding=(12, 7))
        top_bar.pack(fill=tk.X)
        ttk.Label(top_bar, text="Sticker-Shock", style="Header.TLabel").pack(side=tk.LEFT)
        ttk.Label(top_bar, text="  /  sticker_creator", style="Header.TLabel").pack(side=tk.LEFT)
        ttk.Label(top_bar, text="standalone content tool", style="Header.TLabel").pack(side=tk.RIGHT)

        separator: tk.Frame = tk.Frame(self.root, bg=SEPARATOR, height=1)
        separator.pack(fill=tk.X)

        main: ttk.Frame = ttk.Frame(self.root, padding=8)
        main.pack(fill=tk.BOTH, expand=True)
        main.columnconfigure(0, minsize=280)
        main.columnconfigure(1, weight=1)
        main.rowconfigure(0, weight=1)

        lists_panel: ttk.Frame = ttk.Frame(main, style="Panel.TFrame")
        lists_panel.grid(row=0, column=0, sticky="nsew", padx=(0, 8))
        self.build_panel_header(lists_panel, "metadata")
        lists_content: ttk.Frame = ttk.Frame(lists_panel, style="Panel.TFrame", padding=(10, 8, 10, 10))
        lists_content.pack(fill=tk.BOTH, expand=True)
        for key in ("packs", "artists", "rarities"):
            self.build_list_editor(lists_content, key)

        right_panel: ttk.Frame = ttk.Frame(main)
        right_panel.grid(row=0, column=1, sticky="nsew")
        right_panel.columnconfigure(0, weight=1)
        right_panel.rowconfigure(1, weight=1)

        form_panel: ttk.Frame = ttk.Frame(right_panel, style="Panel.TFrame")
        form_panel.grid(row=0, column=0, sticky="ew", pady=(0, 8))
        self.build_panel_header(form_panel, "sticker")
        form_content: ttk.Frame = ttk.Frame(form_panel, style="Panel.TFrame", padding=(12, 10, 12, 12))
        form_content.pack(fill=tk.X)
        form_content.columnconfigure(1, weight=1)

        self.add_readonly_row(form_content, 0, "id", self.next_id_var)
        self.add_entry_row(form_content, 1, "name", self.name_var)

        ttk.Label(form_content, text="art", style="Panel.TLabel").grid(row=2, column=0, sticky="w", padx=(0, 12), pady=4)
        ttk.Entry(form_content, textvariable=self.art_var, state="readonly", style="Readonly.TEntry").grid(row=2, column=1, sticky="ew", pady=4)
        ttk.Button(form_content, text="open…", command=self.browse_art).grid(row=2, column=2, padx=(8, 0), pady=4)

        ttk.Label(form_content, text="description", style="Panel.TLabel").grid(row=3, column=0, sticky="nw", padx=(0, 12), pady=4)
        self.description_text = tk.Text(
            form_content,
            height=5,
            bg=FIELD,
            fg=TEXT,
            insertbackground=TEXT,
            selectbackground=SELECT,
            selectforeground="#ffffff",
            wrap=tk.WORD,
            relief=tk.FLAT,
            borderwidth=0,
            highlightthickness=1,
            highlightbackground=SEPARATOR,
            highlightcolor=ACCENT,
            padx=7,
            pady=5,
        )
        self.description_text.grid(row=3, column=1, columnspan=2, sticky="ew", pady=4)

        self.add_combo_row(form_content, 4, "pack", self.pack_var, "packs")
        self.add_combo_row(form_content, 5, "artist", self.artist_var, "artists")
        self.add_combo_row(form_content, 6, "rarity", self.rarity_var, "rarities")

        button_bar: ttk.Frame = ttk.Frame(form_content, style="Panel.TFrame")
        button_bar.grid(row=7, column=0, columnspan=3, sticky="ew", pady=(10, 0))
        ttk.Label(button_bar, text="id is assigned automatically", style="Muted.TLabel").pack(side=tk.LEFT)
        ttk.Button(button_bar, text="clear", command=self.clear_form).pack(side=tk.RIGHT, padx=(8, 0))
        ttk.Button(button_bar, text="create sticker", style="Accent.TButton", command=self.create_sticker).pack(side=tk.RIGHT)

        existing_panel: ttk.Frame = ttk.Frame(right_panel, style="Panel.TFrame")
        existing_panel.grid(row=1, column=0, sticky="nsew")
        self.build_panel_header(existing_panel, "existing_stickers")
        existing_content: ttk.Frame = ttk.Frame(existing_panel, style="Panel.TFrame", padding=(8, 6, 8, 8))
        existing_content.pack(fill=tk.BOTH, expand=True)
        existing_content.columnconfigure(0, weight=1)
        existing_content.rowconfigure(0, weight=1)

        columns: tuple[str, ...] = ("id", "name", "pack", "artist", "rarity")
        self.sticker_tree = ttk.Treeview(existing_content, columns=columns, show="headings", selectmode="browse")
        widths: dict[str, int] = {"id": 72, "name": 220, "pack": 140, "artist": 160, "rarity": 120}
        for column in columns:
            self.sticker_tree.heading(column, text=column)
            self.sticker_tree.column(column, width=widths[column], anchor=tk.W, stretch=column != "id")
        self.sticker_tree.grid(row=0, column=0, sticky="nsew")

        scrollbar: ttk.Scrollbar = ttk.Scrollbar(existing_content, orient=tk.VERTICAL, command=self.sticker_tree.yview)
        scrollbar.grid(row=0, column=1, sticky="ns")
        self.sticker_tree.configure(yscrollcommand=scrollbar.set)

        status_separator: tk.Frame = tk.Frame(self.root, bg=SEPARATOR, height=1)
        status_separator.pack(fill=tk.X)
        status_bar: ttk.Frame = ttk.Frame(self.root, style="Header.TFrame", padding=(10, 4))
        status_bar.pack(fill=tk.X)
        ttk.Label(status_bar, textvariable=self.status_var, style="Header.TLabel").pack(side=tk.LEFT)
        ttk.Label(status_bar, text="data/stickers  ·  assets/stickers/art", style="Header.TLabel").pack(side=tk.RIGHT)

    def build_panel_header(self, parent: ttk.Frame, title: str) -> None:
        header: ttk.Frame = ttk.Frame(parent, style="Header.TFrame", padding=(9, 5))
        header.pack(fill=tk.X)
        ttk.Label(header, text="▾", style="Header.TLabel").pack(side=tk.LEFT, padx=(0, 5))
        ttk.Label(header, text=title, style="Header.TLabel").pack(side=tk.LEFT)

    def build_list_editor(self, parent: ttk.Frame, key: str) -> None:
        section: ttk.Frame = ttk.Frame(parent, style="Panel.TFrame")
        section.pack(fill=tk.BOTH, expand=True, pady=(0, 9))
        ttk.Label(section, text=key, style="Panel.TLabel").pack(anchor=tk.W, pady=(0, 3))

        listbox: tk.Listbox = tk.Listbox(
            section,
            height=5,
            bg=FIELD,
            fg=TEXT,
            selectbackground=SELECT,
            selectforeground="#ffffff",
            activestyle="none",
            relief=tk.FLAT,
            borderwidth=0,
            highlightthickness=1,
            highlightbackground=SEPARATOR,
            highlightcolor=ACCENT,
        )
        listbox.pack(fill=tk.BOTH, expand=True)
        self.listboxes[key] = listbox

        controls: ttk.Frame = ttk.Frame(section, style="Panel.TFrame")
        controls.pack(fill=tk.X, pady=(4, 0))
        ttk.Button(controls, text="+", width=3, command=lambda selected_key=key: self.add_list_value(selected_key)).pack(side=tk.LEFT)
        ttk.Button(controls, text="−", width=3, command=lambda selected_key=key: self.remove_list_value(selected_key)).pack(side=tk.LEFT, padx=(4, 0))

    def add_entry_row(self, parent: ttk.Frame, row: int, label: str, variable: tk.StringVar) -> None:
        ttk.Label(parent, text=label, style="Panel.TLabel").grid(row=row, column=0, sticky="w", padx=(0, 12), pady=4)
        ttk.Entry(parent, textvariable=variable).grid(row=row, column=1, columnspan=2, sticky="ew", pady=4)

    def add_readonly_row(self, parent: ttk.Frame, row: int, label: str, variable: tk.StringVar) -> None:
        ttk.Label(parent, text=label, style="Panel.TLabel").grid(row=row, column=0, sticky="w", padx=(0, 12), pady=4)
        ttk.Entry(parent, textvariable=variable, state="readonly", style="Readonly.TEntry").grid(row=row, column=1, columnspan=2, sticky="ew", pady=4)

    def add_combo_row(self, parent: ttk.Frame, row: int, label: str, variable: tk.StringVar, list_key: str) -> None:
        ttk.Label(parent, text=label, style="Panel.TLabel").grid(row=row, column=0, sticky="w", padx=(0, 12), pady=4)
        combobox: ttk.Combobox = ttk.Combobox(parent, textvariable=variable, state="readonly")
        combobox.grid(row=row, column=1, columnspan=2, sticky="ew", pady=4)
        self.comboboxes[list_key] = combobox

    def load_lists(self) -> dict[str, list[str]]:
        defaults: dict[str, list[str]] = {"packs": [], "artists": [], "rarities": []}
        if not LISTS_JSON_PATH.exists():
            return defaults
        try:
            parsed: object = json.loads(LISTS_JSON_PATH.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            return defaults
        if not isinstance(parsed, dict):
            return defaults
        return {
            key: self.normalize_values([str(value) for value in parsed.get(key, [])])
            if isinstance(parsed.get(key, []), list)
            else []
            for key in defaults
        }

    def normalize_values(self, values: list[str]) -> list[str]:
        result: list[str] = []
        seen: set[str] = set()
        for raw_value in values:
            value: str = raw_value.strip()
            if value and value not in seen:
                seen.add(value)
                result.append(value)
        return result

    def save_lists(self) -> None:
        self.lists = {key: self.normalize_values(values) for key, values in self.lists.items()}
        atomic_write(LISTS_JSON_PATH, json.dumps(self.lists, indent=2, ensure_ascii=False) + "\n")
        resource_text: str = (
            '[gd_resource type="Resource" script_class="StickerLists" load_steps=2 format=3]\n\n'
            f'[ext_resource type="Script" path="{LISTS_SCRIPT_PATH}" id="1_lists"]\n\n'
            '[resource]\nscript = ExtResource("1_lists")\n'
            f'packs = {godot_string_array(self.lists["packs"])}\n'
            f'artists = {godot_string_array(self.lists["artists"])}\n'
            f'rarities = {godot_string_array(self.lists["rarities"])}\n'
        )
        atomic_write(LISTS_RESOURCE_PATH, resource_text)

    def refresh_lists_ui(self) -> None:
        for key, listbox in self.listboxes.items():
            listbox.delete(0, tk.END)
            for value in self.lists[key]:
                listbox.insert(tk.END, value)
        for key, combobox in self.comboboxes.items():
            combobox.configure(values=self.lists[key])
        if self.pack_var.get() not in self.lists["packs"]:
            self.pack_var.set("")
        if self.artist_var.get() not in self.lists["artists"]:
            self.artist_var.set("")
        if self.rarity_var.get() not in self.lists["rarities"]:
            self.rarity_var.set("")

    def add_list_value(self, key: str) -> None:
        singular: str = {"packs": "pack", "artists": "artist", "rarities": "rarity"}[key]
        value: str | None = simpledialog.askstring(f"add_{singular}", f"new {singular}", parent=self.root)
        if value is None:
            return
        value = value.strip()
        if not value:
            return
        if value in self.lists[key]:
            messagebox.showinfo("already exists", f"{value} already exists in {key}.", parent=self.root)
            return
        self.lists[key].append(value)
        self.save_lists()
        self.refresh_lists_ui()
        self.status_var.set(f"added {singular}: {value}")

    def remove_list_value(self, key: str) -> None:
        selection: tuple[int, ...] = self.listboxes[key].curselection()
        if not selection:
            return
        value: str = str(self.listboxes[key].get(selection[0]))
        field_name: str = {"packs": "pack", "artists": "artist", "rarities": "rarity"}[key]
        if self.value_in_use(field_name, value):
            messagebox.showerror("value in use", f"{value} is used by an existing sticker.", parent=self.root)
            return
        self.lists[key].remove(value)
        self.save_lists()
        self.refresh_lists_ui()
        self.status_var.set(f"removed {field_name}: {value}")

    def value_in_use(self, field_name: str, value: str) -> bool:
        for resource_path in DEFINITION_ROOT.glob("*.tres"):
            try:
                if read_field(resource_path.read_text(encoding="utf-8"), field_name) == value:
                    return True
            except OSError:
                continue
        return False

    def browse_art(self) -> None:
        selected_path: str = filedialog.askopenfilename(
            parent=self.root,
            title="select sticker art",
            filetypes=[("PNG image", "*.png")],
        )
        if selected_path:
            self.art_var.set(selected_path)

    def create_sticker(self) -> None:
        error: str = self.validate_form()
        if error:
            messagebox.showerror("cannot create sticker", error, parent=self.root)
            return

        sticker_id: int = self.next_sticker_id()
        sticker_name: str = self.name_var.get().strip()
        source_art: Path = Path(self.art_var.get())
        description: str = self.description_text.get("1.0", tk.END).strip()

        base_name: str = f"{sticker_id:06d}_{slugify(sticker_name)}"
        art_filename: str = base_name + ".png"
        definition_filename: str = base_name + ".tres"
        destination_art: Path = ART_ROOT / art_filename
        destination_definition: Path = DEFINITION_ROOT / definition_filename

        try:
            shutil.copy2(source_art, destination_art)
        except OSError as copy_error:
            messagebox.showerror("copy failed", str(copy_error), parent=self.root)
            return

        definition_text: str = (
            '[gd_resource type="Resource" script_class="StickerDefinition" load_steps=3 format=3]\n\n'
            f'[ext_resource type="Script" path="{DEFINITION_SCRIPT_PATH}" id="1_definition"]\n'
            f'[ext_resource type="Texture2D" path="res://assets/stickers/art/{art_filename}" id="2_art"]\n\n'
            '[resource]\nscript = ExtResource("1_definition")\n'
            f'id = {sticker_id}\n'
            f'name = {godot_quote(sticker_name)}\n'
            'art = ExtResource("2_art")\n'
            f'description = {godot_quote(description)}\n'
            f'pack = {godot_quote(self.pack_var.get())}\n'
            f'artist = {godot_quote(self.artist_var.get())}\n'
            f'rarity = {godot_quote(self.rarity_var.get())}\n'
        )

        try:
            atomic_write(destination_definition, definition_text)
        except OSError as write_error:
            destination_art.unlink(missing_ok=True)
            messagebox.showerror("write failed", str(write_error), parent=self.root)
            return

        self.refresh_existing_stickers()
        self.clear_form()
        self.refresh_next_id()
        self.status_var.set(f"created #{sticker_id:06d} · {sticker_name}")

    def validate_form(self) -> str:
        if not self.name_var.get().strip():
            return "name is required."
        if not valid_png(Path(self.art_var.get())):
            return "art must be a valid PNG file."
        if self.pack_var.get() not in self.lists["packs"]:
            return "choose a pack from the pack list."
        if self.artist_var.get() not in self.lists["artists"]:
            return "choose an artist from the artist list."
        if self.rarity_var.get() not in self.lists["rarities"]:
            return "choose a rarity from the rarity list."
        return ""

    def existing_ids(self) -> set[int]:
        ids: set[int] = set()
        for resource_path in DEFINITION_ROOT.glob("*.tres"):
            try:
                raw_id: str = read_field(resource_path.read_text(encoding="utf-8"), "id")
            except OSError:
                continue
            if raw_id.isdigit():
                ids.add(int(raw_id))
        return ids

    def next_sticker_id(self) -> int:
        existing: set[int] = self.existing_ids()
        return max(existing, default=0) + 1

    def refresh_next_id(self) -> None:
        self.next_id_var.set(str(self.next_sticker_id()))

    def refresh_existing_stickers(self) -> None:
        for item_id in self.sticker_tree.get_children():
            self.sticker_tree.delete(item_id)

        rows: list[tuple[int, str, str, str, str]] = []
        for resource_path in DEFINITION_ROOT.glob("*.tres"):
            try:
                text: str = resource_path.read_text(encoding="utf-8")
            except OSError:
                continue
            raw_id: str = read_field(text, "id")
            if raw_id.isdigit():
                rows.append(
                    (
                        int(raw_id),
                        read_field(text, "name"),
                        read_field(text, "pack"),
                        read_field(text, "artist"),
                        read_field(text, "rarity"),
                    )
                )

        rows.sort(key=lambda row: row[0])
        for row in rows:
            display_row: tuple[str, str, str, str, str] = (f"{row[0]:06d}", row[1], row[2], row[3], row[4])
            self.sticker_tree.insert("", tk.END, values=display_row)

        self.refresh_next_id()

    def clear_form(self) -> None:
        self.name_var.set("")
        self.art_var.set("")
        self.description_text.delete("1.0", tk.END)
        self.pack_var.set("")
        self.artist_var.set("")
        self.rarity_var.set("")
        self.refresh_next_id()


def main() -> None:
    root: tk.Tk = tk.Tk()
    StickerCreatorApp(root)
    root.mainloop()


if __name__ == "__main__":
    main()
