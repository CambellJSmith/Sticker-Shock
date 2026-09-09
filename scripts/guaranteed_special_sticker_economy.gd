class_name GuaranteedSpecialStickerEconomy
extends StickerEconomy

const GUARANTEED_RAINBOW_PULL_NUMBER: int = 25 # Guarantees the first milestone prismatic edition on the player's twenty-fifth pack sticker pull.
const GUARANTEED_SILVER_PULL_NUMBER: int = 50 # Guarantees the silver edition on the player's fiftieth pack sticker pull.
const GUARANTEED_GOLD_PULL_NUMBER: int = 100 # Guarantees the rarest gold edition on the player's one-hundredth pack sticker pull.
const COUNTER_SAVE_PATH: String = "user://sticker_special_counter.json" # Stores lifetime pack-pull milestone progress independently from the compatible economy save.

var _pack_pull_count: int = 0 # Tracks lifetime paid and free pack sticker pulls through the final one-time milestone.

func initialize() -> void: # Initializes normal progression first and then restores edition-guarantee progress.
	super.initialize() # Restores currency, collection, cooldown, pack selection, and code redemption through the established economy path.
	_load_or_create_guarantee_state() # Restores the lifetime pull counter while migrating the previous one-milestone save format safely.

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
	_currency += sale_price # Credits the accepted market quote to the same spendable coin balance used for pack purchases.
	_save() # Persists inventory removal and currency credit together so quitting cannot split the transaction.
	return true # Confirms that one exact edition copy was sold and paid successfully.

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
