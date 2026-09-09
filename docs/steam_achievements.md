# Steam achievements

Sticker-Shock uses achievement API names under the base launcher Steam application `4281680`. The Sticker-Shock DLC entitlement remains `4478190`; the running Steam API session and its achievement/stat namespace belong to the launcher application.

## First Sticker

Configure this achievement in the Steamworks dashboard for App `4281680`:

- API Name: `STICKER_SHOCK_FIRST_STICKER`
- Display Name: `First Sticker`
- Description: `Get your first sticker.`
- Hidden: No
- Progress stat: None

The game unlocks this achievement when persistent sticker ownership changes from zero copies to one copy. All sticker grant routes use the same economy grant path, so paid packs, free packs, premium-edition pulls, and Unique-code rewards are covered.

Existing saves are reconciled during economy initialization. If a player already owns at least one sticker when this achievement is introduced, the game attempts to unlock it after Steam user stats become available.

`SteamAchievements` requests the local user's stats after `SteamManager` initializes, attempts the achievement immediately when earned, and retries at a bounded interval if Steam's asynchronous stats state is not ready yet. No Godot signal connections are used.

The Steamworks dashboard definition must be created and published before the API name can unlock successfully. Steam also requires the achievement's locked and unlocked artwork to be configured in Steamworks; those dashboard assets are not stored or invented by this repository change.

## Debug diagnostics

Editor runs and debug exports print the first-sticker achievement flow to Godot Output. Release builds do not perform the additional diagnostic reads or print these messages.

A normal diagnostic sequence includes:

```text
SteamAchievements: requesting user stats for steam_id=...
SteamAchievements: sync api=STICKER_SHOCK_FIRST_STICKER total_owned_count=1 steam_available=true
SteamAchievements: attempt api=STICKER_SHOCK_FIRST_STICKER number=1
Steam achievement state: api=STICKER_SHOCK_FIRST_STICKER phase=before setAchievement state={...}
Steam achievement operation: api=STICKER_SHOCK_FIRST_STICKER operation=setAchievement result=true
Steam achievement state: api=STICKER_SHOCK_FIRST_STICKER phase=after setAchievement state={...}
Steam achievement operation: api=STICKER_SHOCK_FIRST_STICKER operation=storeStats result=true
Steam achievement state: api=STICKER_SHOCK_FIRST_STICKER phase=after storeStats state={...}
SteamAchievements: attempt succeeded api=STICKER_SHOCK_FIRST_STICKER number=1
```

The raw `getAchievement()` dictionaries are intentionally printed without interpreting individual keys. This makes API-name lookup failures, an already-achieved state, a successful local mutation, and a persistence failure distinguishable while remaining tolerant of GodotSteam dictionary-shape changes.
