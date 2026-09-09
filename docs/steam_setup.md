# Steam setup

Sticker-Shock uses the GodotSteam GDExtension already committed under `addons/godotsteam/`. The installed plug-in reports GodotSteam 4.22.1 and includes the native Steamworks runtime dependencies in its `.gdextension` manifest.

Sticker-Shock is not the base Steam application. The Steam product uses a launcher as the base application and individual games are DLC entitlements inside that launcher.

- Launcher / base Steam App ID: `4281680`
- Sticker-Shock DLC App ID: `4478190`

The game owns Steam initialization through the `SteamManager` autoload. GodotSteam automatic initialization and embedded callbacks are deliberately disabled so there is one clear lifecycle owner. `SteamManager` initializes the Steam session as the launcher/base application, pumps `Steam.run_callbacks()` every frame even while the game is paused, exposes DLC entitlement/install helpers, overlay/Rich Presence helpers, and calls `steamShutdown()` during normal application teardown.

## 1. Launcher and DLC identity

`project.godot` contains:

```ini
[steam]
initialization/app_data/app_id=4281680
initialization/processes/initialize_on_startup=false
initialization/processes/embed_callbacks=false
integration/content_dlc_app_id=4478190
integration/require_content_dlc=false
integration/require_steam=false
integration/restart_through_steam=true
```

`4281680` is intentionally passed to `steamInitEx()` and `restartAppIfNecessary()`. Sticker-Shock must not initialize Steam as `4478190` in this launcher architecture because `4478190` is the content entitlement, not the Steam library application/session that owns the launcher.

`4478190` is used through Steam's DLC/application entitlement APIs. Ownership and installation are separate states:

```gdscript
SteamManager.owns_content_dlc()
SteamManager.is_content_dlc_installed()
SteamManager.request_content_dlc_install()
SteamManager.get_content_dlc_download_progress()
```

The generic equivalents are also available if the same integration pattern is reused by the launcher for additional games:

```gdscript
SteamManager.is_dlc_owned(dlc_app_id)
SteamManager.is_dlc_installed(dlc_app_id)
SteamManager.request_dlc_install(dlc_app_id)
SteamManager.get_dlc_download_progress(dlc_app_id)
```

The ownership helper uses `Steam.isSubscribedApp()` because a player may own a DLC without currently having its files installed. The installed helper uses `Steam.isDLCInstalled()` because the launcher should only expose a playable launch action once the required DLC files are present.

`integration/restart_through_steam=true` makes an exported Sticker-Shock executable opened directly outside the proper Steam context redirect back through base App ID `4281680`. Editor runs deliberately skip this restart so normal Godot development remains usable.

Keep `integration/require_steam=false` and `integration/require_content_dlc=false` while validating the Steamworks configuration. Once the launcher package, developer licenses, DLC association, depots, and launch flow are verified, these can be enabled if release builds should refuse to continue without the expected base Steam session and Sticker-Shock entitlement.

A local `steam_appid.txt` is ignored by Git. It can still be used for SDK/debug workflows if needed, but normal builds use the configured launcher App ID directly.

## 2. Steamworks launcher and DLC configuration

In Steamworks, App `4281680` should be the application users own/launch from their Steam library. DLC `4478190` should be associated with that base application.

The launcher should treat Sticker-Shock as a stateful DLC entry rather than a second independent Steam library game. A useful launcher state model is:

```text
not_owned
owned_not_installed
downloading
installed
```

For Sticker-Shock, the launcher should use DLC App ID `4478190` when resolving those states. `isSubscribedApp(4478190)` answers entitlement. `isDLCInstalled(4478190)` answers local availability. `installDLC(4478190)` requests installation through Steam when the player owns the DLC but its depots are not installed.

Place Sticker-Shock's distributable files in the depot or depots attached to DLC `4478190`, unless your Steamworks package/depot layout intentionally uses another Valve-supported arrangement. Do not upload only the executable; upload the complete Godot export contents required by the DLC build.

The base launcher should be responsible for deciding whether Sticker-Shock is shown as purchasable, installable, downloading, or playable. Sticker-Shock itself now has an optional second entitlement check as defense in depth.

## 3. Launch flow

The intended flow is:

```text
Steam library
    -> launcher app 4281680
        -> checks DLC 4478190
            -> not owned: show purchase/store action
            -> owned but not installed: show install/download action
            -> installed: launch Sticker-Shock executable
```

When Sticker-Shock starts, GodotSteam still initializes against `4281680`. Its configured DLC identity remains `4478190` for entitlement diagnostics and optional enforcement.

If Sticker-Shock is launched directly as an exported executable and Steam says it should be started through the Steam client, `restartAppIfNecessary(4281680)` redirects execution back to the launcher application rather than attempting to launch the DLC as a standalone Steam app.

## 4. Steam Overlay

The runtime exposes:

```gdscript
SteamManager.open_achievements_overlay()
SteamManager.open_friends_overlay()
SteamManager.open_overlay("Community")
```

Test the overlay from an exported build reached through the Steam launcher flow. GodotSteam documents that the overlay may not appear reliably when the project is launched directly from the Godot editor even when the exported Steam build is correct.

Because the active Steam API session is App `4281680`, overlay application context belongs to the launcher/base app.

## 5. Achievements and stats

The current integration writes achievements and stats through the Steam session for App `4281680`. Therefore achievement/stat API names used by Sticker-Shock should be created under the base launcher application's Steamworks stats/achievements configuration.

Namespace Sticker-Shock entries so multiple DLC games can coexist cleanly, for example:

```text
STICKER_SHOCK_FIRST_PACK
STICKER_SHOCK_COMPLETE_COLLECTION
STICKER_SHOCK_PACKS_OPENED
```

Use `SteamProgress` from gameplay code once the dashboard entries exist:

```gdscript
SteamProgress.unlock_achievement(&"STICKER_SHOCK_FIRST_PACK")
SteamProgress.show_achievement_progress(&"STICKER_SHOCK_COMPLETE_COLLECTION", current_progress, maximum_progress)
SteamProgress.set_stat_int(&"STICKER_SHOCK_PACKS_OPENED", value)
SteamProgress.store_stats()
```

`unlock_achievement()` stores immediately so Steam can display the native unlock notification. Stat setters do not automatically call `storeStats()` so high-frequency gameplay counters can be updated cheaply and committed at meaningful checkpoints. `clear_achievement_for_testing()` is disabled outside debug builds.

If you later want every DLC game to have a completely independent Steam achievement page under its own DLC App ID, that is a different Steam session/product architecture and should be designed deliberately rather than mixing App IDs inside one running API session.

## 6. Rich Presence

The runtime exposes guarded Rich Presence helpers:

```gdscript
SteamManager.set_rich_presence("key", "value")
SteamManager.clear_rich_presence()
```

Rich Presence is published under base App `4281680`. A good launcher-oriented setup is to let each DLC set a game/status token such as Sticker-Shock while preserving one base-app presence configuration.

Configure matching Rich Presence keys and localization in the base application's Steamworks dashboard before relying on player-facing strings.

## 7. Steam Cloud

Sticker-Shock currently persists gameplay under its Godot `user://` directory, including at least:

- `sticker_progress.json`
- `sticker_book.json`
- `sticker_free_pack_bank.json`
- `sticker_market.json`
- `game_preferences.json`

Because the active Steam session is the launcher/base application, configure Cloud ownership and Auto-Cloud rules from App `4281680`. Keep each DLC game's save root distinct so one game's files cannot overwrite another game's data.

Before publishing Cloud configuration, test a Sticker-Shock save on one machine, exit normally, confirm Steam finishes synchronization, then launch through the same base app on a second clean machine and verify that book placements, inventory, free-pack state, market state, and preferences restore correctly.

## 8. Steam Input and controllers

Sticker-Shock already uses Godot's normal controller input actions (`Button_A`, `Button_B`, `Button_Start`, and `StickLeft_*`). No Steam Input API layer has been forced into the game because doing so would duplicate the existing input abstraction and can change controller behavior.

Steam's normal controller remapping can remain enabled at the client level. Add a Steam Input action manifest only if the launcher ecosystem later moves deliberately from Godot input actions to the Steam Input API.

## 9. Steam hardware and Proton

Steamworks SDK 1.65 removed the old dedicated `IsRunningOnSteamDeck()` query. GodotSteam 4.22.1 exposes the replacement hardware APIs used by `SteamManager`:

```gdscript
SteamManager.get_steam_hardware_type()
SteamManager.get_steam_hardware_default_config()
SteamManager.is_running_under_proton()
```

`get_steam_hardware_type()` is useful for diagnostics. Functional quality/performance defaults should prefer `get_steam_hardware_default_config()` rather than hard-coding behavior around one named device. `is_running_under_proton()` is available when a compatibility-specific workaround is genuinely needed.

## 10. Validation checklist

Before promoting the launcher/DLC build:

1. Confirm base application `4281680` owns the Steam library launch entry.
2. Confirm DLC `4478190` is associated with base application `4281680`.
3. Confirm the developer/test account owns the base app and Sticker-Shock DLC.
4. Confirm Sticker-Shock's depot files are associated with the DLC/package arrangement expected by the launcher.
5. Launch App `4281680` from Steam and verify the launcher sees `4478190` as owned.
6. Remove/uninstall the DLC and verify the launcher distinguishes `owned_not_installed` from `not_owned`.
7. Request installation and verify Steam download progress can be presented until `isDLCInstalled(4478190)` becomes true.
8. Launch Sticker-Shock from the launcher and check the log for `base_app=4281680` and `dlc_app=4478190`.
9. Verify Shift+Tab/overlay behavior in the launcher-started Sticker-Shock process.
10. Test published Sticker-Shock achievement/stat API names under App `4281680`.
11. Test Cloud synchronization through the base application across two clean machines or profiles.
12. Quit through both the menu and the window close button and confirm Steam no longer treats the child game process as running after exit.

## Runtime ownership

Steam integration intentionally lives outside `GameController`. `SteamManager` is an autoload with `PROCESS_MODE_ALWAYS`, so Steam callbacks continue regardless of which physical world is active and while the SceneTree is paused. The game uses App `4281680` for the Steam API session and DLC `4478190` for Sticker-Shock entitlement/install state. The two identities are deliberately separate.
