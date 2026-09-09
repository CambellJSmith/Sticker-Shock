# Steam achievements

Sticker-Shock uses the achievement namespace of the base launcher Steam application `4281680`. The Sticker-Shock DLC entitlement remains `4478190`; the running Steam API session, achievements, and stats belong to launcher App `4281680` in the current architecture.

## Steamworks dashboard definitions

Create every entry below as a normal client-set boolean achievement under App `4281680`. Use the API name exactly as written. All are visible (`Hidden: No`) and intentionally use no progress stat (`Progress stat: None`).

| API name | Display name | Description |
| --- | --- | --- |
| `STICKER_SHOCK_FIRST_STICKER` | First Sticker | Get your first sticker. |
| `STICKER_SHOCK_FIRST_PACK` | Crack the Pack | Open your first sticker pack. |
| `STICKER_SHOCK_FIRST_BOOK_PLACEMENT` | Stick It | Place your first sticker in the book. |
| `STICKER_SHOCK_COLLECTION_10_PERCENT` | Getting Started | Discover 10% of the current sticker catalogue. |
| `STICKER_SHOCK_COLLECTION_25_PERCENT` | Quarter Full | Discover 25% of the current sticker catalogue. |
| `STICKER_SHOCK_COLLECTION_50_PERCENT` | Half the Story | Discover 50% of the current sticker catalogue. |
| `STICKER_SHOCK_COLLECTION_75_PERCENT` | Three Quarters There | Discover 75% of the current sticker catalogue. |
| `STICKER_SHOCK_COLLECTION_90_PERCENT` | Almost Complete | Discover 90% of the current sticker catalogue. |
| `STICKER_SHOCK_COMPLETE_COLLECTION` | Complete Collection | Discover every sticker in the current catalogue. |
| `STICKER_SHOCK_BOOK_25_PERCENT` | Curator | Place distinct sticker designs equal to 25% of the current catalogue in the book. |
| `STICKER_SHOCK_BOOK_50_PERCENT` | Exhibition Ready | Place distinct sticker designs equal to 50% of the current catalogue in the book. |
| `STICKER_SHOCK_COMPLETE_BOOK` | Living Catalogue | Place every sticker design in the current catalogue in the book. |
| `STICKER_SHOCK_FIRST_DUPLICATE` | Double Take | Own at least two copies of the same sticker design. |
| `STICKER_SHOCK_RAINBOW_EDITION` | Rainbow Connection | Collect a rainbow-edition sticker. |
| `STICKER_SHOCK_SILVER_EDITION` | Silver Lining | Collect a silver-edition sticker. |
| `STICKER_SHOCK_GOLD_EDITION` | Gold Standard | Collect a gold-edition sticker. |
| `STICKER_SHOCK_FULL_SPECTRUM` | Full Spectrum | Collect at least one rainbow, one silver, and one gold sticker. |
| `STICKER_SHOCK_FULL_FINISH` | Full Finish | Own normal, rainbow, silver, and gold copies of the same sticker design. |
| `STICKER_SHOCK_LEGENDARY` | Living Legend | Collect a Legendary sticker. |
| `STICKER_SHOCK_UNIQUE` | Codebreaker | Collect a Unique sticker. |
| `STICKER_SHOCK_ALL_UNIQUES` | Unique Authority | Collect every Unique sticker in the current catalogue. |
| `STICKER_SHOCK_ALL_PACKS` | Pack Tourist | Collect at least one sticker from every current sticker pack. |
| `STICKER_SHOCK_COMPLETE_ONE_PACK` | Pack Completionist | Discover every random-pull sticker in any one current pack. |
| `STICKER_SHOCK_ALL_RARITIES` | Rarity Roundup | Collect at least one sticker from every rarity currently represented in the catalogue. |
| `STICKER_SHOCK_FIRST_MARKET_SALE` | Market Debut | Sell your first sticker at the collector exchange. |

Each achievement also needs the normal Steamworks achieved and unachieved icon artwork. The repository intentionally does not invent those assets.

## Scaling rules

Do not create fixed Steam progress-stat thresholds for the percentage/content-completion achievements above. The game evaluates their live denominators locally and sends Steam only the final boolean unlock.

Collection milestones use exact integer ratio comparisons against `StickerCatalog.get_sticker_count()`. For example, the 25% achievement is satisfied when `discovered_count * 4 >= current_catalogue_count`; this behaves like a ceiling percentage without floating-point rounding and automatically grows when more sticker definitions are added.

Book milestones use the same current-catalogue denominator but count distinct authored sticker designs physically placed in the book, so duplicate copies cannot shortcut them.

`ALL_UNIQUES` counts all current definitions authored with rarity `Unique`. `ALL_PACKS` uses the current purchasable pack list. `COMPLETE_ONE_PACK` derives each pack's denominator from the current random-pull designs assigned to that pack. `ALL_RARITIES` derives its denominator from the nonempty rarity labels currently represented by authored definitions.

Steam achievements are permanent once earned. The game mirrors that behavior locally: as soon as any rule is satisfied, its API name is persisted to `user://sticker_achievements.json` before Steam synchronization is attempted. This means an achievement earned offline remains earned if the qualifying sticker is later sold, and a catalogue-completion achievement earned before a future content expansion is not invalidated by the new stickers.

## Runtime architecture

`StickerAchievementRules` contains the exact 25 API names plus pure progression evaluation. It never calls Steamworks.

`SteamAchievements` owns permanent local earning, Steam synchronization, bounded retries, and debug diagnostics. It requests user stats after `SteamManager` initializes and reconciles the loaded collection after current content and saves are ready. No Godot signals are used.

New pack and Unique rewards call `SteamAchievements.sync_progress()` after ownership has already committed. A complete pack reward also permanently records `FIRST_PACK`. The first successful market sale permanently records `FIRST_MARKET_SALE` only after the atomic sale transaction succeeds.

Physical book milestones use a half-second poll of only `StickerBookState.get_placement_count()`, which is a constant-time array-size read. A full catalogue achievement scan runs only when that count changes. This keeps book achievement tracking decoupled from persistence and avoids signal wiring while remaining effective offline.

## Retry and idempotency behavior

Every locally earned achievement enters one generic pending queue when Steam is available. The manager attempts it immediately, then retries at most ten times at half-second intervals if Steam's asynchronous stats state is not ready. A bad or unpublished API name is exhausted for the current session so it cannot create an infinite retry loop; the permanent local achievement file causes it to retry on the next launch.

`SteamProgress.unlock_achievement()` first reads `Steam.getAchievement()`. If Steam already reports `{ "ret": true, "achieved": true }`, the helper treats the achievement as synchronized without issuing redundant `setAchievement()` or `storeStats()` calls. Newly earned achievements still use `setAchievement()` followed promptly by `storeStats()`.

## Debug diagnostics

Editor runs and debug exports print achievement synchronization to Godot Output. Release builds keep the same unlock behavior without the diagnostic console output.

A newly earned achievement normally produces lines like:

```text
SteamAchievements: earned locally api=STICKER_SHOCK_RAINBOW_EDITION
SteamAchievements: queued api=STICKER_SHOCK_RAINBOW_EDITION steam_available=true
SteamAchievements: attempt api=STICKER_SHOCK_RAINBOW_EDITION number=1
Steam achievement state: api=STICKER_SHOCK_RAINBOW_EDITION phase=before setAchievement state={ "ret": true, "achieved": false }
Steam achievement operation: api=STICKER_SHOCK_RAINBOW_EDITION operation=setAchievement result=true
Steam achievement state: api=STICKER_SHOCK_RAINBOW_EDITION phase=after setAchievement state={ "ret": true, "achieved": true }
Steam achievement operation: api=STICKER_SHOCK_RAINBOW_EDITION operation=storeStats result=true
Steam achievement state: api=STICKER_SHOCK_RAINBOW_EDITION phase=after storeStats state={ "ret": true, "achieved": true }
SteamAchievements: attempt succeeded api=STICKER_SHOCK_RAINBOW_EDITION number=1
```

An achievement already earned on Steam produces an `already unlocked` diagnostic and skips the redundant store. A missing or unpublished Steamworks API name eventually produces a warning naming the exact failed API after the bounded retry window.