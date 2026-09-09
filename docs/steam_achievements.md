# Steam achievements

Sticker-Shock uses the achievement namespace of the base launcher Steam application `4281680`. The Sticker-Shock DLC entitlement remains `4478190`; the running Steam API session, achievements, and stats belong to launcher App `4281680` in the current architecture.

## Steamworks dashboard definitions

Create every entry below as a normal boolean achievement under App `4281680`. Use the API name exactly as written. All are visible (`Hidden: No`) and use no progress stat (`Progress stat: None`).

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

Each achievement also needs the normal Steamworks locked and unlocked icon artwork before the dashboard configuration is considered complete.

## Scaling rules

Do not create fixed Steam progress-stat thresholds for the percentage/content-completion achievements above. The game intentionally evaluates them locally against the catalogue shipped in the running build and sends Steam only the final boolean unlock.

Collection milestones use exact integer ratio comparisons against `StickerCatalog.get_sticker_count()`. For example, the 25% achievement is satisfied when `discovered_count * 4 >= current_catalogue_count`; this behaves like a ceiling percentage without floating-point rounding and automatically grows when more sticker definitions are added.

Book milestones use the same current-catalogue denominator but count distinct authored sticker designs physically placed in the book, so duplicate copies cannot shortcut them.

`ALL_UNIQUES` counts all current definitions authored with rarity `Unique`. `ALL_PACKS` uses the current purchasable pack list. `COMPLETE_ONE_PACK` derives each pack's denominator from the current random-pull designs assigned to that pack. `ALL_RARITIES` derives its denominator from the nonempty rarity labels currently represented by authored definitions.

Steam achievements are permanent once Steam unlocks them. If a player earns a catalogue-completion achievement and a later game update adds more stickers, the already-earned Steam achievement remains unlocked; players who have not earned it yet are evaluated against the newer, larger catalogue.

## Runtime architecture

`StickerAchievementRules` contains pure progression evaluation and Steam API names. It does not call Steamworks.

`SteamAchievements` owns Steam synchronization, bounded retries, event-history persistence, and debug diagnostics. It requests user stats after `SteamManager` initializes, reconciles the loaded collection after the current catalogue and saves are ready, and keeps no gameplay signal connections.

Newly revealed pack or Unique rewards call `SteamAchievements.sync_progress()` after ownership has already committed. Complete five-sticker pack rewards also persist the first-pack event. Physical book changes are detected by polling only `StickerBookState.get_placement_count()` every half second; the full catalogue scan runs only when that constant-time count changes. The first successful market sale is persisted as an event because current inventory cannot reconstruct historical sales later.

Event-only history is stored at `user://sticker_achievement_events.json`. This lets a pack-open or market-sale event earned while Steam is unavailable reconcile on a later Steam-enabled launch. State-derived achievements require no additional local history because they are reconstructed from the normal economy/book saves.

## Retry and idempotency behavior

Every earned achievement enters one generic pending queue. The manager attempts it immediately, then retries at most ten times at half-second intervals if Steam's asynchronous user-stats cache is not ready. A bad/unpublished API name is exhausted for the current session so progression changes cannot create an infinite retry loop; state-derived conditions are evaluated again on the next launch, and event conditions remain persisted locally.

`SteamProgress.unlock_achievement()` first reads `Steam.getAchievement()`. If Steam already reports `{ "ret": true, "achieved": true }`, the helper treats the achievement as synchronized without issuing a redundant `setAchievement()` or `storeStats()`. Newly earned achievements still use `setAchievement()` followed by `storeStats()`.

## Debug diagnostics

Editor runs and debug exports print achievement synchronization to Godot Output. Release builds keep the same unlock behavior without the diagnostic console output.

A newly earned achievement normally produces lines like:

```text
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