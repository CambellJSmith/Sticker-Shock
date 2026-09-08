# Sticker Creator

Run this tool outside Godot from the repository root:

```bash
python3 tools/sticker_creator/sticker_creator.py
```

On Windows, use `python tools/sticker_creator/sticker_creator.py` if `python3` is not available.

The tool uses only Python's standard library and Tkinter. It manages the controlled `packs`, `artists`, and `rarities` lists, validates numerical sticker IDs, accepts PNG artwork, and creates one Godot `StickerDefinition` resource per sticker.

Generated files are written automatically:

- PNG artwork: `assets/stickers/art/`
- sticker resources: `data/stickers/`
- Godot metadata lists: `data/sticker_lists.tres`
- tool list storage: `tools/sticker_creator/sticker_lists.json`

Each generated `.tres` resource contains the sticker ID, name, art reference, description, pack, artist, and rarity. The runtime `StickerCatalog` discovers these resources automatically and continues exposing PNG paths to the existing sticker renderer and persistence systems.

A list value cannot be removed while an existing generated sticker uses it. Sticker IDs must be positive and unique. Artwork must be a valid PNG file.
