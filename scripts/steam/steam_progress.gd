class_name SteamProgress # Provides achievement and stat operations without coupling Steamworks persistence into gameplay systems.
extends RefCounted # Keeps the helper allocation-free for callers that use its static API.

static func unlock_achievement(api_name: StringName) -> bool: # Unlocks one Steamworks achievement and immediately commits the change.
	if not SteamManager.is_available() or api_name.is_empty(): # Rejects invalid requests before touching the Steam API.
		return false # Reports that no achievement state was changed.
	if not bool(Steam.setAchievement(String(api_name))): # Updates the achievement in Steam's local stats state first.
		return false # Reports that Steamworks rejected the configured API name or current stats state.
	return bool(Steam.storeStats()) # Commits the unlocked achievement so the Steam backend and overlay receive it promptly.

static func clear_achievement_for_testing(api_name: StringName) -> bool: # Clears one achievement only in debug builds for repeatable local Steamworks testing.
	if not OS.is_debug_build(): # Prevents release gameplay from exposing achievement-reset behavior.
		return false # Reports that release builds may not clear achievements.
	if not SteamManager.is_available() or api_name.is_empty(): # Rejects reset attempts without a live Steam API or valid achievement name.
		return false # Reports that no achievement state was changed.
	if not bool(Steam.clearAchievement(String(api_name))): # Clears the local Steam achievement state using the authored API name.
		return false # Reports that Steamworks rejected the reset request.
	return bool(Steam.storeStats()) # Commits the debug reset so repeated achievement testing starts from a known server state.

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
