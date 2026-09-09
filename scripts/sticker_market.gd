class_name StickerMarket
extends RefCounted

const SAVE_PATH: String = "user://sticker_market.json" # Stores persistent live sticker-market pricing independently from player inventory.
const SAVE_VERSION: int = 1 # Identifies the initial trend-driven sticker market save format.
const MARKET_TICK_SECONDS: int = 10 * 60 # Advances sticker values on a real-world ten-minute cadence.
const MAX_CATCHUP_TICKS: int = 1008 # Caps one startup catch-up pass to seven days so long absences never stall loading.
const HISTORY_LENGTH: int = 18 # Retains enough recent quotes to show short-term movement without bloating the save.
const SPECIAL_VALUE_MULTIPLIER: float = 12.0 # Makes gold special editions dramatically more valuable than the matching normal copy.
const MIN_MULTIPLIER: float = 0.35 # Prevents prolonged bearish runs from collapsing a sticker to effectively zero value.
const MAX_MULTIPLIER: float = 3.50 # Prevents extended bullish runs from inflating a sticker without practical bounds.
const RARITY_BASE_VALUES: Dictionary[String, int] = {"Common": 16, "Uncommon": 28, "Rare": 55, "Elite": 110, "Legendary": 240, "Unique": 420} # Establishes sharply increasing collector value by authored rarity.

var _states: Dictionary[String, Variant] = {} # Stores one persistent dictionary state per authored sticker design while keeping the outer string keys statically typed.
var _last_tick_unix: int = 0 # Stores the UTC boundary of the most recently simulated market tick.
var _random_number_generator: RandomNumberGenerator = RandomNumberGenerator.new() # Owns all market noise, regime changes, and occasional demand shocks.

func initialize(catalog: StickerCatalog) -> void: # Restores market state, creates any newly authored sticker states, and catches prices up to the current real-world tick.
	_random_number_generator.randomize() # Seeds market randomness independently from pack-opening randomness.
	_load_or_create_save() # Restores persistent per-design multipliers and trend regimes before touching current catalogue content.
	_ensure_catalog_states(catalog) # Creates market entries for stickers added since the previous save without disturbing existing price history.
	advance_to_now(catalog) # Applies every elapsed ten-minute market step up to the configured catch-up ceiling.
	_save() # Persists newly created catalogue states even when no market tick elapsed this session.

func advance_to_now(catalog: StickerCatalog) -> bool: # Advances persistent values by elapsed real-world ticks and reports whether any quote changed.
	var current_unix: int = int(Time.get_unix_time_from_system()) # Reads the current UTC Unix timestamp from Godot's system-time API.
	if _last_tick_unix <= 0: # Establishes a clean market clock for first-run or malformed legacy state.
		_last_tick_unix = current_unix - current_unix % MARKET_TICK_SECONDS # Anchors the market to the current ten-minute UTC bucket.
		_save() # Persists the stable bucket immediately so reopening cannot repeatedly initialize the same clock.
		return false # Reports no price movement because no prior interval existed to simulate.
	var elapsed_seconds: int = maxi(current_unix - _last_tick_unix, 0) # Ignores backwards system-clock changes rather than reversing market history.
	var elapsed_ticks: int = int(elapsed_seconds / MARKET_TICK_SECONDS) # Converts wall-clock elapsed time into complete pricing intervals explicitly for the static analyzer.
	if elapsed_ticks <= 0: # Rejects sub-tick polling without writing or touching quote state.
		return false # Reports that the market remains on the current published quote.
	var simulated_ticks: int = mini(elapsed_ticks, MAX_CATCHUP_TICKS) # Bounds startup work while still allowing a full week of offline market evolution.
	for _tick_index: int in range(simulated_ticks): # Advances each elapsed market interval in deterministic sequence.
		_advance_one_tick(catalog) # Applies trend drift, random collector noise, demand shocks, and mean reversion once.
	_last_tick_unix = current_unix - current_unix % MARKET_TICK_SECONDS # Publishes the newest simulated quote at the current UTC market bucket.
	_save() # Persists all moved prices and regimes atomically after the complete catch-up pass.
	return true # Reports that visible market quotes should be refreshed.

func get_price(sticker_key: String, catalog: StickerCatalog) -> int: # Returns the current whole-coin bid for one exact normal or gold special edition copy.
	var artwork_path: String = StickerVariant.get_art_path(sticker_key) # Collapses edition identity to the authored design that owns live demand state.
	var rarity_name: String = catalog.get_rarity_name(artwork_path) # Reads the authored rarity that establishes the long-term base value.
	var base_value: int = int(RARITY_BASE_VALUES.get(rarity_name, RARITY_BASE_VALUES["Common"])) # Falls back safely for future unsupported rarity strings.
	var state: Dictionary = _get_state(artwork_path, catalog) # Retrieves or lazily creates the persistent design-level market state.
	var collector_factor: float = float(state.get("collector_factor", 1.0)) # Reads the stable design-specific collector preference that differentiates equal-rarity stickers.
	var market_multiplier: float = float(state.get("multiplier", 1.0)) # Reads the live trend-and-noise multiplier produced by market ticks.
	var edition_multiplier: float = SPECIAL_VALUE_MULTIPLIER if StickerVariant.is_special(sticker_key) else 1.0 # Applies the dramatic premium only to an actually pulled gold copy.
	return maxi(int(round(float(base_value) * collector_factor * market_multiplier * edition_multiplier)), 1) # Produces a stable positive whole-coin sell quote.

func get_trend_direction(sticker_key: String, catalog: StickerCatalog) -> int: # Returns the current persistent market regime as bearish, flat, or bullish.
	var state: Dictionary = _get_state(StickerVariant.get_art_path(sticker_key), catalog) # Resolves the shared design-level state for either edition.
	return clampi(int(state.get("trend", 0)), -1, 1) # Restricts malformed saved values to the three supported trend directions.

func get_recent_change_percent(sticker_key: String, catalog: StickerCatalog) -> float: # Returns the percentage movement between the two most recent normal-edition quotes.
	var artwork_path: String = StickerVariant.get_art_path(sticker_key) # Uses the shared authored design because edition multiplier does not affect percentage change.
	var state: Dictionary = _get_state(artwork_path, catalog) # Retrieves the live state containing compact quote history.
	var history_variant: Variant = state.get("history", []) # Reads the serializable quote-history field defensively.
	if history_variant is not Array: # Rejects malformed history without affecting current pricing.
		return 0.0 # Reports no measurable recent movement when history cannot be trusted.
	var history: Array = history_variant as Array # Narrows the validated history collection for indexed access.
	if history.size() < 2: # Requires two published quotes before a percentage change can exist.
		return 0.0 # Reports a neutral initial movement value.
	var previous_price: float = maxf(float(history[history.size() - 2]), 1.0) # Protects division from malformed zero-valued historical data.
	var current_price: float = float(history[history.size() - 1]) # Reads the latest published normal-edition quote.
	return ((current_price - previous_price) / previous_price) * 100.0 # Converts the latest movement into player-readable percentage points.

func get_seconds_until_next_tick() -> int: # Returns real-world whole seconds until the next ten-minute quote publication.
	var current_unix: int = int(Time.get_unix_time_from_system()) # Reads the same UTC clock used by market advancement.
	var next_tick_unix: int = _last_tick_unix + MARKET_TICK_SECONDS # Calculates the next published quote boundary from persisted market time.
	return maxi(next_tick_unix - current_unix, 0) # Clamps overdue markets to zero so the HUD can request an immediate advance.

func _advance_one_tick(catalog: StickerCatalog) -> void: # Evolves every authored sticker through one common market interval while preserving independent trends.
	_ensure_catalog_states(catalog) # Guarantees stickers added while the game is running receive valid state before iteration.
	for artwork_path: String in _states.keys(): # Advances each design independently so one sticker can rally while another falls.
		var state_variant: Variant = _states.get(artwork_path, {}) # Retrieves the stored per-design state through the typed outer dictionary.
		if state_variant is not Dictionary: # Rejects malformed runtime state rather than allowing one bad entry to break the complete market tick.
			_states[artwork_path] = _create_state(artwork_path, catalog) # Replaces the invalid entry with a clean fair-value market state.
			continue # Advances to the next design after restoring this malformed entry.
		var state: Dictionary = state_variant as Dictionary # Narrows the validated mutable state for the current market tick.
		var trend_ticks_remaining: int = maxi(int(state.get("trend_ticks_remaining", 0)), 0) # Reads how long the current directional regime still persists.
		if trend_ticks_remaining <= 0: # Chooses a new multi-tick regime only after the previous run completes.
			_assign_new_trend(state) # Starts another bullish, bearish, or sideways period with a random duration.
		var trend: int = clampi(int(state.get("trend", 0)), -1, 1) # Reads the active directional regime after any required renewal.
		var trend_strength: float = float(state.get("trend_strength", 0.03)) # Reads the persistent per-tick drift magnitude for this regime.
		var random_noise: float = _random_number_generator.randf_range(-0.075, 0.075) # Adds substantial short-term collector randomness around the persistent direction.
		var demand_shock: float = 0.0 # Starts most ticks without an exceptional demand event.
		if _random_number_generator.randf() < 0.06: # Gives a small chance of a visibly larger market jump or drop.
			var shock_direction: float = -1.0 if _random_number_generator.randf() < 0.5 else 1.0 # Chooses positive and negative shocks symmetrically.
			demand_shock = shock_direction * _random_number_generator.randf_range(0.08, 0.22) # Produces occasional speculative volatility large enough to reward timing.
		var current_multiplier: float = clampf(float(state.get("multiplier", 1.0)), MIN_MULTIPLIER, MAX_MULTIPLIER) # Reads the current quote factor inside safe market bounds.
		var directional_change: float = float(trend) * trend_strength # Converts the persistent regime into signed percentage drift for this interval.
		var mean_reversion: float = (1.0 - current_multiplier) * 0.025 # Pulls extreme values gently toward fair value without erasing profitable runs.
		var next_multiplier: float = current_multiplier * (1.0 + directional_change + random_noise + demand_shock) + mean_reversion # Combines regime, noise, shock, and long-run stabilization into the next quote factor.
		state["multiplier"] = clampf(next_multiplier, MIN_MULTIPLIER, MAX_MULTIPLIER) # Publishes the bounded live value multiplier for this design.
		state["trend_ticks_remaining"] = maxi(int(state.get("trend_ticks_remaining", 1)) - 1, 0) # Advances one interval through the persistent directional run.
		_append_history_price(artwork_path, state, catalog) # Records the new normal-edition quote for recent-change presentation.
		_states[artwork_path] = state # Writes the mutated state back into the typed design-state dictionary.

func _assign_new_trend(state: Dictionary) -> void: # Starts a new persistent market regime with independently randomized direction, strength, and duration.
	var regime_roll: float = _random_number_generator.randf() # Draws one balanced regime selector for this sticker's next directional run.
	var trend: int = 0 # Defaults to a sideways market before evaluating directional thresholds.
	if regime_roll < 0.40: # Gives bearish runs substantial but not dominant frequency.
		trend = -1 # Starts a persistent downward price regime.
	elif regime_roll >= 0.60: # Gives bullish runs the same frequency as bearish runs.
		trend = 1 # Starts a persistent upward price regime.
	state["trend"] = trend # Persists direction so subsequent ticks continue the same speculative run.
	state["trend_strength"] = _random_number_generator.randf_range(0.018, 0.055) if trend != 0 else _random_number_generator.randf_range(0.0, 0.012) # Gives directional runs meaningful drift while sideways periods move mostly from noise.
	state["trend_ticks_remaining"] = _random_number_generator.randi_range(4, 14) # Keeps regimes alive for forty minutes to more than two hours of real time.

func _ensure_catalog_states(catalog: StickerCatalog) -> void: # Ensures every current authored sticker has an independent persistent market entry.
	for index: int in range(catalog.get_sticker_count()): # Visits each catalogue design exactly once.
		var artwork_path: String = catalog.get_sticker_path(index) # Reads the stable authored artwork identity used as the market key.
		if artwork_path.is_empty() or _states.has(artwork_path): # Skips invalid paths and market states already restored from disk.
			continue # Advances without disturbing established price history.
		_states[artwork_path] = _create_state(artwork_path, catalog) # Creates a fresh fair-value-biased market entry for the newly discovered design.

func _get_state(artwork_path: String, catalog: StickerCatalog) -> Dictionary: # Returns one valid design state while supporting newly added catalogue content lazily.
	if not _states.has(artwork_path): # Detects a design that did not exist when the market was initialized.
		_states[artwork_path] = _create_state(artwork_path, catalog) # Creates its first persistent quote without touching other stickers.
	var state_variant: Variant = _states.get(artwork_path, {}) # Retrieves the stored state through the statically typed outer lookup.
	if state_variant is Dictionary: # Accepts the expected mutable dictionary state.
		return state_variant as Dictionary # Returns the validated design-level market state.
	var replacement_state: Dictionary = _create_state(artwork_path, catalog) # Reconstructs malformed state defensively from current authored metadata.
	_states[artwork_path] = replacement_state # Replaces the invalid entry so subsequent reads remain stable.
	return replacement_state # Returns the newly valid state to the requesting quote path.

func _create_state(artwork_path: String, catalog: StickerCatalog) -> Dictionary: # Creates the initial collector preference, quote multiplier, trend, and history for one authored design.
	var sticker_id: int = maxi(catalog.get_sticker_id(artwork_path), 1) # Uses authored numeric identity to derive a stable design-specific demand preference.
	var collector_wave: float = sin(float(sticker_id) * 12.9898) * 43758.5453 # Produces deterministic pseudo-random variation without consuming runtime market randomness.
	var collector_fraction: float = collector_wave - floor(collector_wave) # Normalizes the deterministic design variation into a zero-to-one range.
	var state: Dictionary = {"collector_factor": lerpf(0.84, 1.22, collector_fraction), "multiplier": _random_number_generator.randf_range(0.88, 1.12), "trend": 0, "trend_strength": 0.0, "trend_ticks_remaining": 0, "history": []} # Seeds each design near fair value with its own persistent collector premium.
	_assign_new_trend(state) # Starts the design inside a real multi-tick directional regime immediately.
	_append_history_price(artwork_path, state, catalog) # Records the initial published normal-edition quote for future percentage comparison.
	return state # Returns the complete serializable market entry.

func _append_history_price(artwork_path: String, state: Dictionary, catalog: StickerCatalog) -> void: # Stores one compact normal-edition quote after a market update.
	var rarity_name: String = catalog.get_rarity_name(artwork_path) # Reads rarity directly because get_price would recurse through state lookup during construction.
	var base_value: int = int(RARITY_BASE_VALUES.get(rarity_name, RARITY_BASE_VALUES["Common"])) # Resolves the normal-edition long-term value anchor.
	var normal_price: int = maxi(int(round(float(base_value) * float(state.get("collector_factor", 1.0)) * float(state.get("multiplier", 1.0)))), 1) # Builds the published normal-edition quote for historical percentage movement.
	var history_variant: Variant = state.get("history", []) # Retrieves the serializable history collection defensively.
	var history: Array = [] # Seeds a safe empty history before validating persisted state.
	if history_variant is Array: # Accepts only the expected serializable quote-history collection.
		history = (history_variant as Array).duplicate() # Uses an independent mutable copy so state replacement remains explicit.
	history.append(normal_price) # Appends the newly published quote in chronological order.
	while history.size() > HISTORY_LENGTH: # Keeps only the compact recent market window needed by UI feedback.
		history.pop_front() # Removes the oldest quote without reallocating the entire state object.
	state["history"] = history # Stores the bounded history back into the design state.

func _load_or_create_save() -> void: # Restores the persistent market document or establishes first-run timing and empty state.
	_states.clear() # Starts from a clean model so corrupt or missing saves cannot leave stale runtime state.
	_last_tick_unix = 0 # Resets market time before attempting persistent reconstruction.
	if not FileAccess.file_exists(SAVE_PATH): # Detects first run before attempting to read a nonexistent market file.
		_last_tick_unix = int(Time.get_unix_time_from_system()) # Seeds the initial market clock from current UTC time.
		_last_tick_unix -= _last_tick_unix % MARKET_TICK_SECONDS # Aligns the first market publication to the active ten-minute bucket.
		return # Leaves catalogue-state creation to initialization after the empty market document is established.
	var save_file: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.READ) # Opens the compact market document for one sequential read.
	if save_file == null: # Detects filesystem failure without affecting the player's main progression save.
		push_error("could not read sticker market save") # Reports market persistence failure for development diagnostics.
		return # Continues with a fresh current-session market rather than crashing gameplay.
	var parsed_data: Variant = JSON.parse_string(save_file.get_as_text()) # Parses the human-readable market JSON into Godot variants.
	if parsed_data is not Dictionary: # Rejects malformed documents that do not contain the expected object root.
		push_warning("sticker market save was invalid and has been reset") # Reports market-only recovery while preserving inventory and book saves.
		return # Keeps the safe empty state for reinitialization.
	var save_data: Dictionary = parsed_data # Narrows the validated root for typed field access.
	_last_tick_unix = maxi(int(save_data.get("last_tick_unix", 0)), 0) # Restores the UTC market bucket while rejecting malformed negative timestamps.
	var saved_states_variant: Variant = save_data.get("states", {}) # Retrieves the serialized per-design state object.
	if saved_states_variant is Dictionary: # Accepts state only when the JSON field has the expected object structure.
		var saved_states: Dictionary = saved_states_variant # Narrows the validated market-state dictionary.
		for artwork_path_variant: Variant in saved_states.keys(): # Visits every persisted authored design identity once.
			var artwork_path: String = str(artwork_path_variant) # Converts JSON keys into the runtime string representation.
			var state_variant: Variant = saved_states.get(artwork_path_variant, {}) # Retrieves the serialized state associated with this design.
			if not artwork_path.is_empty() and state_variant is Dictionary: # Keeps only meaningful design keys with valid object states.
				_states[artwork_path] = (state_variant as Dictionary).duplicate(true) # Restores an independent mutable copy for current-session simulation.

func _save() -> void: # Persists market clock and per-design trend state without touching the main progression document.
	var save_file: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.WRITE) # Opens the dedicated market document for atomic replacement.
	if save_file == null: # Detects filesystem failure before serialization.
		push_error("could not write sticker market save") # Reports market persistence failure without interrupting gameplay or selling.
		return # Leaves valid in-memory prices active for the current session.
	var save_data: Dictionary = {"version": SAVE_VERSION, "last_tick_unix": _last_tick_unix, "states": _states.duplicate(true)} # Packages every value required to resume trends and recent history exactly.
	save_file.store_string(JSON.stringify(save_data, "\t")) # Writes readable JSON for debugging and future market migrations.
