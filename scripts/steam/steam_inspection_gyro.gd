class_name SteamInspectionGyro
extends RefCounted

const GAMEPAD_INDEX_COUNT: int = 4 # Covers Steam Input's gamepad-emulation slots before falling back to every connected controller handle.
const STEAM_INPUT_TYPE_STEAM_CONTROLLER: int = 1 # Identifies the original Valve Steam Controller in the Steamworks ESteamInputType enum.
const STEAM_INPUT_TYPE_PS4_CONTROLLER: int = 5 # Identifies PlayStation controllers whose Steam Input type is known to expose motion sensors.
const STEAM_INPUT_TYPE_SWITCH_JOYCON_PAIR: int = 8 # Identifies paired Switch Joy-Cons whose Steam Input type is known to expose motion sensors.
const STEAM_INPUT_TYPE_SWITCH_JOYCON_SINGLE: int = 9 # Identifies a single Switch Joy-Con whose Steam Input type is known to expose motion sensors.
const STEAM_INPUT_TYPE_SWITCH_PRO_CONTROLLER: int = 10 # Identifies Switch Pro controllers whose Steam Input type is known to expose motion sensors.
const STEAM_INPUT_TYPE_PS5_CONTROLLER: int = 13 # Identifies PlayStation controllers whose Steam Input type is known to expose motion sensors.
const STEAM_INPUT_TYPE_STEAM_DECK_CONTROLLER: int = 14 # Identifies Steam Deck-class hardware in the Steamworks ESteamInputType enum.
const MIN_VALID_QUATERNION_LENGTH_SQUARED: float = 0.50 # Rejects zero-filled motion structs returned by controllers without usable motion sensors.
const MAX_VALID_QUATERNION_LENGTH_SQUARED: float = 1.50 # Rejects malformed motion data before normalization can amplify invalid samples.
const MIN_MOTION_RADIANS: float = 0.0007 # Filters tiny sensor jitter below roughly four hundredths of a degree per sample.
const MAX_SAMPLE_DELTA_RADIANS: float = PI / 3.0 # Treats implausible single-frame rotations above sixty degrees as reconnect/recalibration discontinuities.
const MOTION_WARMUP_INVALID_SAMPLE_LIMIT: int = 180 # Gives a known motion controller time to activate its IMU before treating repeated invalid samples as unavailable.

var _input_initialized: bool = false # Keeps Steam Input initialization idempotent across repeated inspection sessions.
var _session_active: bool = false # Restricts motion polling to an open sticker inspection.
var _controller_handle: int = 0 # Stores the Steam Input handle selected for the current inspection session.
var _controller_type: int = 0 # Stores the Steam Input hardware classification for diagnostics and player-facing hints.
var _has_reference_orientation: bool = false # Tracks whether one valid motion sample has established the neutral incremental reference.
var _previous_orientation: Quaternion = Quaternion.IDENTITY # Stores the previous raw Steam sensor-fused orientation for frame-to-frame delta calculation.
var _motion_active: bool = false # Reports whether the most recent valid sample contained deliberate gyro movement above the jitter threshold.
var _invalid_orientation_samples: int = 0 # Counts consecutive invalid motion samples while a known gyro device is warming its IMU.
var _rejected_controller_handles: Dictionary[int, bool] = {} # Prevents a motion device that never becomes usable from blocking another controller during the same inspection.

func begin_session() -> bool: # Starts automatic gyro tracking for an inspection without snapping the sticker to the controller's absolute pose.
	_session_active = true # Enables polling before attempting discovery so hot-plugged Steam Input devices can appear later in the same inspection.
	_controller_handle = 0 # Forces controller discovery for the new modal session instead of retaining a stale disconnected handle.
	_controller_type = 0 # Clears stale hardware diagnostics until a usable motion device is found.
	_has_reference_orientation = false # Makes the first valid quaternion establish neutral orientation rather than rotate the sticker.
	_previous_orientation = Quaternion.IDENTITY # Restores a harmless reference value until the first sensor sample arrives.
	_motion_active = false # Clears movement state inherited from a previous inspection.
	_invalid_orientation_samples = 0 # Clears any warm-up state inherited from a previous inspection.
	_rejected_controller_handles.clear() # Allows every currently connected Steam Input device to be reconsidered for the new inspection session.
	if not _ensure_input_initialized(): # Requires both a live Steam API session and the GodotSteam Steam Input bridge.
		return false # Leaves right-stick inspection fully functional when Steam or Steam Input is unavailable.
	_run_input_frame() # Requests the freshest controller state before the first discovery pass for lowest practical gyro latency.
	return _discover_motion_controller() # Reports whether a gyro-capable Steam Input device is already available at inspection open.

func end_session() -> void: # Stops inspection-owned gyro tracking while leaving Steam Input initialized for later reuse.
	_session_active = false # Prevents hidden inspection screens from polling controller motion every frame.
	_release_controller() # Releases selected-device state without shutting down the game-wide Steam Input interface.
	_rejected_controller_handles.clear() # Drops inspection-local rejection history so later sessions can retry every connected device.

func recenter() -> void: # Makes the controller's next valid pose the new neutral point after an inspection reset.
	_has_reference_orientation = false # Discards only the incremental reference while preserving the selected live controller handle.
	_previous_orientation = Quaternion.IDENTITY # Leaves no stale quaternion available for the next frame-to-frame delta.
	_motion_active = false # Avoids reporting motion during the single neutral-reference frame.
	_invalid_orientation_samples = 0 # Restarts warm-up tolerance so a controller recalibration cannot be mistaken for a permanent motion failure.

func is_available() -> bool: # Reports whether an open inspection currently has a discovered Steam Input motion device.
	return _session_active and _controller_handle != 0 # Requires both modal ownership and a valid nonzero Steam Input handle.

func is_motion_active() -> bool: # Reports whether the most recent sampled quaternion moved beyond the deliberate jitter filter.
	return is_available() and _motion_active # Suppresses stale movement state when the session or device is unavailable.

func get_device_label() -> String: # Returns a concise player-facing identity for the currently selected Steam motion device.
	match _controller_type: # Gives known Valve hardware a precise label while remaining future-compatible with new Steam Input controller types.
		STEAM_INPUT_TYPE_STEAM_CONTROLLER:
			return "Steam Controller gyro" # Identifies the original Steam Controller hardware family.
		STEAM_INPUT_TYPE_STEAM_DECK_CONTROLLER:
			return "Steam Deck / Valve gyro" # Identifies Steam Deck-class motion hardware without making this enum a requirement for support.
		_:
			return "Steam Input gyro" # Allows other motion-capable Steam Input devices to use the same inspection path.

func sample_rotation_delta() -> Quaternion: # Returns one incremental controller-motion quaternion converted into Godot's inspection coordinate basis.
	_motion_active = false # Requires this sample to prove deliberate movement before reporting active gyro input.
	if not _session_active or not _ensure_input_initialized(): # Rejects hidden inspection and unavailable Steam sessions before native calls.
		return Quaternion.IDENTITY # Leaves existing right-stick or mouse inspection behavior unchanged.
	_run_input_frame() # Synchronizes Steam Input immediately before reading motion for lower latency than waiting only on the callback pump.
	if _controller_handle == 0 and not _discover_motion_controller(): # Supports hot-plugging a Steam Controller or opening on hardware that initializes a few frames late.
		return Quaternion.IDENTITY # Waits harmlessly until a usable motion controller becomes available.
	var motion_data: Dictionary = _get_motion_data(_controller_handle) # Reads the raw sensor-fused quaternion from the selected Steam Input device.
	if not _motion_data_has_valid_orientation(motion_data): # Allows Steam Input's documented IMU warm-up before declaring a selected controller unusable.
		_invalid_orientation_samples += 1 # Tracks consecutive invalid samples so a genuine disconnect does not leave the same dead handle selected forever.
		_has_reference_orientation = false # Prevents the next valid sample from being compared against motion data from before the invalid interval.
		_previous_orientation = Quaternion.IDENTITY # Removes the stale physical pose while waiting for a fresh valid sensor sample.
		if _input_type_has_known_motion(_controller_type) and _invalid_orientation_samples <= MOTION_WARMUP_INVALID_SAMPLE_LIMIT: # Keeps polling a controller family that Steam Input documents as motion-capable while its IMU becomes ready.
			return Quaternion.IDENTITY # Leaves the sticker stable during sensor warm-up instead of repeatedly dropping and rediscovering the device.
		_rejected_controller_handles[_controller_handle] = true # Stops a persistently invalid device from monopolizing discovery for the rest of this inspection.
		_release_controller() # Clears the failed selection so another connected motion controller can be considered on the next frame.
		return Quaternion.IDENTITY # Leaves the sticker unchanged while controller discovery recovers.
	_invalid_orientation_samples = 0 # Clears warm-up failure state as soon as the selected controller produces a valid orientation.
	var current_orientation: Quaternion = _quaternion_from_motion_data(motion_data) # Normalizes the valid Steam orientation before any delta calculation.
	if not _has_reference_orientation: # Uses the first valid physical pose only as a neutral reference.
		_previous_orientation = current_orientation # Stores the current controller pose without changing the sticker.
		_has_reference_orientation = true # Enables incremental motion beginning with the next valid sample.
		return Quaternion.IDENTITY # Prevents the sticker from snapping to Steam's absolute sensor-fused orientation.
	if _previous_orientation.dot(current_orientation) < 0.0: # Handles mathematically equivalent q versus -q representations without creating a false 360-degree jump.
		current_orientation = Quaternion(-current_orientation.x, -current_orientation.y, -current_orientation.z, -current_orientation.w) # Moves the sample onto the same quaternion hemisphere as the previous frame.
	var steam_delta: Quaternion = (current_orientation * _previous_orientation.inverse()).normalized() # Calculates only the physical rotation that occurred since the previous Steam Input sample.
	_previous_orientation = current_orientation # Advances the reference immediately so every frame remains incremental instead of following absolute controller orientation.
	var delta_angle: float = steam_delta.get_angle() # Measures physical movement magnitude before coordinate conversion or application.
	if delta_angle < MIN_MOTION_RADIANS: # Filters stationary-controller sensor noise from the visible sticker transform.
		return Quaternion.IDENTITY # Keeps the inspected sticker visually stable while the controller rests.
	if delta_angle > MAX_SAMPLE_DELTA_RADIANS: # Detects discontinuities caused by reconnects, Steam Input recalibration, or invalid one-frame sensor jumps.
		_has_reference_orientation = false # Re-establishes neutral orientation on the following valid sample instead of applying the implausible jump.
		return Quaternion.IDENTITY # Protects inspection from sudden large rotations outside deliberate physical motion.
	_motion_active = true # Marks this sample as genuine gyro motion for input-mode presentation and diagnostics.
	return _steam_delta_to_godot(steam_delta) # Converts Steam's controller orientation basis into the Godot inspection world's basis.

func _ensure_input_initialized() -> bool: # Lazily initializes Steam Input only when sticker inspection actually needs motion sensors.
	if _input_initialized: # Reuses the already initialized Steam Input interface across every later inspection.
		return true # Avoids redundant native initialization calls after the first successful session.
	if not SteamManager.is_available(): # Requires the existing authoritative Steamworks client session before initializing its Input interface.
		return false # Keeps non-Steam/editor fallback behavior completely functional.
	if not Steam.has_method(&"inputInit") or not Steam.has_method(&"getMotionData") or not Steam.has_method(&"getConnectedControllers"): # Verifies the installed GodotSteam build exposes the required Steam Input bridge.
		return false # Avoids runtime method errors on incompatible addon builds.
	var initialized: Variant = Steam.call(&"inputInit", true) # Explicitly gives this helper ownership of Steam Input frame synchronization because it performs low-latency runFrame calls itself.
	_input_initialized = bool(initialized) # Caches the actual GodotSteam initialization result rather than assuming Steam API availability implies Input availability.
	return _input_initialized # Reports whether motion polling may proceed safely.

func _run_input_frame() -> void: # Synchronizes Steam Input state immediately before motion reads when the installed GodotSteam build exposes the low-latency call.
	if _input_initialized and Steam.has_method(&"runFrame"): # Keeps compatibility with addon builds that expose the explicit Steam Input frame path.
		Steam.call(&"runFrame") # Requests the latest physical controller state immediately before discovery or motion reads.

func _discover_motion_controller() -> bool: # Chooses the first usable motion device in active gamepad-slot order, then falls back to remaining Steam Input controllers.
	if not _input_initialized: # Rejects discovery before Steam Input has a live interface.
		return false # Leaves the session waiting for initialization.
	var candidates: Array[int] = [] # Stores unique controller handles with primary gamepad-emulation slots first so the controller actually driving the game wins.
	if Steam.has_method(&"getControllerForGamepadIndex"): # Uses Steam's gamepad-emulation mapping first so an external Steam Controller can correctly outrank a dormant built-in Deck controller.
		for gamepad_index: int in range(GAMEPAD_INDEX_COUNT): # Checks the standard emulated gamepad slots in player order.
			_add_candidate(candidates, int(Steam.call(&"getControllerForGamepadIndex", gamepad_index))) # Adds each valid nonzero mapped handle exactly once.
	var connected_value: Variant = Steam.call(&"getConnectedControllers") # Enumerates every remaining Steam Input controller so native Deck and hot-plugged motion devices are never missed.
	if connected_value is Array: # Handles GodotSteam's ordinary controller-handle array representation.
		var connected_array: Array = connected_value # Narrows the returned Variant once before iterating its controller handles.
		for handle_value: Variant in connected_array: # Visits each returned Steam Input handle once.
			_add_candidate(candidates, int(handle_value)) # Normalizes integer Variants and suppresses duplicates from gamepad-slot discovery.
	elif connected_value is PackedInt64Array: # Supports packed-handle return shapes without binding this helper to one GodotSteam implementation detail.
		var connected_packed: PackedInt64Array = connected_value # Narrows the returned Variant once before iterating packed controller handles.
		for packed_handle: int in connected_packed: # Visits every packed Steam Input handle.
			_add_candidate(candidates, packed_handle) # Adds the handle through the same validity and duplicate guard.
	for candidate: int in candidates: # Preserves active player-controller ordering instead of letting a secondary built-in Deck gyro steal inspection ownership.
		var candidate_type: int = _get_input_type(candidate) # Reads hardware classification before motion validation so known IMU devices can survive Steam Input's warm-up period.
		var motion_data: Dictionary = _get_motion_data(candidate) # Performs the first motion read, which also activates the controller IMU according to Steam Input's lifecycle contract.
		if not _motion_data_has_valid_orientation(motion_data) and not _input_type_has_known_motion(candidate_type): # Rejects devices without valid motion while allowing known gyro hardware time to warm up.
			continue # Checks the next connected Steam Input handle without changing session state.
		_controller_handle = candidate # Commits the first usable or known-motion device according to active-player ordering.
		_controller_type = candidate_type # Stores hardware classification for concise hints and warm-up handling.
		_has_reference_orientation = false # Makes this newly selected controller's first valid sample establish neutral orientation.
		_previous_orientation = Quaternion.IDENTITY # Ensures no orientation from an earlier controller can participate in the new device's first delta.
		_invalid_orientation_samples = 0 # Starts this controller's warm-up accounting from a clean state.
		if OS.is_debug_build(): # Emits one concise development diagnostic without adding release-build console noise.
			print("Steam inspection gyro selected: handle=%d type=%d label=%s" % [_controller_handle, _controller_type, get_device_label()]) # Identifies which Steam Input device currently owns motion during testing.
		return true # Confirms that automatic inspection gyro polling can begin for the selected controller.
	return false # Leaves inspection on right-stick/mouse rotation when no connected Steam Input controller can provide motion.

func _add_candidate(candidates: Array[int], handle: int) -> void: # Adds one valid Steam Input handle exactly once while preserving discovery priority order.
	if handle == 0 or candidates.has(handle) or _rejected_controller_handles.has(handle): # Rejects Steam's invalid handle, duplicate candidates, and devices already proven unusable this session.
		return # Leaves candidate ordering unchanged for invalid, duplicate, or rejected devices.
	candidates.append(handle) # Preserves gamepad-slot priority before remaining connected-controller enumeration order.

func _release_controller() -> void: # Clears selected-device state while preserving Steam Input initialization and session ownership.
	_controller_handle = 0 # Releases the current Steam Input device so discovery can choose another handle.
	_controller_type = 0 # Clears device diagnostics together with the released handle.
	_has_reference_orientation = false # Prevents a replacement controller from inheriting another device's physical pose.
	_previous_orientation = Quaternion.IDENTITY # Restores a harmless orientation baseline until a new controller establishes neutral.
	_motion_active = false # Clears movement state when no selected controller owns gyro input.
	_invalid_orientation_samples = 0 # Clears warm-up accounting together with the device it described.

func _get_motion_data(handle: int) -> Dictionary: # Reads one GodotSteam motion struct defensively through the runtime method boundary.
	if handle == 0 or not Steam.has_method(&"getMotionData"): # Rejects invalid handles and addon builds without motion-data support.
		return {} # Returns an empty structure that naturally fails orientation validation.
	var motion_value: Variant = Steam.call(&"getMotionData", handle) # Requests Steamworks InputMotionData_t through GodotSteam without compile-time dependence on extension method metadata.
	if motion_value is Dictionary: # Accepts only the structured Godot dictionary form expected from the GodotSteam bridge.
		return motion_value # Returns the already validated runtime type through the strongly typed method boundary.
	return {} # Treats any unexpected addon return shape as unavailable motion data rather than raising a cast error.

func _get_input_type(handle: int) -> int: # Reads Steam's hardware classification when available without making it a requirement for gyro support.
	if handle == 0 or not Steam.has_method(&"getInputTypeForHandle"): # Supports GodotSteam builds that expose motion data but omit hardware-type helpers.
		return 0 # Uses the generic Steam Input gyro label and preserves support through actual motion-data validation.
	return int(Steam.call(&"getInputTypeForHandle", handle)) # Returns the current Steamworks ESteamInputType integer unchanged.

func _input_type_has_known_motion(controller_type: int) -> bool: # Identifies Steam Input hardware families whose standard devices include gyro motion sensors.
	match controller_type: # Keeps warm-up tolerance constrained to controller families with known motion capability instead of masking unsupported devices.
		STEAM_INPUT_TYPE_STEAM_CONTROLLER, STEAM_INPUT_TYPE_PS4_CONTROLLER, STEAM_INPUT_TYPE_SWITCH_JOYCON_PAIR, STEAM_INPUT_TYPE_SWITCH_JOYCON_SINGLE, STEAM_INPUT_TYPE_SWITCH_PRO_CONTROLLER, STEAM_INPUT_TYPE_PS5_CONTROLLER, STEAM_INPUT_TYPE_STEAM_DECK_CONTROLLER:
			return true # Allows the selected known-motion device to remain attached while its IMU becomes ready.
		_:
			return false # Requires an immediately valid motion quaternion for unknown or non-motion controller families.

func _motion_data_has_valid_orientation(data: Dictionary) -> bool: # Distinguishes a real normalized sensor-fused quaternion from zero-filled unsupported motion data.
	if data.is_empty(): # Rejects missing motion structures immediately.
		return false # Prevents invalid dictionary field reads and quaternion construction.
	var x: float = _motion_field(data, "rotQuatX", "rot_quat_x") # Reads GodotSteam's established camelCase field while accepting a snake_case compatibility alias.
	var y: float = _motion_field(data, "rotQuatY", "rot_quat_y") # Reads the sensor-fused Y quaternion component.
	var z: float = _motion_field(data, "rotQuatZ", "rot_quat_z") # Reads the sensor-fused Z quaternion component.
	var w: float = _motion_field(data, "rotQuatW", "rot_quat_w") # Reads the sensor-fused scalar quaternion component.
	if not is_finite(x) or not is_finite(y) or not is_finite(z) or not is_finite(w): # Rejects NaN or infinite native data before normalization.
		return false # Prevents malformed sensor values from contaminating inspection orientation.
	var length_squared: float = x * x + y * y + z * z + w * w # Measures quaternion validity without allocating a temporary normalized object.
	return length_squared >= MIN_VALID_QUATERNION_LENGTH_SQUARED and length_squared <= MAX_VALID_QUATERNION_LENGTH_SQUARED # Accepts approximately normalized orientations while rejecting all-zero/nonphysical values.

func _quaternion_from_motion_data(data: Dictionary) -> Quaternion: # Constructs a normalized Steam sensor-fusion quaternion from GodotSteam's motion dictionary.
	return Quaternion(_motion_field(data, "rotQuatX", "rot_quat_x"), _motion_field(data, "rotQuatY", "rot_quat_y"), _motion_field(data, "rotQuatZ", "rot_quat_z"), _motion_field(data, "rotQuatW", "rot_quat_w")).normalized() # Preserves Steam's complete four-component absolute orientation before delta conversion.

func _motion_field(data: Dictionary, camel_case: String, snake_case: String) -> float: # Reads one motion field across GodotSteam dictionary naming variants without exposing that compatibility logic to callers.
	if data.has(camel_case): # Prefers the established GodotSteam/InputMotionData_t field spelling.
		return float(data.get(camel_case, 0.0)) # Converts the raw Variant into the strongly typed float used by quaternion math.
	return float(data.get(snake_case, 0.0)) # Falls back to a common snake_case bridge spelling when present, otherwise returning a safe zero.

func _steam_delta_to_godot(steam_delta: Quaternion) -> Quaternion: # Converts Steam's incremental sensor-fused rotation into the Godot inspection basis without using Euler angles.
	var axis_conversion: Quaternion = Quaternion(Vector3.RIGHT, -PI * 0.5) # Maps the Steam motion frame into the inspection world's right/up/back convention while preserving a proper rotational basis.
	return (axis_conversion * steam_delta * axis_conversion.inverse()).normalized() # Conjugates the incremental physical rotation so pitch, yaw, and roll remain a single unrestricted quaternion.
