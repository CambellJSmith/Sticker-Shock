# Sticker Creator

Use the launcher for your platform:

```bash
tools/sticker_creator/run_linux.sh
```

On Windows, run `tools\sticker_creator\run_windows.bat`.

The launchers use your existing Python installation and do not create a virtual environment, upgrade `pip`, or install packages automatically. Linux uses `python3` by default and Windows uses `python`; set `PYTHON_BIN` before launching if you want to use a different existing interpreter. The launcher checks for Pillow, NumPy, and SciPy and exits with an install command if any are missing. The tool lets you manage packs and artists, assigns sticker IDs automatically, accepts PNG artwork, and creates one Godot `StickerDefinition` resource per sticker.

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

Before artwork is added to the game, source alpha is cleaned into a binary silhouette: pixels with alpha 128 or higher become fully opaque, and pixels below 128 become fully transparent. The selected die-cut border is then generated and the finished image is quantized to a palette of at most 256 colours. Pillow's libimagequant backend is preferred when available, with its RGBA octree quantizer used as the fallback. The original PNG is preserved separately so border edits always start from the original pixels.

## die-cut borders

New stickers automatically start with a white border, a width of 12 pixels, and smoothing of 8 pixels. The border panel provides:

- **width (px):** outward growth in original-image pixels, from 0 to 256; 0 disables the border;
- **smoothing (px):** cleanup of small teeth, bumps, and narrow notches, from 1 to 128; larger values produce a simpler cut outline;
- **colour:** a clickable swatch, preset colour grid, native custom colour picker, and editable `#rrggbb` field;
- **export preview:** the finished palette-converted sticker on a transparency checkerboard, including its final pixel dimensions.

The processor first applies the binary alpha rule, then uses that cleaned silhouette, fills enclosed holes in the backing, grows the outline using Euclidean distance, and smooths its signed distance field. It then offsets the smooth contour outward enough to enclose the complete grown silhouette. Jagged artwork stays intact inside a smooth, antialiased backing; smoothing never clips artwork or adds its original rough contour back onto the cut edge. Exterior indentations larger than the smoothing scale remain recognisable. Nearby shapes may join as the backing grows; widely separated elements remain separate.

Width is a minimum growth distance. Rough points or strong smoothing can make the backing wider than that minimum. The canvas expands where needed, with a transparent sampling margin. The illustration is never resized or filtered during border construction. The game continues to fit the finished image to its standard physical sticker size, so the illustration can occupy a smaller portion of that size after a border is added.

The border is fully opaque except for its antialiased outer edge. Bordered exports reserve 32 palette entries for the exact chosen colour and an alpha ramp, leaving 224 entries for the artwork. This prevents palette conversion from tinting the backing or introducing dark edge halos. Fully transparent PNGs are rejected. Images whose expanded working canvas exceeds 25 million pixels must be reduced before bordering.

Preview work runs on a background worker with debounced updates and cached cut geometry for colour-only changes. The preview uses the same geometry and palette conversion as saving. Pillow, NumPy, and SciPy must already be installed in the Python interpreter used to launch the tool; the launchers only verify those imports and never create or modify a Python environment.

### individual imports, batches, and edits

Individual imports and replacement artwork use the same processing function as batch import. The batch dialog includes its own colour, width, smoothing, and preview controls. Its artwork selector lets you inspect each image before applying one frozen recipe to the entire batch. Width and smoothing are measured in each source image's pixels, so the same pixel width appears proportionally thinner on higher-resolution images.

The existing-sticker list follows the pack selected in the left metadata panel. Select a pack to show only its stickers; clear the selection to show every sticker again. The form's pack dropdown still controls the pack saved for a new or edited sticker.

Editing an authored sticker restores its original artwork and border settings. Changing colour or width renders a fresh border; metadata-only edits reuse an already-current exported PNG without recompressing it. Older authoring records are rendered once with the binary alpha rule on their next edit. Original artwork and recipes use stable numeric filenames, so renaming a sticker does not lose them. Selecting an already-generated tool PNG resolves its preserved original instead of adding another border over the existing one.

Older stickers without authoring records open with width 0. Saving one through the tool archives its existing pixels as the original and writes a cleaned binary-alpha runtime PNG; increasing its width also creates a border from those archived source pixels. Previously baked borders cannot be removed automatically; select the unbordered source image when replacing that artwork.

The original image, border recipe, processed PNG, and Godot definition are saved as one group with rollback for ordinary write failures. Deleting a sticker removes its source and recipe as well as its runtime files. The tool's Commit action includes authoring records in its normal pull request workflow.

Borders are baked into runtime artwork, so peeling, shadows, inspection, and automatic placement continue to use the same authoritative alpha silhouette. Existing rainbow, silver, and gold materials also recolour the border along with the artwork.

### verification

Run the image and persistence regression tests from the repository root:

```bash
python -m unittest discover -s tools/sticker_creator/tests -v
```

The GUI tests also run when a desktop display is available; on headless Linux, run the command under `xvfb-run -a`.

Generated files are written automatically:

- quantized PNG artwork: `assets/stickers/art/`
- sticker resources: `data/stickers/`
- Godot metadata lists: `data/sticker_lists.tres`
- tool list storage: `tools/sticker_creator/sticker_lists.json`
- original PNGs and border recipes: `tools/sticker_creator/source_art/`

The authoring folder contains `.gdignore`, so Godot does not import the preserved originals as runtime textures or discover them as additional stickers.

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
