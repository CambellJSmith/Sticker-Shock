class_name SteamInspectionGyro
extends RefCounted

const GAMEPAD_INDEX_COUNT: int = 4 # Covers Steam Input's gamepad-emulation slots before falling back to every connected controller handle.
const STEAM_INPUT_TYPE_STEAM_CONTROLLER: int = 1 # Identifies the original Valve Steam Controller in the Steamworks ESteamInputType enum.
const STEAM_INPUT_TYPE_STEAM_DECK_CONTROLLER: int = 14 # Identifies Steam Deck-class hardware; current Steam Input also reports newer Valve controller hardware through this value.
const MIN_VALID_QUATERNION_LENGTH_SQUARED: float = 0.50 # Rejects zero-filled motion structs returned by controllers without usable motion sensors.
const MAX_VALID_QUATERNION_LENGTH_SQUARED: float = 1.50 # Rejects malformed motion data before normalization can amplify invalid samples.
const MIN_MOTION_RADIANS: float = 0.0007 # Filters tiny sensor jitter below roughly four hundredths of a degree per sample.
const MAX_SAMPLE_DELTA_RADIANS: float = PI / 3.0 # Treats implausible single-frame rotations above sixty degrees as reconnect/recalibration discontinuities.

var _input_initialized: bool = false # Keeps Steam Input initialization idempotent across repeated inspection sessions.
var _session_active: bool = false # Restricts motion polling to an open sticker inspection.
var _controller_handle: int = 0 # Stores the Steam Input handle selected for the current inspection session.
var _controller_type: int = 0 # Stores the Steam Input hardware classification for diagnostics and prioritization.
var _has_reference_orientation: bool = false # Tracks whether one valid motion sample has established the neutral incremental reference.
var _previous_orientation: Quaternion = Quaternion.IDENTITY # Stores the previous raw Steam sensor-fused orientation for frame-to-frame delta calculation.
var _motion_active: bool = false # Reports whether the most recent valid sample contained deliberate gyro movement above the jitter threshold.

func begin_session() -> bool: # Starts automatic gyro tracking for an inspection without snapping the sticker to the controller's absolute pose.
	_session_active = true # Enables polling before attempting discovery so hot-plugged Steam Input devices can appear later in the same inspection.
	_controller_handle = 0 # Forces controller discovery for the new modal session instead of retaining a stale disconnected handle.
	_controller_type = 0 # Clears stale hardware diagnostics until a usable motion device is found.
	_has_reference_orientation = false # Makes the first valid quaternion establish neutral orientation rather than rotate the sticker.
	_previous_orientation = Quaternion.IDENTITY # Restores a harmless reference value until the first sensor sample arrives.
	_motion_active = false # Clears movement state inherited from a previous inspection.
	if not _ensure_input_initialized(): # Requires both a live Steam API session and the GodotSteam Steam Input bridge.
		return false # Leaves right-stick inspection fully functional when Steam or Steam Input is unavailable.
	_run_input_frame() # Requests the freshest controller state before the first discovery pass for lowest practical gyro latency.
	return _discover_motion_controller() # Reports whether a gyro-capable Steam Input device is already available at inspection open.

func end_session() -> void: # Stops inspection-owned gyro tracking while leaving Steam Input initialized for later reuse.
	_session_active = false # Prevents hidden inspection screens from polling controller motion every frame.
	_controller_handle = 0 # Releases the selected device handle so reconnects are rediscovered cleanly next time.
	_controller_type = 0 # Clears device diagnostics together with the released handle.
	_has_reference_orientation = false # Prevents a future session from applying a stale physical-controller delta.
	_previous_orientation = Quaternion.IDENTITY # Restores a harmless orientation baseline after the modal closes.
	_motion_active = false # Clears the last movement state immediately when inspection loses ownership.

func recenter() -> void: # Makes the controller's next valid pose the new neutral point after an inspection reset.
	_has_reference_orientation = false # Discards only the incremental reference while preserving the selected live controller handle.
	_previous_orientation = Quaternion.IDENTITY # Leaves no stale quaternion available for the next frame-to-frame delta.
	_motion_active = false # Avoids reporting motion during the single neutral-reference frame.

func is_available() -> bool: # Reports whether an open inspection currently has a discovered Steam Input motion device.
	return _session_active and _controller_handle != 0 # Requires both modal ownership and a valid nonzero Steam Input handle.

func is_motion_active() -> bool: # Reports whether the most recent sampled quaternion moved beyond the deliberate jitter filter.
	return is_available() and _motion_active # Suppresses stale movement state when the session or device is unavailable.

func get_device_label() -> String: # Returns a concise player-facing identity for the currently selected Steam motion device.
	match _controller_type: # Keeps labels intentionally broad because current Steam Input can classify multiple Valve devices under the same type.
		STEAM_INPUT_TYPE_STEAM_CONTROLLER:
			return "Steam Controller gyro" # Identifies the original Steam Controller hardware family.
		STEAM_INPUT_TYPE_STEAM_DECK_CONTROLLER:
			return "Steam Deck / Valve controller gyro" # Covers the Deck and newer Valve controller hardware currently surfaced through this Steam Input type.
		_:
			return "Steam Input gyro" # Supports any additional Steam Input motion-capable controller without hard-coding future enum values.

func sample_rotation_delta() -> Quaternion: # Returns one incremental controller-motion quaternion converted into Godot's inspection coordinate basis.
	_motion_active = false # Requires this sample to prove deliberate movement before reporting active gyro input.
	if not _session_active or not _ensure_input_initialized(): # Rejects hidden inspection and unavailable Steam sessions before native calls.
		return Quaternion.IDENTITY # Leaves existing right-stick or mouse inspection behavior unchanged.
	_run_input_frame() # Synchronizes Steam Input immediately before reading motion for lower latency than waiting only on the callback pump.
	if _controller_handle == 0 and not _discover_motion_controller(): # Supports hot-plugging a Steam Controller or opening on hardware that initializes a few frames late.
		return Quaternion.IDENTITY # Waits harmlessly until a valid motion quaternion becomes available.
	var motion_data: Dictionary = _get_motion_data(_controller_handle) # Reads the raw sensor-fused quaternion from the selected Steam Input device.
	if not _motion_data_has_valid_orientation(motion_data): # Detects disconnects, non-motion devices, or temporarily invalid sensor state.
		_controller_handle = 0 # Forces rediscovery instead of repeatedly reading a dead controller handle.
		_controller_type = 0 # Clears stale device diagnostics together with the failed handle.
		_has_reference_orientation = false # Prevents a future replacement controller from inheriting another device's physical pose.
		return Quaternion.IDENTITY # Leaves the sticker unchanged during reconnection.
	var current_orientation: Quaternion = _quaternion_from_motion_data(motion_data) # Normalizes the valid Steam orientation before any delta calculation.
	if not _has_reference_orientation: # Uses the first valid physical pose only as a neutral reference.
		_previous_orientation = current_orientation # Stores the current controller pose without changing the sticker.
		_has_reference_orientation = true # Enables incremental motion beginning with the next valid sample.
		return Quaternion.IDENTITY # Prevents the sticker from snapping to Steam's absolute sensor-fused orientation.
	if _previous_orientation.dot(current_orientation) < 0.0: # Handles mathematically equivalent q versus -q representations without creating a false 360-degree jump.
		current_orientation = Quaternion(-current_orientation.x, -current_orientation.y, -current_orientation.z, -current_orientation.w) # Moves the sample onto the same quaternion hemisphere as the previous frame.
	var steam_delta: Quaternion = (current_orientation * _previous_orientation.inverse()).normalized() # Calculates only the physical rotation that occurred since the previous Steam Input sample.
	_previous_orientation = current_orientation # Advances the reference immediately so every frame remains incremental and drift cannot snap absolute sticker orientation.
	var delta_angle: float = steam_delta.get_angle() # Measures physical movement magnitude before coordinate conversion or application.
	if delta_angle < MIN_MOTION_RADIANS: # Filters stationary-controller sensor noise from the visible sticker transform.
		return Quaternion.IDENTITY # Keeps the inspected sticker visually stable while the controller rests.
	if delta_angle > MAX_SAMPLE_DELTA_RADIANS: # Detects discontinuities caused by reconnects, Steam Input recalibration, or invalid one-frame sensor jumps.
		_has_reference_orientation = false # Re-establishes neutral orientation on the following valid sample instead of applying the implausible jump.
		return Quaternion.IDENTITY # Protects inspection from sudden large rotations outside deliberate physical motion.
	_motion_active = true # Marks this sample as genuine gyro motion for input-mode presentation and diagnostics.
	return _steam_delta_to_godot(steam_delta) # Converts Steam's controller coordinate basis into the Godot inspection world's right/up/back basis.

func _ensure_input_initialized() -> bool: # Lazily initializes Steam Input only when sticker inspection actually needs motion sensors.
	if _input_initialized: # Reuses the already initialized Steam Input interface across every later inspection.
		return true # Avoids redundant native initialization calls after the first successful session.
	if not SteamManager.is_available(): # Requires the existing authoritative Steamworks client session before initializing its Input interface.
		return false # Keeps non-Steam/editor fallback behavior completely functional.
	if not Steam.has_method(&"inputInit") or not Steam.has_method(&"getMotionData") or not Steam.has_method(&"getConnectedControllers"): # Verifies the installed GodotSteam build exposes the required Steam Input bridge.
		return false # Avoids runtime method errors on incompatible addon builds.
	var initialized: Variant = Steam.call(&"inputInit") # Initializes ISteamInput through GodotSteam using its current no-argument/default configuration.
	_input_initialized = bool(initialized) # Caches the actual GodotSteam initialization result rather than assuming Steam API availability implies Input availability.
	return _input_initialized # Reports whether motion polling may proceed safely.

func _run_input_frame() -> void: # Synchronizes Steam Input state immediately before motion reads when the installed GodotSteam build exposes the low-latency call.
	if _input_initialized and Steam.has_method(&"runFrame"): # Keeps compatibility with addon builds that rely only on SteamAPI callback pumping.
		Steam.call(&"runFrame") # Requests the latest physical controller state; Valve documents this as the lowest-latency path before reads.

func _discover_motion_controller() -> bool: # Chooses a usable gyro device, preferring Valve hardware while supporting hot-plugged Steam Input motion controllers.
	if not _input_initialized: # Rejects discovery before Steam Input has a live interface.
		return false # Leaves the session waiting for initialization.
	var candidates: Array[int] = [] # Stores unique controller handles in preferred gamepad-slot order followed by remaining Steam Input devices.
	if Steam.has_method(&"getControllerForGamepadIndex"): # Uses Steam's gamepad-emulation mapping first so the primary actively used controller wins when possible.
		for gamepad_index: int in range(GAMEPAD_INDEX_COUNT): # Checks the standard four emulated gamepad slots in player order.
			_add_candidate(candidates, int(Steam.call(&"getControllerForGamepadIndex", gamepad_index))) # Adds each valid nonzero mapped handle exactly once.
	var connected_value: Variant = Steam.call(&"getConnectedControllers") # Enumerates every remaining Steam Input controller so Deck/native Steam Controller handles are never missed.
	if connected_value is Array: # Handles GodotSteam's ordinary controller-handle array representation.
		for handle_value: Variant in connected_value as Array: # Visits each returned Steam Input handle once.
			_add_candidate(candidates, int(handle_value)) # Normalizes integer Variants and suppresses duplicates from gamepad-slot discovery.
	elif connected_value is PackedInt64Array: # Supports packed-handle return shapes without binding this helper to one GodotSteam implementation detail.
		for packed_handle: int in connected_value as PackedInt64Array: # Visits every packed 64-bit input handle.
			_add_candidate(candidates, packed_handle) # Adds the handle through the same validity and duplicate guard.
	if candidates.is_empty(): # Handles no connected Steam Input devices without generating warnings every frame.
		return false # Leaves hot-plug discovery active for later samples in the same inspection.
	var best_handle: int = 0 # Stores the strongest usable candidate after validating actual motion data.
	var best_type: int = 0 # Stores the corresponding Steam Input hardware classification for labels and preference ranking.
	var best_priority: int = 999 # Starts above every supported candidate priority so the first valid motion device can win.
	for candidate: int in candidates: # Validates real motion capability instead of assuming a controller type always contains a gyro.
		var motion_data: Dictionary = _get_motion_data(candidate) # Reads one current motion struct from this potential controller.
		if not _motion_data_has_valid_orientation(motion_data): # Rejects zero-filled or malformed motion data from devices without a usable gyro.
			continue # Checks the next connected Steam Input handle without changing session state.
		var input_type: int = _get_input_type(candidate) # Reads hardware classification only after proving the candidate exposes valid motion.
		var priority: int = _device_priority(input_type) # Prefers Deck/new Valve hardware, then original Steam Controller, then other gyro-capable Steam Input devices.
		if priority < best_priority: # Replaces the current candidate only when the new device better matches the requested Valve gyro hardware.
			best_handle = candidate # Stores the preferred valid Steam Input handle.
			best_type = input_type # Stores its classification for concise inspection hints and diagnostics.
			best_priority = priority # Prevents lower-priority non-Valve devices from replacing a discovered Steam controller.
	if best_handle == 0: # Handles connected controllers that all lack valid motion sensors.
		return false # Leaves inspection on right-stick/mouse rotation until a gyro-capable controller appears.
	_controller_handle = best_handle # Commits the selected physical controller for frame-by-frame motion sampling.
	_controller_type = best_type # Commits matching hardware classification for labels and later diagnostics.
	_has_reference_orientation = false # Makes this newly selected controller's first sample establish neutral orientation.
	if OS.is_debug_build(): # Emits one concise development diagnostic without adding release-build console noise.
		print("Steam inspection gyro ready: handle=%d type=%d label=%s" % [_controller_handle, _controller_type, get_device_label()]) # Identifies which Steam Input device actually owns motion during testing.
	return true # Confirms that automatic inspection gyro rotation can begin after its neutral reference sample.

func _add_candidate(candidates: Array[int], handle: int) -> void: # Adds one valid Steam Input handle exactly once while preserving discovery priority order.
	if handle == 0 or candidates.has(handle): # Rejects Steam's invalid zero handle and duplicates returned through multiple enumeration paths.
		return # Leaves candidate ordering unchanged for invalid or already-seen devices.
	candidates.append(handle) # Preserves gamepad-slot priority before remaining connected-controller enumeration order.

func _get_motion_data(handle: int) -> Dictionary: # Reads one GodotSteam motion struct defensively through the runtime method boundary.
	if handle == 0 or not Steam.has_method(&"getMotionData"): # Rejects invalid handles and addon builds without motion-data support.
		return {} # Returns an empty structure that naturally fails orientation validation.
	var motion_value: Variant = Steam.call(&"getMotionData", handle) # Requests Steamworks InputMotionData_t through GodotSteam without compile-time dependence on extension method metadata.
	return motion_value as Dictionary if motion_value is Dictionary else {} # Preserves the raw dictionary only when the addon returned the expected structured data.

func _get_input_type(handle: int) -> int: # Reads Steam's hardware classification when available without making it a requirement for gyro support.
	if handle == 0 or not Steam.has_method(&"getInputTypeForHandle"): # Supports GodotSteam builds that expose motion data but omit hardware-type helpers.
		return 0 # Uses the generic Steam Input gyro label and lowest preference tier.
	return int(Steam.call(&"getInputTypeForHandle", handle)) # Returns the current Steamworks ESteamInputType integer unchanged.

func _device_priority(input_type: int) -> int: # Ranks connected motion devices so the requested Valve hardware wins automatically when multiple gyros are attached.
	if input_type == STEAM_INPUT_TYPE_STEAM_DECK_CONTROLLER: # Covers Steam Deck-class hardware and newer Valve controller hardware currently surfaced through this type.
		return 0 # Gives the current Valve motion-device class first priority.
	if input_type == STEAM_INPUT_TYPE_STEAM_CONTROLLER: # Recognizes the original Steam Controller independently from Deck-class hardware.
		return 1 # Gives original Steam Controller second priority ahead of unrelated gyro-capable devices.
	return 2 # Still permits other Steam Input gyro controllers as a harmless fallback when no Valve gyro is connected.

func _motion_data_has_valid_orientation(data: Dictionary) -> bool: # Distinguishes a real normalized sensor-fused quaternion from zero-filled unsupported motion data.
	if data.is_empty(): # Rejects missing motion structures immediately.
		return false # Prevents invalid dictionary field reads and quaternion construction.
	var x: float = _motion_field(data, "rotQuatX", "rot_quat_x") # Reads GodotSteam's established camelCase field while accepting snake_case compatibility aliases.
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

func _steam_delta_to_godot(steam_delta: Quaternion) -> Quaternion: # Converts Steam controller axes (right/forward/up) into Godot inspection axes (right/up/back) while preserving physical rotation magnitude.
	var axis_conversion: Quaternion = Quaternion(Vector3.RIGHT, -PI * 0.5) # Rotates Steam's positive-forward Y and positive-up Z basis into Godot's negative-forward Z and positive-up Y basis.
	return (axis_conversion * steam_delta * axis_conversion.inverse()).normalized() # Conjugates the incremental physical rotation into Godot coordinates without Euler-angle conversion or gimbal locking.
