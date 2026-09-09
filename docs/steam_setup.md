# Steam setup

Sticker-Shock uses the GodotSteam GDExtension already committed under `addons/godotsteam/`. The installed plug-in reports GodotSteam 4.22.1 and includes the native Steamworks runtime dependencies in its `.gdextension` manifest.

The game now owns Steam initialization through the `SteamManager` autoload. GodotSteam automatic initialization and embedded callbacks are deliberately disabled so there is one clear lifecycle owner. `SteamManager` initializes with `steamInitEx()`, pumps `Steam.run_callbacks()` every frame even while the game is paused, exposes common overlay/Rich Presence helpers, and calls `steamShutdown()` during normal application teardown.

## 1. Set the real Steam App ID

`project.godot` currently contains:

```ini
[steam]
initialization/app_data/app_id=0
initialization/processes/initialize_on_startup=false
initialization/processes/embed_callbacks=false
integration/require_steam=false
integration/restart_through_steam=true
```

Replace `initialization/app_data/app_id=0` with Sticker-Shock's real numeric Steam App ID before making a Steam build. The repository did not contain an App ID, so one has not been guessed or replaced with Spacewar's test ID.

`integration/restart_through_steam=true` makes exported builds use `Steam.restartAppIfNecessary()` when a real App ID is configured. Editor runs deliberately skip that restart so normal Godot development remains fast.

Keep `integration/require_steam=false` while initially validating the integration. When the Steamworks packages, developer licenses, depots, and launch options are known to be correct, change it to `true` if the release should refuse to run without a valid Steam session and ownership entitlement.

A local `steam_appid.txt` is ignored by Git. It can still be used for SDK/debug workflows if needed, but the normal integration passes the configured App ID directly to GodotSteam.

## 2. Steamworks application and packages

In Steamworks, verify that the Sticker-Shock application exists and that the development account has a package granting ownership of the app. Steam initialization can succeed while ownership checks fail if the account does not have the correct package/license.

Under the application's installation settings, create the launch option for each platform being shipped and point it at the executable produced by the corresponding Godot export.

Do not upload only the executable. Upload the complete Godot export directory. GodotSteam requires its native GDExtension library and the Steam API redistributable beside/in the exported package as produced by Godot. On Windows this includes the GodotSteam Windows library and `steam_api64.dll` for a 64-bit build; the `.gdextension` manifest already declares the matching Linux and macOS dependencies as well.

## 3. Steam Overlay

The runtime exposes:

```gdscript
SteamManager.open_achievements_overlay()
SteamManager.open_friends_overlay()
SteamManager.open_overlay("Community")
```

Test the overlay from an exported build launched by the Steam client. GodotSteam documents that the overlay may not appear reliably when the project is launched directly from the Godot editor even when the exported Steam build is correct.

## 4. Achievements and stats

Steam achievement/stat API names must be authored and published in the Steamworks dashboard before the game can successfully write them. Sticker-Shock does not currently define a canonical achievement list in the repository, so no fake achievement IDs have been invented.

Use `SteamProgress` from gameplay code once the dashboard entries exist:

```gdscript
SteamProgress.unlock_achievement(&"ACH_API_NAME")
SteamProgress.show_achievement_progress(&"ACH_API_NAME", current_progress, maximum_progress)
SteamProgress.set_stat_int(&"STAT_API_NAME", value)
SteamProgress.set_stat_float(&"STAT_API_NAME", value)
SteamProgress.store_stats()
```

`unlock_achievement()` stores immediately so Steam can display the native unlock notification. Stat setters do not automatically call `storeStats()` so high-frequency gameplay counters can be updated cheaply and committed at meaningful checkpoints. `clear_achievement_for_testing()` is disabled outside debug builds.

Steamworks achievement/stat definitions must use the exact same API names and compatible stat types. Publish dashboard changes before testing them in a build.

## 5. Rich Presence

The runtime exposes guarded Rich Presence helpers:

```gdscript
SteamManager.set_rich_presence("key", "value")
SteamManager.clear_rich_presence()
```

For player-facing Rich Presence text, configure the matching Rich Presence keys/localization in Steamworks first. The game deliberately does not invent status tokens because those become part of the public Steam configuration.

## 6. Steam Cloud

Sticker-Shock currently persists gameplay under Godot's `user://` directory, including at least:

- `sticker_progress.json`
- `sticker_book.json`
- `sticker_free_pack_bank.json`
- `sticker_market.json`
- `game_preferences.json`

The simplest Steam integration is Steam Auto-Cloud. Configure Auto-Cloud in Steamworks to synchronize the Sticker-Shock Godot `user://` save directory on each supported desktop platform. Prefer syncing the save JSON files rather than mirroring the project/install directory.

Before publishing Cloud configuration, test a save on one machine, exit normally, confirm Steam finishes synchronization, then launch on a second clean machine and verify that book placements, inventory, free-pack state, market state, and preferences restore correctly.

## 7. Steam Input and controllers

Sticker-Shock already uses Godot's normal controller input actions (`Button_A`, `Button_B`, `Button_Start`, and `StickLeft_*`). No Steam Input API layer has been forced into the game because doing so would duplicate the existing input abstraction and can change controller behavior.

Steam's normal controller remapping can remain enabled at the client level. Add a Steam Input action manifest only if Sticker-Shock later moves deliberately from Godot input actions to the Steam Input API.

## 8. Steam hardware and Proton

Steamworks SDK 1.65 removed the old dedicated `IsRunningOnSteamDeck()` query. GodotSteam 4.22.1 exposes the replacement hardware APIs used by `SteamManager`:

```gdscript
SteamManager.get_steam_hardware_type()
SteamManager.get_steam_hardware_default_config()
SteamManager.is_running_under_proton()
```

`get_steam_hardware_type()` is useful for diagnostics and analytics. Functional quality/performance defaults should prefer `get_steam_hardware_default_config()` rather than hard-coding behavior around one named device. `is_running_under_proton()` is available when a compatibility-specific workaround is genuinely needed.

No Steam-hardware-specific gameplay branch is currently required because Sticker-Shock already has controller navigation and a scalable desktop UI. Validate the exported Linux/Proton build through Steam, including controller-only navigation, text-entry behavior, pause/back actions, overlay behavior, and cloud-save restoration.

## 9. Build validation checklist

Before promoting a Steam build:

1. Set the real `steam/initialization/app_data/app_id`.
2. Export from Godot and upload the complete export directory to the correct depot.
3. Confirm the Steam launch option starts that executable.
4. Launch from the Steam client and check the startup log for `Steam initialized` with the expected App ID and Steam ID.
5. Verify Shift+Tab/overlay behavior in the Steam-launched export.
6. Verify the account reports ownership before enabling `integration/require_steam=true`.
7. Test any published achievement/stat API names with `SteamProgress`.
8. Test Auto-Cloud across two machines or two clean user profiles.
9. Test controller-only navigation and Linux/Proton or Steam hardware configurations that are being supported.
10. Quit through both the menu and the window close button and confirm Steam no longer reports the game as running after the process exits.

## Runtime ownership

Steam integration intentionally lives outside `GameController`. `SteamManager` is an autoload with `PROCESS_MODE_ALWAYS`, so Steam callbacks continue regardless of which physical world is active and while the SceneTree is paused. The rest of Sticker-Shock can use Steam features through the small guarded API without acquiring Steam lifecycle responsibility or adding callback signal connections throughout gameplay code.
