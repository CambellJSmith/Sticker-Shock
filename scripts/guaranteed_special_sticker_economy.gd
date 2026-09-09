class_name GuaranteedSpecialStickerEconomy
extends StickerEconomy

const GUARANTEED_RAINBOW_PULL_NUMBER: int = 25 # Guarantees the first milestone prismatic edition on the player's twenty-fifth pack sticker pull.
const GUARANTEED_SILVER_PULL_NUMBER: int = 50 # Guarantees the silver edition on the player's fiftieth pack sticker pull.
const GUARANTEED_GOLD_PULL_NUMBER: int = 100 # Guarantees the rarest gold edition on the player's one-hundredth pack sticker pull.
const COUNTER_SAVE_PATH: String = "user://sticker_special_counter.json" # Stores lifetime pack-pull milestone progress independently from the compatible economy save.
const MIN_DYNAMIC_PACK_PRICE: int = 5 # Keeps every purchasable pack at a positive readable price without overriding depressed-market resale economics.
const MAX_DYNAMIC_PACK_PRICE: int = 650 # Prevents extreme bullish spikes from making any authored pack effectively inaccessible.
const PACK_TARGET_RESALE_RETURN: float = 1.12 # Prices packs below current expected resale value so repeated buying and selling has a modest positive long-run return before market timing.
const PRICE_ROUNDING_STEP: int = 5 # Keeps rapidly changing market-linked shop prices readable in whole five-pound increments.
const RANDOM_EDITION_EXPECTED_MULTIPLIER: float = (1.0 - StickerVariant.RAINBOW_PULL_CHANCE - StickerVariant.SILVER_PULL_CHANCE - StickerVariant.GOLD_PULL_CHANCE) + StickerVariant.RAINBOW_PULL_CHANCE * BalancedStickerMarket.RAINBOW_VALUE_MULTIPLIER + StickerVariant.SILVER_PULL_CHANCE * BalancedStickerMarket.SILVER_VALUE_MULTIPLIER + StickerVariant.GOLD_PULL_CHANCE * BalancedStickerMarket.GOLD_VALUE_MULTIPLIER # Converts normal pull EV into edition-aware resale EV without pricing in one-time guarantees.

var _pack_pull_count: int = 0 # Tracks lifetime paid and free pack sticker pulls through the final one-time milestone.
var _pricing_market: StickerMarket # Reads current live sticker values for market-linked shop pricing.
var _pricing_catalog: StickerCatalog # Supplies pack membership and rarity data to the dynamic pricing model.

func initialize() -> void: # Initializes normal progression first and then restores edition-guarantee progress.
	super.initialize() # Restores currency, collection, cooldown, pack selection, and code redemption through the established economy path.
	_load_or_create_guarantee_state() # Restores the lifetime pull counter while migrating the previous one-milestone save format safely.

func configure_market_pricing(market: StickerMarket, catalog: StickerCatalog) -> void: # Connects the live market after both economy and catalogue have completed normal startup.
	_pricing_market = market # Retains the same authoritative quote model used by the collector exchange.
	_pricing_catalog = catalog # Retains authored pack membership for expected-value calculations.

func get_pack_price() -> int: # Returns the selected pack's current market-linked purchase price.
	if _pricing_market == null or _pricing_catalog == null or _selected_pack_name.is_empty(): # Falls back during early startup before live pricing is connected.
		return super.get_pack_price() # Preserves a valid shop price until the market model is ready.
	_pricing_market.advance_to_now(_pricing_catalog) # Publishes any overdue live quote before deriving a new pack price from current values.
	return _calculate_dynamic_pack_price(_selected_pack_name) # Prices only the authored pack currently selected by the player.

func can_buy_pack(catalog: StickerCatalog) -> bool: # Checks affordability against the selected pack's current live-market price.
	return catalog.has_normal_pack(_selected_pack_name) and _currency >= get_pack_price() # Requires valid content and enough pounds for the current quote.

func buy_pack(catalog: StickerCatalog) -> PackedStringArray: # Purchases one selected pack at a price locked from the current market before the draw occurs.
	if not catalog.has_normal_pack(_selected_pack_name): # Rejects stale or invalid authored pack selections before pricing.
		return PackedStringArray() # Leaves currency and inventory untouched.
	var purchase_price: int = get_pack_price() # Locks one price so a fifteen-second market boundary cannot change cost halfway through the transaction.
	if _currency < purchase_price: # Rejects purchases that cannot afford the locked market-linked price.
		return PackedStringArray() # Leaves progression unchanged when funds are insufficient.
	var base_pack: PackedStringArray = catalog.create_random_pack(PACK_SIZE, _random_number_generator, _selected_pack_name) # Draws authored designs using the established rarity probabilities.
	if base_pack.size() != PACK_SIZE: # Protects currency when malformed content cannot produce a complete pack.
		return PackedStringArray() # Returns no reward without charging the player.
	var pack: PackedStringArray = _apply_special_rolls(base_pack) # Applies random editions and one-time milestone guarantees after design selection.
	_currency -= purchase_price # Charges exactly the previously locked dynamic price.
	_grant_pack(pack) # Adds every exact edition copy to persistent ownership.
	_save() # Persists currency and inventory together after the completed purchase.
	return pack # Returns edition-aware identities for reveal presentation.

func sell_owned_copy(sticker_key: String, sale_price: int) -> bool: # Removes exactly one owned edition copy and credits its accepted market value in one persisted progression transaction.
	if sticker_key.is_empty() or sale_price <= 0: # Rejects invalid identities and nonpositive quotes before touching player progression.
		return false # Leaves inventory and currency unchanged for malformed sale requests.
	var current_count: int = get_owned_count(sticker_key) # Reads the exact normal-or-edition count currently owned.
	if current_count <= 0: # Rejects stale sale requests after the final copy has already been sold.
		return false # Prevents inventory from becoming negative or currency from being duplicated.
	if current_count == 1: # Removes the edition key completely when this transaction sells its final owned copy.
		_owned_sticker_counts.erase(sticker_key) # Keeps the compact persistent inventory free from zero-count entries.
	else: # Handles editions where multiple copies remain after this sale.
		_owned_sticker_counts[sticker_key] = current_count - 1 # Removes exactly one copy while preserving every other owned duplicate.
	_currency += sale_price # Credits the accepted market quote to the same spendable pound balance used for pack purchases.
	_save() # Persists inventory removal and currency credit together so quitting cannot split the transaction.
	return true # Confirms that one exact edition copy was sold and paid successfully.

func _calculate_dynamic_pack_price(pack_name: String) -> int: # Prices one authored pack below its current weighted resale EV so the buy-sell loop is sustainable over many random packs.
	var rarity_price_totals: Dictionary[String, float] = {} # Accumulates current normal-edition market prices within each represented rarity.
	var rarity_counts: Dictionary[String, int] = {} # Counts designs in each rarity so same-rarity sticker selection remains uniform.
	for index: int in range(_pricing_catalog.get_sticker_count()): # Scans each authored design once because catalogue sizes are small and shop refresh is throttled.
		var sticker_path: String = _pricing_catalog.get_sticker_path(index) # Reads the normal authored identity for this design.
		if _pricing_catalog.get_pack_name(sticker_path) != pack_name: # Excludes stickers belonging to other authored packs.
			continue # Advances without affecting this pack's valuation.
		var rarity_name: String = _pricing_catalog.get_rarity_name(sticker_path) # Reads the rarity used by the pack's weighted draw.
		if not StickerCatalog.RARITY_WEIGHTS.has(rarity_name): # Excludes Unique and unsupported non-random rarities from paid-pack pricing.
			continue # Keeps pricing aligned with what the pack can actually pull.
		var normal_quote: int = _pricing_market.get_price(sticker_path, _pricing_catalog) # Reads the exact current normal resale quote for this design.
		rarity_price_totals[rarity_name] = float(rarity_price_totals.get(rarity_name, 0.0)) + float(normal_quote) # Adds this design to its rarity's average-value pool.
		rarity_counts[rarity_name] = int(rarity_counts.get(rarity_name, 0)) + 1 # Counts the design for uniform within-rarity selection.
	var total_available_weight: float = 0.0 # Re-normalizes rarity odds around rarities actually represented in this authored pack.
	for rarity_name: String in StickerCatalog.RARITY_WEIGHTS.keys(): # Visits the fixed normal rarity distribution.
		if rarity_counts.has(rarity_name): # Includes only rarities with at least one sticker in this pack.
			total_available_weight += float(StickerCatalog.RARITY_WEIGHTS[rarity_name]) # Adds its configured pull weight to the available total.
	if total_available_weight <= 0.0: # Handles malformed packs defensively.
		return super.get_pack_price() # Falls back to the base price when no valid pullable stickers exist.
	var expected_normal_pull_value: float = 0.0 # Calculates weighted current resale value for one normal-edition design pull.
	for rarity_name: String in StickerCatalog.RARITY_WEIGHTS.keys(): # Visits rarity bands in the same distribution used by actual pack generation.
		if not rarity_counts.has(rarity_name): # Skips rarities unavailable in this specific pack.
			continue # Leaves probability mass re-normalized among represented rarities.
		var rarity_average: float = float(rarity_price_totals[rarity_name]) / float(maxi(rarity_counts[rarity_name], 1)) # Averages current market value among equally selectable designs of this rarity.
		var rarity_probability: float = float(StickerCatalog.RARITY_WEIGHTS[rarity_name]) / total_available_weight # Converts configured weight into this pack's actual pull probability.
		expected_normal_pull_value += rarity_average * rarity_probability # Adds this rarity's contribution to one pull's expected normal resale value.
	var expected_pack_value: float = expected_normal_pull_value * float(PACK_SIZE) * RANDOM_EDITION_EXPECTED_MULTIPLIER # Includes all five slots and ordinary random rainbow/silver/gold odds.
	var raw_price: float = expected_pack_value / PACK_TARGET_RESALE_RETURN # Leaves the configured expected resale margin with the player instead of adding a house markup.
	var rounded_price: int = floori(raw_price / float(PRICE_ROUNDING_STEP)) * PRICE_ROUNDING_STEP # Rounds downward so five-pound presentation steps can never erase the intended positive expected return.
	return clampi(rounded_price, MIN_DYNAMIC_PACK_PRICE, MAX_DYNAMIC_PACK_PRICE) # Keeps the price positive and caps only extreme bullish markets without imposing a loss-making crash floor.

func _apply_special_rolls(base_pack: PackedStringArray) -> PackedStringArray: # Converts authored pulls into explicit normal, rainbow, silver, or gold copy identities.
	var result: PackedStringArray = PackedStringArray() # Stores the exact edition identity for each real pull in original reveal order.
	for sticker_path: String in base_pack: # Processes every paid or free pack sticker independently while sharing one lifetime milestone counter.
		_pack_pull_count += 1 # Counts every actual random-pack sticker pull regardless of whether an earlier random edition was awarded.
		var edition: int = _get_guaranteed_edition(_pack_pull_count) # Gives exact milestone pulls precedence over the normal random edition roll.
		if edition == StickerVariant.EDITION_NORMAL: # Uses random premium odds only when this pull is not one of the three fixed guarantees.
			edition = StickerVariant.roll_random_edition(_random_number_generator) # Rolls mutually exclusive one-percent rainbow, half-percent silver, and tenth-percent gold chances.
		result.append(StickerVariant.make_edition_key(sticker_path, edition)) # Stores the finish with the copy so collection, book, inspection, and market all preserve it.
	_save_guarantee_state() # Persists progress after the complete pack so quitting or changing pack type cannot reset any milestone.
	return result # Returns the complete edition-aware pack without changing authored rarity selection.

func _get_guaranteed_edition(pull_number: int) -> int: # Resolves the three one-time lifetime milestone finishes without resetting between milestones.
	if pull_number == GUARANTEED_RAINBOW_PULL_NUMBER: # Detects exactly the twenty-fifth lifetime paid/free pack sticker pull.
		return StickerVariant.EDITION_RAINBOW # Forces the prismatic rainbow edition regardless of the random roll.
	if pull_number == GUARANTEED_SILVER_PULL_NUMBER: # Detects exactly the fiftieth lifetime paid/free pack sticker pull.
		return StickerVariant.EDITION_SILVER # Forces the silver-metal edition regardless of earlier random specials.
	if pull_number == GUARANTEED_GOLD_PULL_NUMBER: # Detects exactly the one-hundredth lifetime paid/free pack sticker pull.
		return StickerVariant.EDITION_GOLD # Forces the rarest gold-metal edition regardless of earlier random specials.
	return StickerVariant.EDITION_NORMAL # Reports no milestone override for every other pull.

func _load_or_create_guarantee_state() -> void: # Restores lifetime milestone progress and migrates the previous twenty-fifth-pull-only state format.
	var historical_pack_pulls: int = maxi(get_total_owned_count() - _redeemed_unique_ids.size(), 0) # Provides a conservative fallback estimate from currently owned random-pack copies while excluding code rewards.
	if not FileAccess.file_exists(COUNTER_SAVE_PATH): # Detects the first run with any dedicated milestone tracking.
		_pack_pull_count = mini(historical_pack_pulls, GUARANTEED_GOLD_PULL_NUMBER) # Starts from existing collection history and caps only after the final guaranteed milestone.
		_save_guarantee_state() # Establishes the new persistent counter immediately.
		return # Keeps the reconstructed progress active for the current session.
	var save_file: FileAccess = FileAccess.open(COUNTER_SAVE_PATH, FileAccess.READ) # Opens the compact milestone progress document for one sequential read.
	if save_file == null: # Detects filesystem failures while preserving safe in-memory defaults.
		push_error("could not read sticker edition guarantee state") # Reports persistence failure without blocking normal pack opening.
		_pack_pull_count = mini(historical_pack_pulls, GUARANTEED_GOLD_PULL_NUMBER) # Falls back to the best available collection-derived estimate.
		return # Continues with safe current-session progress.
	var parsed_data: Variant = JSON.parse_string(save_file.get_as_text()) # Parses old or new milestone JSON into Godot variants.
	if parsed_data is not Dictionary: # Rejects malformed dedicated state without touching core progression.
		push_warning("sticker edition guarantee state was invalid and has been rebuilt") # Reports recovery for development diagnostics.
		_pack_pull_count = mini(historical_pack_pulls, GUARANTEED_GOLD_PULL_NUMBER) # Reconstructs the strongest safe estimate available.
		_save_guarantee_state() # Replaces malformed data with the current format.
		return # Keeps rebuilt progress for gameplay.
	var save_data: Dictionary = parsed_data # Narrows the validated object for controlled access.
	var stored_pull_count: int = maxi(int(save_data.get("pack_pull_count", 0)), 0) # Reads both the old and new counter field without relying on removed boolean flags.
	if save_data.has("guaranteed_special_awarded"): # Detects the previous twenty-fifth-only format introduced before multiple editions existed.
		stored_pull_count = maxi(stored_pull_count, GUARANTEED_RAINBOW_PULL_NUMBER if bool(save_data.get("guaranteed_special_awarded", false)) else 0) # Preserves at least the milestone already passed by the old save.
	_pack_pull_count = clampi(maxi(stored_pull_count, historical_pack_pulls), 0, GUARANTEED_GOLD_PULL_NUMBER) # Uses the strongest available history estimate and continues counting toward silver and gold.
	_save_guarantee_state() # Rewrites legacy state into the compact new format immediately after successful migration.

func _save_guarantee_state() -> void: # Persists lifetime random-pack sticker-pull progress through the final one-time edition milestone.
	var save_file: FileAccess = FileAccess.open(COUNTER_SAVE_PATH, FileAccess.WRITE) # Opens the dedicated milestone document for replacement.
	if save_file == null: # Detects filesystem failure before serialization.
		push_error("could not write sticker edition guarantee state") # Reports persistence failure without interrupting the current pack transaction.
		return # Leaves valid in-memory progress active for the session.
	var save_data: Dictionary = {"pack_pull_count": _pack_pull_count, "guarantee_version": 2} # Stores only the lifetime count because milestone completion is implied by passing each exact pull number.
	save_file.store_string(JSON.stringify(save_data, "\t")) # Writes readable JSON for straightforward future migration and debugging.
