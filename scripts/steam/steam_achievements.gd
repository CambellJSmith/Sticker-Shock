extends Node # Reconciles Sticker-Shock progression and event history with Steam achievements without gameplay signal wiring.

const EVENT_SAVE_PATH: String = "user://sticker_achievement_events.json" # Persists non-reconstructible first-time gameplay events so offline sessions can reconcile them with Steam later.
const EVENT_SAVE_VERSION: int = 1 # Identifies the compact event-history document format used by the generic achievement manager.
const RETRY_INTERVAL_SECONDS: float = 0.5 # Limits failed Steam achievement retries while the asynchronous user-stats cache becomes ready.
const MAX_RETRY_ATTEMPTS: int = 10 # Bounds native retry work when Steamworks configuration is missing or stats remain unavailable.

var _economy: StickerEconomy # Retains authoritative owned-copy progression after the game controller completes model initialization.
var _catalog: StickerCatalog # Retains the current authored sticker catalogue used for dynamically scaled achievement denominators.
var _book_state: StickerBookState # Retains persistent physical placements used for book-filing milestones.
var _earned_events: Dictionary[StringName, bool] = {} # Stores locally earned event achievements that cannot always be inferred from current collection state.
var _pending_attempt_counts: Dictionary[StringName, int] = {} # Stores Steam achievements waiting for successful stats-cache mutation and persistence.
var _completed_session: Dictionary[StringName, bool] = {} # Prevents already confirmed Steam achievements from being queried or stored repeatedly during this process lifetime.
var _exhausted_session: Dictionary[StringName, bool] = {} # Prevents a bad dashboard definition from restarting another bounded retry loop every time progression changes this session.
var _retry_elapsed_seconds: float = 0.0 # Accumulates process time so pending native calls run only at the controlled retry cadence.

func _ready() -> void: # Loads durable event history and requests Steam stats after SteamManager has initialized the base-app session.
	process_mode = Node.PROCESS_MODE_ALWAYS # Keeps pending Steam synchronization alive while gameplay is paused or switching physical worlds.
	set_process(false) # Avoids per-frame work until at least one earned achievement needs a retry.
	_load_event_state() # Restores event achievements earned during previous online or offline sessions before gameplay models finish startup.
	if SteamManager.is_available(): # Requests the local user's stats only when the base launcher Steam session initialized successfully.
		_debug_print("requesting user stats for steam_id=%d" % SteamManager.get_steam_id()) # Confirms the asynchronous stats request during editor/debug testing.
		Steam.requestUserStats(SteamManager.get_steam_id()) # Starts the user-stats load required before achievement reads and writes can be relied upon.
	else: # Distinguishes a deliberately standalone run from later achievement-specific failures.
		_debug_print("Steam unavailable during achievement startup") # Leaves local event persistence active while skipping native Steam work.

func configure(economy: StickerEconomy, catalog: StickerCatalog, book_state: StickerBookState) -> void: # Binds authoritative progression models once normal game startup has rebuilt current authored content and loaded saves.
	_economy = economy # Retains duplicate-aware ownership state for collection and edition achievements.
	_catalog = catalog # Retains the live catalogue so all content-count milestones scale with future sticker additions.
	_book_state = book_state # Retains physical placement state for dynamically scaled book milestones.
	_queue_saved_events() # Reconciles durable first-time events that may have been earned while Steam was unavailable.
	sync_progress() # Reconciles every achievement whose condition can be reconstructed from current persistent game state.

func sync_progress() -> void: # Re-evaluates all state-derived achievements against the current catalogue and persistent progression.
	if _economy == null or _catalog == null or _book_state == null: # Rejects calls made before the game controller has supplied all authoritative models.
		return # Leaves achievement state untouched until startup configuration is complete.
	var earned_api_names: Array[StringName] = StickerAchievementRules.evaluate_progress(_economy, _catalog, _book_state) # Calculates satisfied rules without crossing the Steam extension boundary.
	_debug_print("sync state-derived achievements satisfied=%d catalogue=%d" % [earned_api_names.size(), _catalog.get_sticker_count()]) # Exposes compact reconciliation context in debug builds.
	for api_name: StringName in earned_api_names: # Queues each currently satisfied condition idempotently.
		_queue_achievement(api_name) # Deduplicates session-complete, pending, and exhausted achievements before any native call.

func report_pack_opened(was_free_pack: bool) -> void: # Records the first successful pack event plus the appropriate paid-or-free route for durable offline-safe reconciliation.
	_record_event(StickerAchievementRules.FIRST_PACK) # Records opening any complete pack regardless of payment route.
	if was_free_pack: # Distinguishes the cooldown/banked free-pack route from a paid transaction.
		_record_event(StickerAchievementRules.FIRST_FREE_PACK) # Records the first successfully claimed free sticker pack.
	else: # Handles a normal currency-paid pack purchase.
		_record_event(StickerAchievementRules.FIRST_PAID_PACK) # Records the first successfully purchased sticker pack.

func report_market_sale() -> void: # Records the first successful collector-exchange sale as an event that current inventory cannot reconstruct later.
	_record_event(StickerAchievementRules.FIRST_MARKET_SALE) # Persists and queues the market-debut achievement only after gameplay confirms an atomic sale succeeded.

func _record_event(api_name: StringName) -> void: # Persists one controlled event achievement before attempting Steam so offline or interrupted sessions cannot lose it.
	if not StickerAchievementRules.is_event_api_name(api_name): # Rejects arbitrary achievement names from being persisted through the event-history channel.
		return # Leaves the controlled local save unchanged for invalid callers.
	if not _earned_events.has(api_name): # Writes the small event file only when this first-time event is genuinely new locally.
		_earned_events[api_name] = true # Records the event before any asynchronous Steam interaction can fail.
		_save_event_state() # Flushes the earned event immediately so a quit or offline run remains recoverable.
		_debug_print("recorded event api=%s" % String(api_name)) # Makes first-time local event persistence visible in debug testing.
	_queue_achievement(api_name) # Attempts or schedules the corresponding Steam achievement even when the event was already recorded earlier.

func _queue_saved_events() -> void: # Queues every durable event condition restored from the local achievement-event save.
	for api_name: StringName in _earned_events: # Visits only validated known event API names loaded from disk.
		_queue_achievement(api_name) # Reconciles each event with Steam idempotently during startup configuration.

func _queue_achievement(api_name: StringName) -> void: # Adds one earned achievement to the generic bounded Steam retry pipeline exactly once per session state.
	if api_name.is_empty() or _completed_session.has(api_name) or _pending_attempt_counts.has(api_name) or _exhausted_session.has(api_name): # Rejects invalid, already confirmed, already queued, or session-exhausted work.
		return # Avoids duplicate native calls when several rules become true during the same progression change.
	_pending_attempt_counts[api_name] = 0 # Starts a fresh bounded attempt counter for this earned achievement.
	_debug_print("queued api=%s steam_available=%s" % [String(api_name), str(SteamManager.is_available())]) # Exposes the exact earned API name before native synchronization begins.
	if not SteamManager.is_available(): # Keeps earned state local when Steam is intentionally unavailable for this process.
		return # Leaves event conditions durable and state-derived conditions reconstructible on a future Steam-enabled launch.
	if _attempt_achievement(api_name): # Tries immediately so normal gameplay receives an achievement toast without an avoidable half-second delay.
		return # Leaves processing disabled when the first native transaction succeeds.
	if _pending_attempt_counts.has(api_name): # Enables retries only when the immediate attempt failed without exhausting its bounded attempt budget.
		_retry_elapsed_seconds = 0.0 # Starts a clean retry interval after the immediate native call.
		set_process(true) # Activates the generic pending queue until all earned achievements succeed or exhaust this session.

func _process(delta: float) -> void: # Retries every pending earned achievement at a controlled cadence while Steam's user-stats cache becomes ready.
	if _pending_attempt_counts.is_empty() or not SteamManager.is_available(): # Stops process work when nothing remains or the current session has no live Steam API.
		set_process(false) # Removes the autoload from future process frames until another earned achievement is queued.
		return # Leaves durable/reconstructible conditions available for a later Steam-enabled launch when necessary.
	_retry_elapsed_seconds += delta # Accumulates pause-independent process time toward the next native retry pass.
	if _retry_elapsed_seconds < RETRY_INTERVAL_SECONDS: # Waits for the configured interval instead of crossing the extension boundary every frame.
		return # Defers the queue without mutating attempt counters.
	_retry_elapsed_seconds = 0.0 # Restarts the interval immediately before the next retry batch.
	var queued_api_names: Array[StringName] = [] # Copies keys because successful or exhausted attempts erase entries from the authoritative pending dictionary.
	for api_name: StringName in _pending_attempt_counts: # Visits each currently pending earned achievement exactly once for this retry pass.
		queued_api_names.append(api_name) # Preserves a stable iteration list while the pending dictionary can change below.
	for api_name: StringName in queued_api_names: # Attempts each achievement independently so one bad Steamworks definition cannot block unrelated achievements.
		_attempt_achievement(api_name) # Updates per-achievement attempt state and removes successful or exhausted entries.
	if _pending_attempt_counts.is_empty(): # Detects completion of the entire retry batch after all mutations are finished.
		set_process(false) # Stops per-frame work until another newly earned achievement appears.

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
		return true # Reports that this earned achievement is synchronized with Steam.
	_debug_print("attempt failed api=%s number=%d" % [String(api_name), attempt_number]) # Makes transient stats readiness or dashboard failures explicit in debug output.
	if attempt_number >= MAX_RETRY_ATTEMPTS: # Detects a persistent Steamworks configuration or stats-cache failure after the bounded retry window.
		_pending_attempt_counts.erase(api_name) # Stops native traffic for this achievement for the rest of the current session.
		_exhausted_session[api_name] = true # Prevents subsequent gameplay syncs from immediately starting another ten-attempt loop.
		push_warning("Steam achievement %s could not be stored after %d attempts" % [String(api_name), MAX_RETRY_ATTEMPTS]) # Reports the exact API name for Steamworks dashboard diagnosis.
	return false # Reports that this attempt did not confirm the earned achievement in Steam.

func _load_event_state() -> void: # Restores locally earned non-reconstructible achievement events from the compact user-data document.
	_earned_events.clear() # Starts from deterministic empty history before any filesystem or parsing failure can occur.
	if not FileAccess.file_exists(EVENT_SAVE_PATH): # Treats absence as a normal first run before any event achievement has been earned.
		return # Leaves the empty event set without creating unnecessary storage at startup.
	var save_file: FileAccess = FileAccess.open(EVENT_SAVE_PATH, FileAccess.READ) # Opens the small event-history document for one sequential read.
	if save_file == null: # Detects an operating-system or filesystem failure while retaining safe empty state.
		push_error("could not read sticker achievement event save") # Reports persistence failure without blocking gameplay or state-derived achievements.
		return # Continues with empty local event history for this session.
	var parsed_data: Variant = JSON.parse_string(save_file.get_as_text()) # Parses the complete compact JSON document into Godot variants.
	if parsed_data is not Dictionary: # Rejects malformed content that does not contain the expected object root.
		push_warning("sticker achievement event save was invalid and has been reset") # Reports recovery during development without terminating gameplay.
		_save_event_state() # Replaces malformed data with the current valid empty schema.
		return # Keeps deterministic empty event history.
	var save_data: Dictionary = parsed_data # Narrows the validated JSON root for controlled field access.
	var saved_events: Variant = save_data.get("earned_events", []) # Retrieves the stored API-name list while remaining tolerant of future document fields.
	if saved_events is not Array: # Rejects malformed event collections independently from the valid root object.
		return # Leaves the local event set empty rather than trusting incompatible data.
	for saved_event: Variant in saved_events: # Visits each serialized API name once.
		var api_name: StringName = StringName(str(saved_event)) # Converts the JSON string into the same compact identifier type used by runtime rules.
		if StickerAchievementRules.is_event_api_name(api_name): # Restores only currently recognized event achievements so stale future/removed keys cannot cause arbitrary Steam calls.
			_earned_events[api_name] = true # Reconstructs the durable earned-event set for startup reconciliation.

func _save_event_state() -> void: # Persists every earned non-reconstructible event in a stable compact JSON document.
	var save_file: FileAccess = FileAccess.open(EVENT_SAVE_PATH, FileAccess.WRITE) # Opens the event-history file for replacement with authoritative current state.
	if save_file == null: # Detects filesystem failure before serialization.
		push_error("could not write sticker achievement event save") # Reports persistence failure without interrupting the gameplay event that was just completed.
		return # Leaves valid in-memory event state active for this session.
	var earned_event_names: Array[String] = [] # Builds a stable JSON-compatible list from internal StringName keys.
	for api_name: StringName in _earned_events: # Copies every validated locally earned event exactly once.
		earned_event_names.append(String(api_name)) # Serializes the exact Steamworks API name for straightforward migration and debugging.
	earned_event_names.sort() # Stabilizes file order so diffs and manual diagnostics remain deterministic.
	var save_data: Dictionary = {"version": EVENT_SAVE_VERSION, "earned_events": earned_event_names} # Stores the schema version and complete durable event set.
	save_file.store_string(JSON.stringify(save_data, "\t")) # Writes readable JSON because the event history is tiny and occasionally useful during development.

func _debug_print(message: String) -> void: # Emits achievement-manager diagnostics only in editor and debug builds.
	if not OS.is_debug_build(): # Keeps release sessions free from development-only achievement logging.
		return # Skips console output outside debug testing.
	print("SteamAchievements: %s" % message) # Prefixes every manager message so the complete achievement pipeline is easy to isolate in Godot Output.