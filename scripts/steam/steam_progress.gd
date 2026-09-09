class_name SteamProgress # Provides achievement and stat operations without coupling Steamworks persistence into gameplay systems.
extends RefCounted # Keeps the helper allocation-free for callers that use its static API.

static func unlock_achievement(api_name: StringName) -> bool: # Unlocks one Steamworks achievement and immediately commits the change.
	if not SteamManager.is_available() or api_name.is_empty(): # Rejects invalid requests before touching the Steam API.
		return false # Reports that no achievement state was changed.
	var api_name_string: String = String(api_name) # Converts the authored StringName once for the native Steamworks calls and debug output.
	_debug_print_achievement_state(api_name_string, "before setAchievement") # Captures whether Steam can read the published API name and whether it is already unlocked before mutation.
	var set_result: bool = bool(Steam.setAchievement(api_name_string)) # Updates the achievement in Steam's local stats state first.
	_debug_print_achievement_result(api_name_string, "setAchievement", set_result) # Reports the native set result in debug builds so rejected API names or unloaded stats are visible immediately.
	if not set_result: # Stops before persistence when Steamworks rejected the local achievement mutation.
		return false # Reports that Steamworks rejected the configured API name or current stats state.
	_debug_print_achievement_state(api_name_string, "after setAchievement") # Verifies whether Steam's local cached achievement state changed before StoreStats runs.
	var store_result: bool = bool(Steam.storeStats()) # Commits the unlocked achievement so the Steam backend and overlay receive it promptly.
	_debug_print_achievement_result(api_name_string, "storeStats", store_result) # Reports whether Steam accepted the persistence request in debug builds.
	_debug_print_achievement_state(api_name_string, "after storeStats") # Reads the cached state again so a silent successful unlock is distinguishable from an overlay-notification problem.
	return store_result # Reports whether Steam accepted the explicit persistence request.

static func clear_achievement_for_testing(api_name: StringName) -> bool: # Clears one achievement only in debug builds for repeatable local Steamworks testing.
	if not OS.is_debug_build(): # Prevents release gameplay from exposing achievement-reset behavior.
		return false # Reports that release builds may not clear achievements.
	if not SteamManager.is_available() or api_name.is_empty(): # Rejects reset attempts without a live Steam API or valid achievement name.
		return false # Reports that no achievement state was changed.
	var api_name_string: String = String(api_name) # Converts the authored StringName once for native calls and diagnostics.
	_debug_print_achievement_state(api_name_string, "before clearAchievement") # Records the starting state so repeated tests confirm the achievement was actually unlocked before reset.
	var clear_result: bool = bool(Steam.clearAchievement(api_name_string)) # Clears the local Steam achievement state using the authored API name.
	_debug_print_achievement_result(api_name_string, "clearAchievement", clear_result) # Reports whether Steam accepted the local reset in the debug build.
	if not clear_result: # Stops before persistence when Steamworks rejected the reset request.
		return false # Reports that Steamworks rejected the reset request.
	_debug_print_achievement_state(api_name_string, "after clearAchievement") # Confirms the local cached state changed before committing the reset.
	var store_result: bool = bool(Steam.storeStats()) # Commits the debug reset so repeated achievement testing starts from a known server state.
	_debug_print_achievement_result(api_name_string, "storeStats after clearAchievement", store_result) # Reports whether the reset persistence request was accepted.
	_debug_print_achievement_state(api_name_string, "after clear storeStats") # Confirms the cached state after the reset commit for end-to-end test diagnostics.
	return store_result # Reports whether Steam accepted the explicit reset persistence request.

static func show_achievement_progress(api_name: StringName, current_progress: int, maximum_progress: int) -> bool: # Shows Steam's native progress toast for a progress-based achievement.
	if not SteamManager.is_available() or api_name.is_empty(): # Rejects progress presentation without a live Steam API or configured achievement name.
		return false # Reports that no progress notification was submitted.
	if maximum_progress <= 0 or current_progress < 0: # Rejects malformed progress ranges before crossing the extension boundary.
		return false # Reports that the supplied progress values were invalid.
	var clamped_progress: int = mini(current_progress, maximum_progress) # Keeps the displayed progress inside Steamworks' expected range.
	return bool(Steam.indicateAchievementProgress(String(api_name), clamped_progress, maximum_progress)) # Requests the native Steam overlay progress notification without implicitly unlocking the achievement.

static func set_stat_int(api_name: StringName, value: int) -> bool: # Updates one integer Steam stat in local Steamworks state without forcing an immediate network commit.
	if not SteamManager.is_available() or api_name.is_empty(): # Rejects stat writes without a live Steam API or configured stat name.
		return false # Reports that no stat value was changed.
	return bool(Steam.setStatInt(String(api_name), value)) # Returns Steamworks' validation result for the integer stat write.

static func set_stat_float(api_name: StringName, value: float) -> bool: # Updates one floating-point Steam stat in local Steamworks state without forcing an immediate network commit.
	if not SteamManager.is_available() or api_name.is_empty(): # Rejects stat writes without a live Steam API or configured stat name.
		return false # Reports that no stat value was changed.
	return bool(Steam.setStatFloat(String(api_name), value)) # Returns Steamworks' validation result for the floating-point stat write.

static func get_stat_int(api_name: StringName) -> int: # Reads one integer Steam stat for the current user.
	if not SteamManager.is_available() or api_name.is_empty(): # Rejects stat reads without a live Steam API or configured stat name.
		return 0 # Returns the neutral integer fallback when Steam data is unavailable.
	return int(Steam.getStatInt(String(api_name))) # Returns the current integer value held by Steamworks for the authored stat.

static func get_stat_float(api_name: StringName) -> float: # Reads one floating-point Steam stat for the current user.
	if not SteamManager.is_available() or api_name.is_empty(): # Rejects stat reads without a live Steam API or configured stat name.
		return 0.0 # Returns the neutral floating-point fallback when Steam data is unavailable.
	return float(Steam.getStatFloat(String(api_name))) # Returns the current floating-point value held by Steamworks for the authored stat.

static func store_stats() -> bool: # Commits all pending Steam stat and achievement changes at a deliberate gameplay checkpoint.
	if not SteamManager.is_available(): # Rejects persistence requests without a live Steam API.
		return false # Reports that no backend store request was submitted.
	return bool(Steam.storeStats()) # Sends the current Steamworks stat snapshot to the backend in one explicit commit.

static func _debug_print_achievement_state(api_name: String, phase: String) -> void: # Reads and prints one achievement's raw GodotSteam state only while running a debug build.
	if not OS.is_debug_build(): # Keeps release builds free from diagnostic native reads and console output.
		return # Skips the diagnostic path entirely outside development builds.
	var state: Dictionary = Steam.getAchievement(api_name) # Preserves the raw GodotSteam dictionary so return flags and achieved state remain visible without assumptions about key naming.
	print("Steam achievement state: api=%s phase=%s state=%s" % [api_name, phase, str(state)]) # Emits one compact line that can be compared before and after each Steamworks mutation.

static func _debug_print_achievement_result(api_name: String, operation: String, result: bool) -> void: # Prints the boolean result of one native achievement operation only in debug builds.
	if not OS.is_debug_build(): # Keeps release builds free from development-only diagnostics.
		return # Skips console output outside development builds.
	print("Steam achievement operation: api=%s operation=%s result=%s" % [api_name, operation, str(result)]) # Exposes exactly which Steamworks call accepted or rejected the current achievement transaction.
