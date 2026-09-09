class_name EditionStickerMarket
extends StickerMarket

const LIVE_TICK_SECONDS: int = 15 # Publishes one visible market quote every fifteen real-world seconds.
const LIVE_HISTORY_LENGTH: int = 120 # Retains thirty minutes of fifteen-second quotes for the live chart.
const MAX_LIVE_CATCHUP_TICKS: int = 240 # Caps offline catch-up to one hour of fine-grained ticks so reopening stays fast.
const RAINBOW_VALUE_RATIO: float = 0.25 # Converts the legacy twelve-times premium into a three-times rainbow premium.
const SILVER_VALUE_RATIO: float = 0.50 # Converts the legacy twelve-times premium into a six-times silver premium.

func advance_to_now(catalog: StickerCatalog) -> bool: # Advances the market on the faster live cadence while preserving persistent real-world timing.
	var current_unix: int = int(Time.get_unix_time_from_system()) # Reads the current UTC Unix timestamp once for this update.
	if _last_tick_unix <= 0: # Establishes a clean clock when no previous market timestamp exists.
		_last_tick_unix = current_unix - current_unix % LIVE_TICK_SECONDS # Anchors the first quote to the current fifteen-second bucket.
		_save() # Persists the initialized clock immediately.
		return false # Reports that no historical movement occurred during initialization.
	var elapsed_seconds: int = maxi(current_unix - _last_tick_unix, 0) # Ignores backwards system-clock movement rather than reversing prices.
	var elapsed_ticks: int = int(elapsed_seconds / LIVE_TICK_SECONDS) # Converts elapsed wall time into complete live-market intervals.
	if elapsed_ticks <= 0: # Rejects polling before another fifteen-second quote is due.
		return false # Leaves all current quotes unchanged.
	var simulated_ticks: int = mini(elapsed_ticks, MAX_LIVE_CATCHUP_TICKS) # Bounds offline catch-up work to a predictable amount.
	for _tick_index: int in range(simulated_ticks): # Advances each elapsed live quote in chronological order.
		_advance_one_tick(catalog) # Applies trend drift, collector noise, shocks, and mean reversion.
	_last_tick_unix = current_unix - current_unix % LIVE_TICK_SECONDS # Publishes the newest quote at the active fifteen-second boundary.
	_save() # Persists the complete moved market atomically after catch-up.
	return true # Tells the HUD to refresh prices and the selected chart.

func get_seconds_until_next_tick() -> int: # Returns the whole seconds remaining until the next live quote.
	var current_unix: int = int(Time.get_unix_time_from_system()) # Reads the same UTC clock used for market advancement.
	var next_tick_unix: int = _last_tick_unix + LIVE_TICK_SECONDS # Calculates the next fifteen-second quote boundary.
	return maxi(next_tick_unix - current_unix, 0) # Clamps overdue markets to zero so the HUD advances immediately.

func get_price(sticker_key: String, catalog: StickerCatalog) -> int: # Returns the live quote while scaling premium value according to edition scarcity.
	var base_quote: int = super.get_price(sticker_key, catalog) # Reuses the shared rarity, collector preference, and live multiplier calculation.
	match StickerVariant.get_edition(sticker_key): # Adjusts only premium editions after shared market movement is calculated.
		StickerVariant.EDITION_RAINBOW: return maxi(int(round(float(base_quote) * RAINBOW_VALUE_RATIO)), 1) # Values rainbow at roughly three times normal.
		StickerVariant.EDITION_SILVER: return maxi(int(round(float(base_quote) * SILVER_VALUE_RATIO)), 1) # Values silver at roughly six times normal.
		_: return base_quote # Keeps normal unchanged and gold at the full twelve-times premium.

func get_price_history(sticker_key: String, catalog: StickerCatalog) -> PackedFloat32Array: # Returns chart-ready historical prices for one exact edition.
	var artwork_path: String = StickerVariant.get_art_path(sticker_key) # Resolves every edition back to the shared authored market state.
	var state: Dictionary = _get_state(artwork_path, catalog) # Reads the persistent state containing normal-edition quote history.
	var history_variant: Variant = state.get("history", []) # Retrieves the saved history defensively.
	var result: PackedFloat32Array = PackedFloat32Array() # Allocates the compact chart output.
	if history_variant is not Array: # Rejects malformed history without disturbing current market state.
		return result # Returns an empty graph safely.
	var multiplier: float = _get_edition_history_multiplier(sticker_key) # Resolves the exact edition premium applied to every historical point.
	for price_variant: Variant in history_variant as Array: # Converts each stored normal quote into the selected edition quote.
		result.append(maxf(float(price_variant) * multiplier, 1.0)) # Preserves the same percentage movement while scaling absolute edition value.
	return result # Returns chronological values ready for native custom drawing.

func _advance_one_tick(catalog: StickerCatalog) -> void: # Evolves every design through one fifteen-second market interval with watchable volatility.
	_ensure_catalog_states(catalog) # Ensures newly authored stickers have a valid market state before iteration.
	for artwork_path: String in _states.keys(): # Advances every sticker independently so simultaneous markets can diverge.
		var state_variant: Variant = _states.get(artwork_path, {}) # Reads the stored mutable market state.
		if state_variant is not Dictionary: # Detects malformed runtime or persisted state.
			_states[artwork_path] = _create_state(artwork_path, catalog) # Rebuilds the bad entry at a safe fair-value state.
			continue # Moves on after repairing this design.
		var state: Dictionary = state_variant as Dictionary # Narrows the validated state for fast repeated access.
		var trend_ticks_remaining: int = maxi(int(state.get("trend_ticks_remaining", 0)), 0) # Reads how many live ticks remain in the current regime.
		if trend_ticks_remaining <= 0: # Starts a new directional run only after the previous one expires.
			_assign_new_trend(state) # Chooses the next bullish, bearish, or sideways regime.
		var trend: int = clampi(int(state.get("trend", 0)), -1, 1) # Reads the active signed market direction.
		var trend_strength: float = float(state.get("trend_strength", 0.002)) # Reads the small per-tick directional drift.
		var random_noise: float = _random_number_generator.randf_range(-0.012, 0.012) # Adds visible but controlled collector noise every fifteen seconds.
		var demand_shock: float = 0.0 # Leaves most ticks without an exceptional event.
		if _random_number_generator.randf() < 0.012: # Gives occasional larger jumps enough rarity to feel noteworthy.
			var shock_direction: float = -1.0 if _random_number_generator.randf() < 0.5 else 1.0 # Chooses positive and negative shocks symmetrically.
			demand_shock = shock_direction * _random_number_generator.randf_range(0.025, 0.075) # Produces sudden but bounded collector-demand spikes or selloffs.
		var current_multiplier: float = clampf(float(state.get("multiplier", 1.0)), MIN_MULTIPLIER, MAX_MULTIPLIER) # Reads the current bounded market multiplier.
		var directional_change: float = float(trend) * trend_strength # Converts persistent direction into signed drift.
		var mean_reversion: float = (1.0 - current_multiplier) * 0.003 # Pulls extreme values gently toward fair value over many live ticks.
		var next_multiplier: float = current_multiplier * (1.0 + directional_change + random_noise + demand_shock) + mean_reversion # Combines all live-market forces into the next quote.
		state["multiplier"] = clampf(next_multiplier, MIN_MULTIPLIER, MAX_MULTIPLIER) # Publishes the bounded new price factor.
		state["trend_ticks_remaining"] = maxi(int(state.get("trend_ticks_remaining", 1)) - 1, 0) # Advances one fifteen-second step through the current regime.
		_append_history_price(artwork_path, state, catalog) # Records the quote for the scrolling chart and recent-move display.
		_states[artwork_path] = state # Writes the mutated state back to the authoritative market dictionary.

func _assign_new_trend(state: Dictionary) -> void: # Starts a multi-minute live market regime so players can watch momentum develop.
	var regime_roll: float = _random_number_generator.randf() # Draws one balanced selector for the next direction.
	var trend: int = 0 # Defaults to a sideways consolidation period.
	if regime_roll < 0.40: # Gives bearish regimes substantial frequency.
		trend = -1 # Starts a persistent falling run.
	elif regime_roll >= 0.60: # Gives bullish regimes equal frequency to bearish ones.
		trend = 1 # Starts a persistent rising run.
	state["trend"] = trend # Persists the chosen direction across many live updates.
	state["trend_strength"] = _random_number_generator.randf_range(0.0015, 0.0055) if trend != 0 else _random_number_generator.randf_range(0.0, 0.0010) # Sets meaningful momentum without overwhelming short-term noise.
	state["trend_ticks_remaining"] = _random_number_generator.randi_range(20, 80) # Keeps regimes alive for roughly five to twenty minutes.

func _append_history_price(artwork_path: String, state: Dictionary, catalog: StickerCatalog) -> void: # Stores one compact normal quote for the thirty-minute live chart window.
	var rarity_name: String = catalog.get_rarity_name(artwork_path) # Reads authored rarity directly to avoid recursive quote lookup during construction.
	var base_value: int = int(RARITY_BASE_VALUES.get(rarity_name, RARITY_BASE_VALUES["Common"])) # Resolves the normal long-term price anchor.
	var normal_price: int = maxi(int(round(float(base_value) * float(state.get("collector_factor", 1.0)) * float(state.get("multiplier", 1.0)))), 1) # Builds the exact normal-edition published quote.
	var history_variant: Variant = state.get("history", []) # Reads persisted history defensively.
	var history: Array = [] # Starts with an empty safe history collection.
	if history_variant is Array: # Accepts only the expected serializable array.
		history = (history_variant as Array).duplicate() # Uses an independent mutable copy before replacing state.
	history.append(normal_price) # Adds the newest quote in chronological order.
	while history.size() > LIVE_HISTORY_LENGTH: # Bounds saved/chart history to thirty minutes.
		history.pop_front() # Discards the oldest point as the live window scrolls forward.
	state["history"] = history # Stores the bounded chronological history back into market state.

func _get_edition_history_multiplier(sticker_key: String) -> float: # Returns the absolute price multiplier represented by one edition's chart.
	match StickerVariant.get_edition(sticker_key): # Maps exact finish to its established scarcity premium.
		StickerVariant.EDITION_RAINBOW: return SPECIAL_VALUE_MULTIPLIER * RAINBOW_VALUE_RATIO # Produces the three-times rainbow history.
		StickerVariant.EDITION_SILVER: return SPECIAL_VALUE_MULTIPLIER * SILVER_VALUE_RATIO # Produces the six-times silver history.
		StickerVariant.EDITION_GOLD: return SPECIAL_VALUE_MULTIPLIER # Produces the twelve-times gold history.
		_: return 1.0 # Leaves normal history at its stored value.
