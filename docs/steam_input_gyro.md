# Steam Input inspection gyro

Sticker inspection automatically reads motion from Steam Input when a compatible controller exposes a valid sensor-fused orientation quaternion.

## Supported behavior

- Steam Controller (2015) gyro is supported through Steam Input motion data.
- Steam Deck gyro is supported through the same Steam Input path.
- Newer Steam Controller hardware is supported by motion capability rather than by requiring one hard-coded controller enum, so a new Steam Input type can still be selected when `getMotionData()` returns a valid orientation.
- Other Steam Input controllers with valid motion data can use the same fallback path.
- The first valid controller pose after inspection opens becomes the neutral reference. The sticker does not snap to Steam's absolute controller orientation.
- Every later sensor-fused quaternion is compared with the previous sample and only the incremental rotation is applied to the sticker.
- Small stationary sensor noise is ignored and implausibly large one-frame jumps trigger a fresh neutral reference instead of rotating the sticker violently.
- Right-stick rotation, shoulder roll, mouse rotation, and all existing inspection controls remain available alongside gyro.
- R3 resets the sticker view and recenters the gyro reference at the controller's current physical pose.
- Disconnecting the motion controller leaves inspection usable through the existing controls; reconnecting or hot-plugging a compatible Steam Input controller is discovered while the inspection remains open.

## Steam lifecycle

The gyro helper does not create a second Steamworks session. It requires the existing `SteamManager` session to be live, then lazily initializes the Steam Input interface only when inspection first needs motion data.

During an open inspection it calls Steam Input's frame synchronization immediately before motion reads when the installed GodotSteam build exposes `runFrame()`. Valve documents this as the lowest-latency way to obtain current controller state; the application's existing Steam callback pump continues normally.

The implementation uses runtime method checks for `inputInit`, `getConnectedControllers`, `getControllerForGamepadIndex`, `getInputTypeForHandle`, `getMotionData`, and `runFrame`, so a non-Steam run or incompatible addon build falls back cleanly instead of breaking inspection.

## Controller selection

Controller discovery is ordered deliberately:

1. Steam Input gamepad-emulation slots 0 through 3 are checked in player order.
2. Remaining connected Steam Input handles are appended without duplicates.
3. The first handle that returns a valid approximately normalized motion quaternion owns inspection gyro input.

This keeps an external player-one Steam Controller ahead of a secondary built-in Deck controller when both are connected, while still allowing the Deck gyro to be found when it is the active controller.

## Runtime validation

For the final hardware check, launch an exported build through Steam with the intended controller connected and open any sticker inspection.

A debug build prints a line similar to:

```text
Steam inspection gyro ready: handle=123456789 type=14 label=Steam Deck / Valve gyro
```

Validate the following:

1. Hold the controller in a comfortable pose before opening inspection; the sticker should remain at its canonical orientation when the modal appears.
2. Pitch, yaw, and roll the controller; the sticker should follow the physical rotation smoothly.
3. Stop moving the controller; the sticker should remain visually stable rather than continuously jittering.
4. Use the right stick while gyro is available; both inputs should compose without resetting each other.
5. Press R3 while holding the controller at a new angle; the sticker should reset and subsequent gyro motion should continue from that new neutral pose.
6. Disconnect the controller during inspection; right-stick/mouse controls should continue working.
7. Reconnect a compatible controller; gyro should be rediscovered without reopening the game.
8. On a docked Steam Deck with an external Steam Controller, confirm that the controller assigned to the primary gamepad slot drives the sticker rather than the dormant built-in Deck gyro.

Valve's current `ISteamInput::GetMotionData` documentation notes that the returned quaternion is sensor-fused absolute orientation and can drift in yaw. The game deliberately consumes frame-to-frame quaternion differences instead of binding the sticker to that absolute orientation, which prevents opening-pose snapping and limits absolute-heading drift from becoming a hard orientation constraint.

Reference: https://partner.steamgames.com/doc/api/isteaminput
