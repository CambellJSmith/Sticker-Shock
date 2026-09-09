# Sticker-Shock

Godot 4.7.2 prototype for a physical multi-page sticker book with realistic peeling, a separate 3D sticker shop, random sticker packs, manual placement, alpha-silhouette automatic packing, and a complete game-style navigation shell.

## game ux

Sticker-Shock opens with a dedicated title screen, original vector pack artwork, and a compact charcoal-and-warm-orange interface inspired by Blender. New players can start collecting immediately; returning players continue to their book or finish an unresolved pack.

The UI is composed from editor-authored Godot controls and separate screen scenes under `scenes/ui/`. Its shared appearance lives in `assets/ui/game_theme.tres`.

- One compact navigation rail and status bar keep currency, the free-pack timer, and unresolved copies visible without duplicating them across panels.
- The shop separates purchase offers from the physical reward reveal. It explains affordability and cooldowns, marks newly discovered designs, and provides native keyboard/controller actions for each exact pending copy.
- The book keeps its full physical cover inside the available viewport, with page navigation and contextual interaction guidance in a bottom toolbar. A new book has a clear first-pack action.
- The collection caches its cards, adapts its column count to available width, and supports search plus all/collected/missing filters. Collected cards open the same freely rotatable inspector used by physical book stickers. Empty results have a clear recovery action.
- Settings use native toggles and a scrollable controls reference. Display preferences retain their existing persistence.
- Pause owns the entire pointer and focus scope. Returning from its settings shortcut restores the paused destination. Closing inspection restores the exact card or control that opened it.
- Mouse buttons use native press/release behavior, hover feedback, disabled states, and keyboard activation. A small `GameButton` component overrides Godot's `_pressed()` hook to call its owner directly; no signal connections are used.
- Escape/back closes inspection, returns from settings or collection, cancels a pending manual placement, or toggles pause. Start explicitly pauses; A confirms a focused action. Placement and peeling remain mouse interactions.
- Hidden worlds and the closed inspection viewport stop processing. Progress counts refresh on changes; timer labels update once per second.

The desktop minimum window size is 960 × 640. Anchors, containers, scroll clipping, and camera fitting preserve the usable gameplay area as the window changes size. The native window title is “Sticker-Shock”; the internal project name remains the existing save-directory key, so existing books and currency continue to load.

See [the UI design notes](docs/ui_design.md) for component ownership, input behavior, and verification instructions.

## world flow

The project now has two separate long-lived gameplay scenes:

- `scenes/book_world.tscn` contains the open book, virtual page-pair navigation, persistent placed stickers, realistic peel interaction, manual new-sticker placement, landing projections, and bounce/slam attachment.
- `scenes/shop_world.tscn` contains a physically separate shop display, its own camera/lighting/environment, pack controls, and the five physical sticker reveal objects.
- `scripts/game_controller.gd` owns transitions and persistent models. The two 3D compositions are kept far apart and only the active scene owns camera, environment, interface, and input.

The game starts at the dedicated main menu. Opening the book or shop activates the appropriate physical world underneath the persistent navigation shell; collection and settings are complete screen-space destinations.

## packs

Every normal or free pack contains exactly five random sticker copies. Duplicates are allowed.

- normal packs cost in-game currency
- one free pack is claimable every six real-world hours
- currency, owned-copy counts, and the next free-pack timestamp are saved in `user://sticker_progress.json`
- new sticker art under `assets/stickers/` is discovered automatically and enters the random pool

After a successful transaction the five won stickers are actual 3D `StickerMesh` sheets. They launch upward into five display positions with a staggered throw, spin during the throw, and then slowly rotate/tilt while waiting for the player.

Only one opened pack is resolved at a time so physical copies cannot be lost or confused with another transaction.

## manual placement

Click one of the rotating pack-result stickers in the shop to carry that exact pending copy into the book.

In manual placement mode:

- move the mouse to position the sticker over either active page
- if neither active page has any legal zero-overlap fit for the selected sticker, a fresh left/right spread is appended automatically before placement begins
- previous/next controls let the player turn among all page pairs that already exist
- the sticker is shown as a full front-facing physical sheet above the page
- no procedural border is generated; the supplied image alpha is the complete sticker silhouette
- the faint landing guide shows the exact final silhouette on the page
- the sticker remains at its original source-artwork rotation while it is positioned in the book
- left click commits the placement
- the real sticker appears above the target, hops upward slightly, then accelerates down and slams flat
- after the landing animation the game returns to the shop and the remaining won stickers are still displayed
- cancel returns to the shop without consuming the selected pending copy

## auto_stick

`auto_stick` places every unresolved won sticker into the book without requiring manual clicks.

`scripts/sticker_auto_packer.gd` builds a coarse physical occupancy mask directly from each source image's alpha channel, so packing uses the supplied sticker silhouette rather than its rectangular texture bounds.

The solver:

1. caches the alpha-derived base mask so texture readback is not performed inside placement loops
2. caches canonical-orientation packed masks for duplicate stickers and existing placements
3. rasterizes only the already attached stickers on the currently targeted virtual page
4. finds empty frontier cells directly beside the existing silhouette cluster
5. keeps every sticker at its source artwork orientation and performs no book-space rotation search
6. aligns sampled candidate boundary cells against sampled cluster-frontier cells
7. rejects page-edge violations and normal overlaps
8. heavily rewards shared perimeter contact, with cluster distance used only as a secondary compactness term
9. falls back to a sparse bounded scan of both active pages if frontier matching finds no legal free location
10. if neither active page contains any zero-overlap fit, the book appends a completely new left/right spread and continues packing there
11. automatic packing never uses the old forced-overlap fallback; page growth is now the resolution for a full spread

This means irregular shapes can nest into each other's gaps substantially more tightly than rectangle-based packing.

## closing the game with unresolved stickers

Pending stickers are never presented as a resumable pack on the next normal session.

For a normal desktop window close, `GameController` disables automatic SceneTree quit handling, catches the window close request, runs the same auto-stick solver for every unresolved sticker, saves the book, and then quits.

If the process is terminated abnormally and the shutdown handler cannot run, the pending list was already persisted when the pack opened. On the next launch, `GameController` detects it before either gameplay world is composed, auto-places those stickers into the saved book, and then starts normal play. The player therefore returns to the book with the abandoned pack already dealt with.

## persistent book

Physical page placements are saved in `user://sticker_book.json`.

Each placement stores:

- a stable placement id
- sticker resource path
- physical artwork size
- zero-based absolute virtual page index
- page-space x/z center within the visible left/right page geometry
- canonical yaw (always zero while attached to the book)
- paper stack order

The save also stores total page count and the currently open spread. Pages are created in pairs, so the physical scene only needs one reusable left page and one reusable right page while persistence can grow to any number of virtual pages. Existing version-1 two-page saves migrate automatically to pages 0 and 1.

Only stickers from the active spread are reconstructed as full peelable `Sticker` objects, which keeps mesh, shader, and picking cost bounded as the collection grows. Turning pages rebuilds the visible spread from persistence. Moving and resticking an existing sticker updates its persistent page, position, canonical orientation, and stack order. Book placement never preserves a temporary inspection rotation.

## realistic sticker implementation

`StickerMesh` is a permanent 30 x 30 subdivided `ArrayMesh`. Attached peeling changes shader uniforms rather than rebuilding vertices on the CPU.

The peel is calculated from the actual local grabbed point and drag vector. The complete sheet curls around the moving fold, exposes its reverse, detaches only after the whole physical sheet clears the curl, then rotates face-up while being carried. Reversing the mouse after detachment does not cause reattachment during the same drag.

The front uses the sticker artwork exactly as supplied. The image alpha directly defines the physical sticker silhouette used by peel geometry, shadows, collision sizing, automatic packing, landing outlines, and inspection.

On release, a detached sticker performs a short upward bounce followed by an accelerating flat slam onto the exact position shown by its landing guide.

## adding stickers

Place compatible artwork anywhere below:

`assets/stickers/`

Transparent PNG, WebP, or SVG is recommended. Alpha directly defines the physical sticker shape used by rendering, peeling, landing outlines, inspection, and auto-packing.

The catalogue recursively discovers supported texture resources. No hard-coded pack entry is required for a new sticker.

`StickerCatalog.DEFAULT_LONG_EDGE` controls the default physical scale assigned to newly discovered designs while preserving their source aspect ratio.

No border-width setting exists. Add any desired border directly to the sticker artwork itself; its alpha will then become part of the physical sticker shape.

## economy tuning

The main values remain grouped in `scripts/sticker_economy.gd`:

- `STARTING_CURRENCY`
- `PACK_PRICE`
- `PACK_SIZE`
- `FREE_PACK_COOLDOWN_SECONDS`

Gameplay code can award currency through `StickerEconomy.add_currency(amount)`.

The six-hour free timer uses the local machine's Unix system time so it continues while the game is closed. A fully tamper-resistant real-world cooldown would require trusted server time.

## input implementation

Native `GameButton` controls handle mouse release, hover, disabled state, Enter, and Space through Godot's GUI input path, then call their owning component directly. `GameUI` handles global back/pause and confines tab/directional navigation to the active page or modal. Collection search retains native text-entry behavior.

The project maps `Button_Start`, `Button_A`, `Button_B`, and the four `StickLeft_*` directions. Default UI keyboard/d-pad navigation also works. Analog navigation is debounced to prevent small axis changes from skipping items.

Physical world picking runs through `_unhandled_input`, after GUI processing. The book separately completes an already-started gesture on release even over the navigation rail. Opening a modal or leaving the book finalizes any active peel before changing input ownership. Cancelled manual placement preserves its exact pending copy.

## Flat 2D presentation

The complete player-facing presentation is now flat and screen-aligned. The main menu, persistent navigation shell, collection, settings, shop, and book all read as a 2D game interface. The book and shop retain a small amount of internal 3D geometry only where it materially improves sticker simulation.

- Both gameplay cameras use orthographic projection and look exactly perpendicular to their presentation surfaces.
- A shared `FlatPresentationCamera` component automatically centers the book and shop inside the usable screen area beside the navigation rail, below the top bar, and above the book toolbar.
- Window resizing fits the complete book on both axes and recomputes the camera offset for the actual usable region.
- Sticker peeling, turnover, landing bounce, and real shadows still use depth internally, but perspective never changes their apparent size.
- Shop pack results remain face-on for their entire throw and idle animation. They rotate only around the sticker face normal.
- The old angled shop wall is hidden because it only existed to support the previous perspective presentation.
- Book pages are viewed directly from above, so sticker placement corresponds visually to a conventional 2D canvas.

This is intentionally a 2.5D implementation internally: the player sees a flat 2D composition, while the realistic peel system can still curl a real surface out of the page and cast a physically useful shadow.


## sticker inspection

A settled sticker has two deliberately separate pointer interactions:

- a short click opens the sticker inspection modal
- dragging farther than the peel threshold starts the physical peel using the exact original material click point

Inspection now uses an isolated `SubViewport` with an orthographic `Camera3D` and a separate `StickerMesh` instance. This preserves the game's flat presentation while allowing the selected sticker itself to rotate freely in true 3D without moving or mutating the real sticker in the book.

Inspection controls:

- left-drag uses a virtual arcball/trackball for unrestricted 3D orientation across pitch, yaw, and roll
- right-drag performs deliberate roll around the current camera-facing axis
- `Q` and `E` provide keyboard roll steps
- mouse wheel or the toolbar changes orthographic zoom
- `R` or the reset button restores canonical orientation and one-times zoom
- `Escape` or close exits inspection

The inspection orientation is stored as a normalized `Quaternion`, not accumulated Euler angles. The temporary mesh uses the same supplied artwork silhouette, printed front, and adhesive reverse material as the physical book sticker, so rotating through 180 degrees exposes the actual sticker backside. Camera fitting uses the complete sticker diagonal so any orientation can rotate without being clipped at normal zoom.

Every attached sticker is still forced to its original source-artwork orientation. Manual placement, auto-stick, moving/resticking, save loading, and old-save migration all enforce canonical yaw. Inspection rotation and zoom never write into `StickerBookState`.

## auto-stick performance

Automatic placement uses bounded canonical-orientation searches rather than exhaustive dictionary-heavy scans.

- Page occupancy is stored in `PackedByteArray` row-major grids so hot collision tests use direct contiguous indexing.
- Canonical sticker masks use cached `PackedInt32Array` coordinate pairs with cached local bounds.
- Book-space rotation search has been removed completely because attached stickers must retain their source artwork orientation.
- Cheap silhouette-bound rejection runs before any exact alpha-mask overlap walk.
- Existing-page frontiers are sampled to a fixed upper bound rather than cross-testing every contour cell against every sticker edge cell.
- Candidate sticker boundaries are cached into distributed radial contour supports.
- The old every-cell/every-rotation fallback is replaced by a sparse bounded recovery scan.
- Blank pages use a centered canonical-orientation fast path.
- A five-sticker auto-stick operation copies only the active spread once and appends new placements to that working snapshot. It no longer deep-copies the complete multi-page book before every sticker.
- Fresh spread validation passes an empty placement set directly instead of rasterizing unrelated pages.

Exact source-alpha silhouette overlap remains authoritative for every accepted placement. Removing all angle search makes the current solver materially cheaper than the previous optimized version as well as enforcing the book-orientation rule.

## expanded built-in sticker catalogue

The project now ships with 70 transparent SVG sticker designs. The original rocket, planet, and ghost remain, with 67 additional designs grouped under `assets/stickers/` by theme:

- `animals` — frog, cat, corgi, bee, snail, axolotl, octopus, shark
- `space` — moon, sun, ringed planet, UFO, alien, comet, satellite, astronaut helmet
- `fantasy` — wizard hat, potion, crystal, sword, shield, crown, dragon egg, magic wand, mimic chest
- `food` — pizza, donut, strawberry, cherries, ice cream, burger, cupcake, ramen, boba tea
- `retro` — gamepad, cassette, floppy disk, CRT monitor, arcade cabinet, boombox, joystick, pixel heart, vinyl record
- `spooky` — skull, pumpkin, bat, eyeball, black cat, candle, spider web, coffin
- `nature` — mushroom, cactus, flower, leaf, rainbow, cloud, lightning bolt, snowflake
- `objects` — key, lock, dice, d20, lightbulb, mug, camera, rubber duck

Every asset has a transparent background and uses its own alpha silhouette. The supplied alpha feeds peeling, landing outlines, inspection, and automatic placement directly. If you want a white border, bake it into the artwork before adding the sticker.

The catalogue remains data-free: dropping another supported image anywhere under `assets/stickers/` automatically includes it in future packs and the collection browser.

## Exact peel detachment

Peeling now detaches on the first frame where the shader's moving fold has crossed the final visible point of the sticker silhouette. The CPU test mirrors the shader's active curl width and fold equation directly, so there is no additional post-contact drag threshold.

The completion edge is derived directly from the source artwork alpha contour instead of from the rectangular mesh bounds. This prevents transparent corners around irregular artwork from delaying detachment. The contour is cached per sticker design and reused by duplicate copies.

## Sticker silhouette

The game does not generate a sticker border. The source image alpha is authoritative. Any border, backing margin, or custom cut shape should be included in the artwork you import.

The [Sticker Creator](tools/sticker_creator/README.md#die-cut-borders) can now bake smooth die-cut borders into new or replacement artwork. Its colour picker, pixel width, smoothing controls, and export preview are available for individual and batch imports. Imported alpha is normalized before processing: alpha 128 or higher becomes opaque and anything below 128 becomes transparent. Original PNGs and border recipes are preserved for later edits; the runtime continues to use only the finished PNG's alpha for the physical sticker shape.
