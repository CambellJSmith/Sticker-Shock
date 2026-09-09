class_name SteamAchievements # Owns Sticker-Shock achievement definitions and retries Steam unlocks without gameplay signal wiring.
extends Node # Runs as an autoload so pending achievement work can survive scene changes and wait for Steam stats readiness.

const FIRST_STICKER: StringName = &"STICKER_SHOCK_FIRST_STICKER" # Identifies the Steamworks achievement awarded when the player owns their first sticker copy.
const RETRY_INTERVAL_SECONDS: float = 0.5 # Limits failed Steam achievement retries while the asynchronous user-stats cache becomes ready.

var _first_sticker_pending: bool = false # Stores whether gameplay has satisfied the first-sticker condition but Steam has not yet accepted the unlock.
var _retry_elapsed_seconds: float = 0.0 # Accumulates process time so failed unlock attempts do not cross the Steam extension boundary every frame.

func _ready() -> void: # Prepares asynchronous achievement persistence after SteamManager has initialized the base-app Steam session.
	process_mode = Node.PROCESS_MODE_ALWAYS # Keeps pending Steam progress available while gameplay is paused or switching physical worlds.
	set_process(false) # Avoids per-frame work until an earned achievement actually needs a retry.
	if SteamManager.is_available(): # Requests the local user's Steam stats only when the base Steam session initialized successfully.
		Steam.requestUserStats(SteamManager.get_steam_id()) # Starts the asynchronous user-stats load required before Steam can reliably accept achievement writes.

func _process(delta: float) -> void: # Retries an earned achievement until Steam's asynchronous stats state accepts and stores it.
	if not _first_sticker_pending or not SteamManager.is_available(): # Stops retry work when nothing is earned or the current process has no live Steam session.
		set_process(false) # Removes the tracker from future process frames until another valid report re-enables it.
		return # Leaves achievement state pending locally without touching an unavailable Steam API.
	_retry_elapsed_seconds += delta # Accumulates pause-independent process time toward the bounded retry cadence.
	if _retry_elapsed_seconds < RETRY_INTERVAL_SECONDS: # Waits until the configured interval has elapsed before another native call.
		return # Avoids hammering Steamworks while the user-stats request is still completing.
	_retry_elapsed_seconds = 0.0 # Restarts the retry interval immediately before attempting another unlock.
	_attempt_first_sticker_unlock() # Tries to commit the already-earned achievement through the shared Steam progress helper.

func sync_first_sticker(total_owned_count: int) -> void: # Reconciles persisted or newly granted ownership with the first-sticker Steam achievement.
	if total_owned_count <= 0: # Requires at least one actual collected sticker copy before earning the achievement.
		return # Leaves the achievement untouched for a genuinely empty collection.
	_first_sticker_pending = true # Records the earned condition independently from whether Steam stats are ready this exact frame.
	_retry_elapsed_seconds = 0.0 # Allows the first unlock attempt to happen immediately instead of waiting through the retry interval.
	if not SteamManager.is_available(): # Keeps standalone development harmless when Steam initialization is intentionally optional.
		return # Leaves no active retry loop because Steam cannot become available later in the same initialized process.
	if _attempt_first_sticker_unlock(): # Attempts the unlock synchronously so normal gameplay gets the native toast without avoidable delay.
		return # Leaves processing disabled after a successful immediate commit.
	set_process(true) # Enables bounded retries because Steam is live but its asynchronous stats cache is not ready yet.

func _attempt_first_sticker_unlock() -> bool: # Attempts one idempotent Steam unlock/store transaction for the first-sticker achievement.
	if not _first_sticker_pending or not SteamManager.is_available(): # Rejects calls without an earned condition or a live Steam API session.
		return false # Reports that no Steam transaction completed.
	if not SteamProgress.unlock_achievement(FIRST_STICKER): # Uses the existing guarded helper so setAchievement and storeStats remain centralized.
		return false # Keeps the earned achievement pending for a later stats-ready retry.
	_first_sticker_pending = false # Clears local pending state only after Steam accepted and stored the achievement.
	set_process(false) # Stops all retry work immediately after the successful backend commit.
	return true # Reports that the achievement is now committed through Steamworks.
