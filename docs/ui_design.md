# interface design

The interface should make the next useful action obvious and leave the stickers enough room to be the main attraction. The shared theme uses charcoal surfaces, clear spacing, restrained borders, and warm orange for primary actions and selection. Lowercase display text stays conversational; filenames and resource identities remain independent of those labels.

## flow

| state | primary action | supporting behavior |
| --- | --- | --- |
| new collection | start your collection | opens the pack shop without spending currency |
| returning player | open your book | restores the saved spread |
| unresolved pack | finish opening your pack | resumes its exact pending copies |
| shop offers | claim free pack when eligible | paid packs show their price; unavailable actions explain why |
| pack reveal | choose a sticker | native actions match the physical copies; auto-place handles all remaining copies |
| manual placement | click to place | escape/back cancels without consuming the copy; start pauses |
| collection | search or filter | owned designs open inspection; missing designs explain how to discover them |
| inspection | rotate or zoom | toolbar actions stay native; closing restores the exact opener |
| pause | back to it | input stays modal; settings returns to pause |

## component ownership

| component | responsibility |
| --- | --- |
| `GameUI` | routes, back history, pause and inspection scopes, status bar |
| `StickerMainMenu` | first-session and returning-player actions, progress summary |
| `CollectionBrowser` / `CollectionItem` | cached cards, ownership, search, responsive layout, inspection actions |
| `StickerSettingsPage` | persisted display toggles and contextual return |
| `BookHUD` | page controls, placement guidance, first-session action |
| `ShopHUD` | offer availability, discovery labels, exact pending-copy actions |
| `GameButton` | native `_pressed()` hook with a direct owner callback |
| `UIFocus` | tab and directional navigation within the permitted scope |
| `FlatPresentationCamera` | fitting physical content inside the shared shell and toolbar |
| `game_theme.tres` | editable native theme, colors, typography sizes, and control states |

World scripts own simulation and picking. HUDs own native UI controls. The economy, auto-packer, book persistence, source-art silhouettes, and quaternion inspection remain authoritative in their existing components.

## verification

Use Godot 4.7.2 or the project's compatible stable Godot version. Import once before running the regression scenario:

```bash
godot --headless --path . --editor --import --quit
XDG_DATA_HOME=/tmp/sticker_shock_ui_test godot --headless --path . --script res://tests/ui_flow_test.gd --fixed-fps 60
```

The scenario requires its named temporary data directory and refuses to use a normal player save. It runs native viewport input through the actual main scene and checks press/release purchases, cancellation, free-pack cooldown, modal click and focus isolation, back history, collection search, native text input, inspection focus restoration, copy conservation, manual/automatic placement, narrow result labels, camera bounds, and peel release across UI/modal boundaries.

Headless checks validate control layout and interaction. They do not replace a final desktop check of rendered lighting, shader appearance, font rasterization, animation feel, fullscreen behavior, or a physical gamepad. Desktop capture was unavailable in the implementation environment because starting a virtual display was rejected by its automatic approval policy.
