extends Node # Reconciles durable Sticker-Shock achievement history with Steam without gameplay signal wiring.

const SAVE_PATH: String = "user://sticker_achievements.json" # Persists every locally earned achievement so offline play, later sales, and future catalogue growth cannot erase historical earning.
const SAVE_VERSION: int = 1 # Identifies the compact local achievement-history document format.
const RETRY_INTERVAL_SECONDS: float = 0.5 # Limits failed Steam achievement retries while the asynchronous user-stats cache becomes ready.
const BOOK_POLL_INTERVAL_SECONDS: float = 0.5 # Polls only the constant-time physical placement count so book milestones update without coupling persistence back to Steam.
const MAX_RETRY_ATTEMPTS: int = 10 # Bounds native retry work when Steamworks configuration is missing or stats remain unavailable.

var _economy: StickerEconomy # Retains authoritative owned-copy progression after normal game startup completes.
var _catalog: StickerCatalog # Retains the current authored sticker catalogue used for dynamically scaled achievement denominators.
var _book_state: StickerBookState # Retains persistent physical placements used for dynamically scaled book milestones.
var _locally_earned: Dictionary[StringName, bool] = {} # Stores permanent local earning history independently from current mutable collection state.
var _pending_attempt_counts: Dictionary[StringName, int] = {} # Stores Steam achievements waiting for successful stats-cache mutation and persistence.
var _completed_session: Dictionary[StringName, bool] = {} # Prevents already confirmed Steam achievements from being queried or stored repeatedly during this process lifetime.
var _exhausted_session: Dictionary[StringName, bool] = {} # Prevents a bad dashboard definition from restarting another bounded retry loop every time progression changes this session.
var _retry_elapsed_seconds: float = 0.0 # Accumulates process time so pending native calls run only at the controlled retry cadence.
var _book_poll_elapsed_seconds: float = 0.0 # Accumulates process time between cheap physical placement-count comparisons.
var _last_book_placement_count: int = -1 # Stores the last observed count so a full catalogue evaluation runs only when book contents actually change.

func _ready() -> void: # Restores permanent local earning history and requests Steam stats after SteamManager initializes the base-app session.
	process_mode = Node.PROCESS_MODE_ALWAYS # Keeps local earning and pending Steam synchronization alive while gameplay is paused or switching physical worlds.
	set_process(false) # Avoids per-frame work until models are configured or an early first-sticker Steam retry requires it.
	_load_local_state() # Restores achievements earned in earlier online or offline sessions before gameplay models finish startup.
	if SteamManager.is_available(): # Requests the local user's stats only when the base launcher Steam session initialized successfully.
		_debug_print("requesting user stats for steam_id=%d" % SteamManager.get_steam_id()) # Confirms the asynchronous stats request during editor/debug testing.
		Steam.requestUserStats(SteamManager.get_steam_id()) # Starts the user-stats load required before achievement reads and writes can be relied upon.
	else: # Distinguishes a deliberately standalone run from later achievement-specific failures.
		_debug_print("Steam unavailable during achievement startup") # Leaves permanent local earning active while skipping native Steam work.

func configure(economy: StickerEconomy, catalog: StickerCatalog, book_state: StickerBookState) -> void: # Binds authoritative progression models after current content and saves have completed startup initialization.
	_economy = economy # Retains duplicate-aware ownership state for collection, rarity, pack, and finish achievements.
	_catalog = catalog # Retains the live catalogue so every amount-based denominator follows future sticker additions automatically.
	_book_state = book_state # Retains physical placement state for book-filing achievements.
	_last_book_placement_count = _book_state.get_placement_count() if _book_state != null else -1 # Seeds the constant-time book change detector from restored persistence.
	_book_poll_elapsed_seconds = 0.0 # Starts a fresh polling interval after authoritative model wiring completes.
	_queue_locally_earned() # Reconciles every achievement previously earned while Steam was unavailable or before the current process started.
	sync_progress() # Evaluates current persistent progression so existing saves receive newly introduced achievements retroactively where their state proves the condition.
	set_process(true) # Keeps cheap book-placement change detection active even offline so physical filing achievements are permanently recorded when earned.

func sync_first_sticker(total_owned_count: int) -> void: # Preserves the existing central economy hook while the generic manager owns persistence and Steam synchronization.
	if total_owned_count <= 0: # Requires at least one actual collected physical copy before earning the original achievement.
		return # Leaves local and Steam state untouched for a genuinely empty collection.
	_earn_achievement(StickerAchievementRules.FIRST_STICKER) # Permanently records and synchronizes the first-copy milestone through the generic path.

func sync_progress() -> void: # Re-evaluates all state-derived rules and permanently records every condition satisfied at this moment.
	if _economy == null or _catalog == null or _book_state == null: # Rejects calls before the game controller has supplied every authoritative model.
		return # Leaves durable achievement state unchanged until startup configuration completes.
	_last_book_placement_count = _book_state.get_placement_count() # Synchronizes the cheap detector whenever a full rule evaluation is already being performed.
	var earned_api_names: Array[StringName] = StickerAchievementRules.evaluate_progress(_economy, _catalog, _book_state) # Calculates current conditions without crossing the Steam extension boundary.
	_debug_print("sync state-derived achievements satisfied=%d catalogue=%d" % [earned_api_names.size(), _catalog.get_sticker_count()]) # Exposes compact reconciliation context in debug builds.
	for api_name: StringName in earned_api_names: # Visits each condition currently proven by authoritative progression.
		_earn_achievement(api_name) # Makes the achievement permanent locally before attempting idempotent Steam synchronization.

func report_pack_opened() -> void: # Permanently records one successfully completed sticker-pack transaction.
	_earn_achievement(StickerAchievementRules.FIRST_PACK) # Keeps first-pack earning valid even if every pack sticker is later sold or removed from future content.

func report_market_sale() -> void: # Permanently records the first successful collector-exchange sale.
	_earn_achievement(StickerAchievementRules.FIRST_MARKET_SALE) # Preserves historical sale proof because current inventory cannot reconstruct it later.

func _earn_achievement(api_name: StringName) -> void: # Permanently records one validated local achievement before attempting Steam so offline earning cannot be lost.
	if not StickerAchievementRules.is_valid_api_name(api_name): # Rejects arbitrary or stale identifiers before persistence or native calls.
		return # Leaves controlled local history and Steam untouched for invalid callers.
	if not _locally_earned.has(api_name): # Writes the small local save only when this achievement is genuinely newly earned on this progression profile.
		_locally_earned[api_name] = true # Makes earning permanent independently from later mutable collection state or content changes.
		_save_local_state() # Flushes immediately so quitting, going offline, or selling the qualifying sticker cannot lose the achievement.
		_debug_print("earned locally api=%s" % String(api_name)) # Makes the exact moment of permanent local earning visible during debug testing.
	_queue_achievement(api_name) # Reconciles the locally earned condition with Steam idempotently when a live session is available.

func _queue_locally_earned() -> void: # Queues every permanent local achievement restored from user storage for Steam reconciliation.
	for api_name: StringName in _locally_earned: # Visits only validated known API names loaded from disk.
		_queue_achievement(api_name) # Attempts each independently so one missing dashboard definition cannot block the rest.

func _queue_achievement(api_name: StringName) -> void: # Adds one locally earned achievement to the generic bounded Steam retry pipeline exactly once per session state.
	if api_name.is_empty() or _completed_session.has(api_name) or _pending_attempt_counts.has(api_name) or _exhausted_session.has(api_name): # Rejects invalid, already confirmed, already queued, or session-exhausted work.
		return # Avoids duplicate native calls when several gameplay paths synchronize the same achievement.
	_debug_print("queued api=%s steam_available=%s" % [String(api_name), str(SteamManager.is_available())]) # Exposes the exact earned API name before native synchronization begins.
	if not SteamManager.is_available(): # Keeps the achievement safely local when Steam is intentionally unavailable for this process.
		return # Relies on the permanent local save to retry automatically on a future Steam-enabled launch.
	_pending_attempt_counts[api_name] = 0 # Starts a fresh bounded attempt counter only when a native Steam session can actually service it.
	if _attempt_achievement(api_name): # Tries immediately so normal gameplay receives the native achievement notification without avoidable delay.
		return # Leaves no pending retry when the first native transaction succeeds.
	if _pending_attempt_counts.has(api_name): # Enables retries only when the immediate attempt failed without exhausting its bounded attempt budget.
		_retry_elapsed_seconds = 0.0 # Starts a clean retry interval after the immediate native call.
		set_process(true) # Activates the pending queue; configured sessions also use this process loop for cheap book change detection.

func _process(delta: float) -> void: # Detects physical-book changes and retries pending Steam work without gameplay signal wiring.
	if _book_state != null: # Enables local book-achievement earning only after authoritative models have been configured.
		_book_poll_elapsed_seconds += delta # Accumulates pause-independent time toward the next constant-time placement-count comparison.
		if _book_poll_elapsed_seconds >= BOOK_POLL_INTERVAL_SECONDS: # Throttles even the cheap count read to two checks per second.
			_book_poll_elapsed_seconds = 0.0 # Restarts the book change interval before reading current persistence state.
			var current_placement_count: int = _book_state.get_placement_count() # Reads only the O(1) array size without allocating a placement snapshot.
			if current_placement_count != _last_book_placement_count: # Runs the full scalable rule scan only when a sticker was physically added or removed.
				_last_book_placement_count = current_placement_count # Updates the detector before synchronization performs its own stable count read.
				sync_progress() # Permanently records newly satisfied filing milestones even when Steam itself is offline.
	if _pending_attempt_counts.is_empty(): # Skips retry timing when every locally earned achievement is already synchronized or Steam was unavailable when it was earned.
		if _book_state == null: # Detects the pre-configuration case where processing was enabled only for an early Steam retry that has now finished.
			set_process(false) # Returns to idle until configuration or another early achievement needs work.
		return # Keeps configured sessions alive only for cheap physical-book change detection.
	if not SteamManager.is_available(): # Protects against a Steam session disappearing while locally earned history remains valid.
		return # Keeps book polling active and leaves native work for a later Steam-enabled launch.
	_retry_elapsed_seconds += delta # Accumulates pause-independent process time toward the next native retry pass.
	if _retry_elapsed_seconds < RETRY_INTERVAL_SECONDS: # Waits for the configured interval instead of crossing the extension boundary every frame.
		return # Defers the queue without mutating attempt counters.
	_retry_elapsed_seconds = 0.0 # Restarts the interval immediately before the next retry batch.
	var queued_api_names: Array[StringName] = [] # Copies keys because successful or exhausted attempts erase entries from the authoritative pending dictionary.
	for api_name: StringName in _pending_attempt_counts: # Visits each currently pending earned achievement exactly once for this retry pass.
		queued_api_names.append(api_name) # Preserves a stable iteration list while the pending dictionary can change below.
	for api_name: StringName in queued_api_names: # Attempts each achievement independently so one bad Steamworks definition cannot block unrelated achievements.
		_attempt_achievement(api_name) # Updates per-achievement attempt state and removes successful or exhausted entries.

func _attempt_achievement(api_name: StringName) -> bool: # Performs one guarded Steam unlock/store transaction for an already-earned achievement.
	if not _pending_attempt_counts.has(api_name) or not SteamManager.is_available(): # Rejects stale attempts and calls without a live Steam API session.
		return false # Reports that no native transaction completed.
	var attempt_number: int = _pending_attempt_counts[api_name] + 1 # Advances only this achievement's bounded retry counter.
	_pending_attempt_counts[api_name] = attempt_number # Persists the increment before crossing into Steamworks for deterministic diagnostics.
	_debug_print("attempt api=%s number=%d" % [String(api_name), attempt_number]) # Correlates generic retry state with SteamProgress's detailed native-call diagnostics.
	if SteamProgress.unlock_achievement(api_name): # Uses the centralized helper for already-unlocked detection, setAchievement, and storeStats.
		_pending_attempt_counts.erase(api_name) # Removes completed work immediately so later progression syncs stay quiet.
		_completed_session[api_name] = true # Caches confirmation for the remainder of this process lifetime.
		_debug_print("attempt succeeded api=%s number=%d" % [String(api_name), attempt_number]) # Confirms successful or already-achieved Steam state even when editor overlay toasts are unavailable.
		return true # Reports that this permanently earned achievement is synchronized with Steam.
	_debug_print("attempt failed api=%s number=%d" % [String(api_name), attempt_number]) # Makes transient stats readiness or dashboard failures explicit in debug output.
	if attempt_number >= MAX_RETRY_ATTEMPTS: # Detects a persistent Steamworks configuration or stats-cache failure after the bounded retry window.
		_pending_attempt_counts.erase(api_name) # Stops native traffic for this achievement for the rest of the current session.
		_exhausted_session[api_name] = true # Prevents subsequent gameplay syncs from immediately starting another ten-attempt loop.
		push_warning("Steam achievement %s could not be stored after %d attempts" % [String(api_name), MAX_RETRY_ATTEMPTS]) # Reports the exact API name for Steamworks dashboard diagnosis.
	return false # Reports that this attempt did not confirm the earned achievement in Steam.

func _load_local_state() -> void: # Restores permanent local achievement history from the compact user-data document.
	_locally_earned.clear() # Starts from deterministic empty history before any filesystem or parsing failure can occur.
	if not FileAccess.file_exists(SAVE_PATH): # Treats absence as a normal first run before the generic achievement system has stored anything.
		return # Leaves the empty local set without creating unnecessary storage at startup.
	var save_file: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.READ) # Opens the small achievement-history document for one sequential read.
	if save_file == null: # Detects an operating-system or filesystem failure while retaining safe empty state.
		push_error("could not read sticker achievement save") # Reports persistence failure without blocking gameplay or newly earned achievements.
		return # Continues with empty local history for this session.
	var parsed_data: Variant = JSON.parse_string(save_file.get_as_text()) # Parses the complete compact JSON document into Godot variants.
	if parsed_data is not Dictionary: # Rejects malformed content that does not contain the expected object root.
		push_warning("sticker achievement save was invalid and has been reset") # Reports recovery during development without terminating gameplay.
		_save_local_state() # Replaces malformed data with the current valid empty schema.
		return # Keeps deterministic empty local history.
	var save_data: Dictionary = parsed_data # Narrows the validated JSON root for controlled field access.
	var saved_achievements: Variant = save_data.get("earned", []) # Retrieves the stored API-name list while remaining tolerant of future document fields.
	if saved_achievements is not Array: # Rejects malformed achievement collections independently from the valid root object.
		return # Leaves the local set empty rather than trusting incompatible data.
	for saved_achievement: Variant in saved_achievements: # Visits each serialized API name once.
		var api_name: StringName = StringName(str(saved_achievement)) # Converts the JSON string into the same compact identifier type used by runtime rules.
		if StickerAchievementRules.is_valid_api_name(api_name): # Restores only currently recognized achievements so edited or stale keys cannot cause arbitrary Steam calls.
			_locally_earned[api_name] = true # Reconstructs permanent local earning history for startup Steam reconciliation.

func _save_local_state() -> void: # Persists every permanently earned achievement in a stable compact JSON document.
	var save_file: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.WRITE) # Opens the achievement-history file for replacement with authoritative current state.
	if save_file == null: # Detects filesystem failure before serialization.
		push_error("could not write sticker achievement save") # Reports persistence failure without interrupting the gameplay action that just earned an achievement.
		return # Leaves valid in-memory earning state active for this session.
	var earned_names: Array[String] = [] # Builds a stable JSON-compatible list from internal StringName keys.
	for api_name: StringName in _locally_earned: # Copies every validated locally earned achievement exactly once.
		earned_names.append(String(api_name)) # Serializes the exact Steamworks API name for straightforward migration and debugging.
	earned_names.sort() # Stabilizes file order so diffs and manual diagnostics remain deterministic.
	var save_data: Dictionary = {"version": SAVE_VERSION, "earned": earned_names} # Stores the schema version and complete permanent local achievement set.
	save_file.store_string(JSON.stringify(save_data, "\t")) # Writes readable JSON because the achievement history is tiny and occasionally useful during development.

func _debug_print(message: String) -> void: # Emits achievement-manager diagnostics only in editor and debug builds.
	if not OS.is_debug_build(): # Keeps release sessions free from development-only achievement logging.
		return # Skips console output outside debug testing.
	print("SteamAchievements: %s" % message) # Prefixes every manager message so the complete achievement pipeline is easy to isolate in Godot Output.