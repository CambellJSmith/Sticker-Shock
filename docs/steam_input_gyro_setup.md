# Steam Input gyro setup for sticker inspection

Sticker-Shock reads the controller's sensor-fused orientation through `ISteamInput::GetMotionData`. The game does **not** convert gyro movement into mouse or right-stick input; it applies the motion quaternion directly to the inspected sticker.

That distinction matters because Steam Input can discover a motion-capable controller while the active controller layout is not servicing its gyro. In that state the game can obtain a valid controller handle and hardware type but still receive an unusable/zero motion quaternion.

## What the game now reports

Debug builds distinguish three separate states:

1. `Steam inspection gyro selected` — Steam Input found a controller handle whose hardware is motion-capable.
2. `Steam inspection gyro waiting for valid motion` — the handle exists, but `GetMotionData` is not returning a usable orientation quaternion.
3. `Steam inspection gyro ready` — a valid approximately-normalized orientation has actually arrived and sticker rotation can begin.

Do not treat `selected` as proof that gyro data is working. `ready` is the successful state.

## Immediate development test

Before changing the Steamworks configuration, use Steam's controller-layout screen for App ID **4281680** and give the Steam Controller gyro an active behavior temporarily.

1. Run Sticker-Shock through Steam with the Steam Controller connected.
2. Open the game's Controller Layout / Edit Layout screen in Steam.
3. Open the **Gyro** section.
4. Change Gyro Behavior from **None** to an active gyro behavior temporarily.
5. Return to the game and reopen a sticker inspection.
6. Watch the Godot output.

The important result is:

```text
Steam inspection gyro ready: ...
```

If the log remains on `waiting for valid motion`, paste that diagnostic line into the issue/debug conversation. It includes the exact quaternion and raw GodotSteam motion dictionary.

This temporary layout change is only a diagnostic. Do not ship a layout that maps the inspection gyro to mouse or right-stick movement across the whole game, because that would create unrelated input outside sticker inspection and can cause double rotation while the game is also consuming raw motion.

## Recommended shipping configuration

Valve supports an official Steam Input configuration for each supported controller. For Sticker-Shock, the clean design is:

- keep ordinary buttons/sticks behaving as they do now;
- expose a dedicated Steam Input gyro action such as `InspectionGyro`;
- bind the Steam Controller's physical gyro to that dedicated action in the official Steam Controller configuration;
- continue to use `GetMotionData` for the actual three-axis sticker orientation;
- do not translate the gyro into mouse/right-stick input merely to wake the sensor.

A dedicated action is preferable because Steam can keep the gyro active without causing operating-system mouse movement or conventional gamepad look input.

## Steamworks setup

Valve's current Steam Input workflow is:

1. Create an In-Game Actions / Action Manifest file for the base application, App ID **4281680**.
2. Add the game's action set(s) and a `StickPadGyro` action for inspection motion.
3. Enable Steam Input layout development mode in the Steam client while authoring the official configuration.
4. Edit the Steam Controller layout and bind its gyro to the inspection action.
5. Export/save that layout as the developer configuration.
6. In the Steamworks partner site, configure Steam Input for App ID **4281680** and publish the official Steam Controller configuration.
7. Test from an account receiving the current Steam build, not only from an editor-launched process.

Sticker-Shock initializes Steam as base App ID **4281680**, so the Steam Input configuration belongs to **4281680**, not DLC App ID 4478190.

## Bundled configuration option

Valve also supports bundling the action manifest and official controller configuration files in the game depot. In Steamworks this is configured as **Custom Configuration (Bundled with game)** and the partner site is pointed at the action-manifest path inside the depot.

Bundling is useful once the layout is stable because the controller configuration can be versioned alongside the project and updated atomically with the build.

Do not hand-author a full Steam Controller configuration file unless necessary. Valve's recommended workflow is to use Steam Input layout developer mode to create/export the configuration, then commit the exported VDF files to the repository.

## Runtime validation

With the official layout active, open a sticker and verify the following order in a debug build:

```text
Steam inspection input initialization: result=true
Steam inspection gyro selected: ... motion_ready=...
Steam inspection gyro ready: ...
```

After `ready`, physically pitching, yawing, and rolling the controller should rotate the sticker immediately. The first valid pose is used as neutral, so opening inspection should not snap the sticker to an arbitrary absolute controller orientation.

If `selected` appears but `ready` never does, the problem is upstream of the sticker quaternion application. The first `waiting for valid motion` line should then be used to determine whether Steam is returning zeros, malformed data, or another unexpected representation.

## References

- Valve Steam Input — Getting Started for Developers: https://partner.steamgames.com/doc/features/steam_controller/getting_started_for_devs
- Valve Steam Input — In-Game Actions File: https://partner.steamgames.com/doc/features/steam_controller/iga_file
- Valve Steam Input — Action Manifest Files: https://partner.steamgames.com/doc/features/steam_controller/action_manifest_file
- Valve Steam Input API: https://partner.steamgames.com/doc/api/isteaminput
