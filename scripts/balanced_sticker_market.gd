class_name BalancedStickerMarket
extends EditionStickerMarket

const BALANCE_VERSION: int = 1 # Identifies the current market-value tuning so old absolute-price history is reset only once.
const BALANCED_RARITY_BASE_VALUES: Dictionary[String, int] = {"Common": 8, "Uncommon": 16, "Rare": 36, "Elite": 90, "Legendary": 250, "Unique": 600} # Sets lower ordinary resale anchors while preserving a steep rarity curve and meaningful jackpots.
const RAINBOW_VALUE_MULTIPLIER: float = 3.0 # Prices the one-percent prismatic edition at a strong but attainable premium.
const SILVER_VALUE_MULTIPLIER: float = 6.0 # Prices the half-percent silver edition substantially above rainbow.
const GOLD_VALUE_MULTIPLIER: float = 20.0 # Makes the tenth-percent gold edition a true market jackpot.

func initialize(catalog: StickerCatalog) -> void: # Restores live state, then migrates any pre-balance absolute-price history without resetting trends.
	super.initialize(catalog) # Reuses persistent fifteen-second market timing, trend state, and offline catch-up.
	var changed: bool = false # Tracks whether any old market state needs one-time balance migration.
	for artwork_path: String in _states.keys(): # Visits every persistent authored market state once.
		var state_variant: Variant = _states.get(artwork_path, {}) # Reads the saved state defensively.
		if state_variant is not Dictionary: # Leaves malformed-state recovery to the established market implementation.
			continue # Skips entries that cannot safely carry migration metadata.
		var state: Dictionary = state_variant as Dictionary # Narrows the validated state for migration.
		if int(state.get("balance_version", 0)) >= BALANCE_VERSION: # Detects states already converted to the current value scale.
			continue # Preserves their accumulated live chart history on later launches.
		state["history"] = [] # Removes old absolute-price points so charts do not show an artificial balance-patch crash.
		state["balance_version"] = BALANCE_VERSION # Marks this design as migrated to the current economy tuning.
		_append_history_price(artwork_path, state, catalog) # Seeds one correctly balanced quote at the existing market multiplier.
		_states[artwork_path] = state # Writes the migrated state back without changing its trend or collector preference.
		changed = true # Requests one persistence write after all states are migrated.
	if changed: # Avoids unnecessary disk writes on every normal startup.
		_save() # Persists the one-time history migration atomically.

func get_price(sticker_key: String, catalog: StickerCatalog) -> int: # Returns the balanced live quote for one exact sticker edition.
	var artwork_path: String = StickerVariant.get_art_path(sticker_key) # Resolves premium copies back to the shared authored design state.
	var rarity_name: String = catalog.get_rarity_name(artwork_path) # Reads the rarity that establishes long-run fair value.
	var base_value: int = int(BALANCED_RARITY_BASE_VALUES.get(rarity_name, BALANCED_RARITY_BASE_VALUES["Common"])) # Uses the balanced fallback for unknown future rarity labels.
	var state: Dictionary = _get_state(artwork_path, catalog) # Reuses the persistent collector preference and live market multiplier.
	var normal_quote: float = float(base_value) * float(state.get("collector_factor", 1.0)) * float(state.get("multiplier", 1.0)) # Calculates the current normal-edition quote before finish premium.
	return maxi(int(round(normal_quote * _get_balanced_edition_multiplier(sticker_key))), 1) # Publishes a positive whole-pound price for the exact finish.

func _append_history_price(artwork_path: String, state: Dictionary, catalog: StickerCatalog) -> void: # Records balanced normal-edition quotes for graphing and recent-change calculations.
	var rarity_name: String = catalog.get_rarity_name(artwork_path) # Reads authored rarity without recursing through get_price during state construction.
	var base_value: int = int(BALANCED_RARITY_BASE_VALUES.get(rarity_name, BALANCED_RARITY_BASE_VALUES["Common"])) # Resolves the balanced long-run normal value.
	var normal_price: int = maxi(int(round(float(base_value) * float(state.get("collector_factor", 1.0)) * float(state.get("multiplier", 1.0)))), 1) # Builds the current whole-pound normal quote.
	var history_variant: Variant = state.get("history", []) # Reads persisted chart history defensively.
	var history: Array = [] # Starts with a safe empty chronological series.
	if history_variant is Array: # Accepts only the expected serializable collection.
		history = (history_variant as Array).duplicate() # Uses an independent mutable history before storing it back.
	history.append(normal_price) # Adds the newest normal quote.
	while history.size() > LIVE_HISTORY_LENGTH: # Retains the same rolling thirty-minute chart window as the live market.
		history.pop_front() # Drops the oldest quote as the window advances.
	state["history"] = history # Stores the bounded balanced series back into persistent state.
	state["balance_version"] = BALANCE_VERSION # Marks newly created and updated states as using the current value scale.

func _get_edition_history_multiplier(sticker_key: String) -> float: # Scales the shared normal-price graph into the exact selected finish.
	return _get_balanced_edition_multiplier(sticker_key) # Keeps historical and current edition premiums mathematically identical.

func _get_balanced_edition_multiplier(sticker_key: String) -> float: # Resolves the scarcity premium for one exact edition key.
	match StickerVariant.get_edition(sticker_key): # Maps each persistent finish identity to its market multiplier.
		StickerVariant.EDITION_RAINBOW: return RAINBOW_VALUE_MULTIPLIER # Applies the prismatic premium.
		StickerVariant.EDITION_SILVER: return SILVER_VALUE_MULTIPLIER # Applies the stronger silver premium.
		StickerVariant.EDITION_GOLD: return GOLD_VALUE_MULTIPLIER # Applies the rare gold jackpot premium.
		_: return 1.0 # Leaves normal printed copies at their balanced live quote.
