# Sticker Creator

Use the launcher for your platform:

```bash
tools/sticker_creator/run_linux.sh
```

On Windows, run `tools\sticker_creator\run_windows.bat`.

The launcher installs Pillow automatically if it is not already available. The tool manages the controlled `packs`, `artists`, and `rarities` lists, assigns sticker IDs automatically, accepts PNG artwork, and creates one Godot `StickerDefinition` resource per sticker.

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

A list value cannot be removed while an existing generated sticker uses it. Artwork must be a valid PNG file.
