# Sticker Creator

Use the launcher for your platform:

```bash
tools/sticker_creator/run_linux.sh
```

On Windows, run `tools\sticker_creator\run_windows.bat`.

The launcher automatically installs the Python dependencies required by the sticker creator and its local vision model. The tool lets you manage packs and artists, assigns sticker IDs automatically, accepts PNG artwork, and creates one Godot `StickerDefinition` resource per sticker.

On first run, the tool automatically downloads and caches `HuggingFaceTB/SmolVLM-256M-Instruct`. Setup runs in the background and the normal sticker-authoring controls remain usable while it completes. After the model has been cached, flavour-text generation runs locally from the selected PNG and does not require an online inference service.

The `generate from art` button beside the description field asks the local vision model to inspect the selected PNG and write short flavour text based primarily on what is visibly depicted. The generated text is placed into the normal description field and remains fully editable before the sticker is created.

Selecting a PNG automatically fills the sticker Name from the image filename without the extension. The Name field remains editable so it can be overwritten manually.

Sticker rarity is fixed and cannot be edited in the tool. The available values are `Common`, `Uncommon`, `Rare`, `Elite`, `Legendary`, and `Unique`.

Normal random pack pulls use these rarity weights:

- Common: 60%
- Uncommon: 25%
- Rare: 10%
- Elite: 4%
- Legendary: 1%
- Unique: excluded from normal random pulls

If a specific pack contains no stickers of one of the weighted rarities, the available rarity weights are automatically re-normalized. `Unique` stickers remain valid authored content but are never selected by the normal random-pack system.

Before artwork is added to the game, it is converted to RGBA and quantized to the best available 256-color palette. Pillow's libimagequant backend is preferred when available, with its RGBA octree quantizer used as the fallback. The processed PNG is the only copy written into the game project.

Generated files are written automatically:

- quantized PNG artwork: `assets/stickers/art/`
- sticker resources: `data/stickers/`
- Godot metadata lists: `data/sticker_lists.tres`
- tool list storage: `tools/sticker_creator/sticker_lists.json`

Each generated `.tres` resource contains the sticker ID, name, art reference, description, pack, artist, and rarity. The runtime `StickerCatalog` discovers these resources automatically.

## Commit button

The `Commit` button uploads new sticker-tool content through the repository's normal pull-request workflow. It requires `git`, the GitHub CLI (`gh`), and an authenticated `gh` session.

When pressed, the tool:

1. verifies the checkout is on `main`;
2. refuses to continue if unrelated local changes exist;
3. creates a temporary sticker-content branch;
4. stages only sticker resources, sticker art, and metadata-list files;
5. commits and pushes that branch;
6. creates a pull request against `main`;
7. squash-merges the pull request;
8. switches back to `main` and fast-forwards the local checkout.

A pack or artist value cannot be removed while an existing generated sticker uses it. Artwork must be a valid PNG file.
