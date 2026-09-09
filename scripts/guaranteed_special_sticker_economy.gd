class_name GuaranteedSpecialStickerEconomy
extends StickerEconomy

const GUARANTEED_SPECIAL_PULL_NUMBER: int = 25 # Defines the one and only pack sticker pull that is guaranteed to be special.
const COUNTER_SAVE_PATH: String = "user://sticker_special_counter.json" # Stores one-time guarantee progress independently from the existing compatible economy save.

var _pack_pull_count: int = 0 # Tracks lifetime paid and free pack sticker pulls up to the one-time guarantee point.
var _guaranteed_special_awarded: bool = false # Stores whether the one-time 25th-pull guarantee has already been consumed.

func initialize() -> void: # Initializes the normal economy first and then restores the persistent one-time guarantee state.
	super.initialize() # Restores the existing currency, collection, cooldown, and redemption state through the established economy path.
	_load_or_create_guarantee_state() # Restores guarantee progress or reconstructs it from existing collection history when first introduced.

func _apply_special_rolls(base_pack: PackedStringArray) -> PackedStringArray: # Converts authored pulls into edition-aware identities while enforcing the one-time 25th-pull guarantee.
	var result: PackedStringArray = PackedStringArray() # Stores the exact normal-or-special identity for each pull in original order.
	for sticker_path: String in base_pack: # Processes every paid or free pack pull independently in its real draw order.
		if not _guaranteed_special_awarded: # Advances guarantee tracking only until the one-time special has been awarded.
			_pack_pull_count += 1 # Counts this actual paid or free pack sticker pull toward the first 25 pulls.
		var guaranteed_special: bool = not _guaranteed_special_awarded and _pack_pull_count == GUARANTEED_SPECIAL_PULL_NUMBER # Detects only the player's 25th lifetime pack sticker pull.
		var random_special: bool = _random_number_generator.randf() < StickerVariant.SPECIAL_PULL_CHANCE # Preserves the existing independent one-percent random special chance on every pull.
		var special: bool = guaranteed_special or random_special # Forces the 25th pull special while leaving every other pull governed by the normal random chance.
		result.append(StickerVariant.make_key(sticker_path, special)) # Stores the exact edition identity used by reveal, collection, placement, and persistence.
		if guaranteed_special: # Detects completion of the one-time guarantee.
			_guaranteed_special_awarded = true # Permanently disables any future guaranteed specials while leaving random one-percent rolls active.
			_pack_pull_count = GUARANTEED_SPECIAL_PULL_NUMBER # Keeps the stored lifetime guarantee milestone stable after it has been reached.
	_save_guarantee_state() # Persists progress after the complete pack so quitting or switching pack types cannot reset the first-25 counter.
	return result # Returns the complete edition-aware pack while leaving normal rarity selection unchanged.

func _load_or_create_guarantee_state() -> void: # Restores one-time guarantee progress or establishes a compatible value for saves created before this feature existed.
	if not FileAccess.file_exists(COUNTER_SAVE_PATH): # Detects the first run after introducing persistent guaranteed-special tracking.
		var historical_pack_pulls: int = maxi(get_total_owned_count() - _redeemed_unique_ids.size(), 0) # Reconstructs prior pack pulls by excluding one-time code-redemption rewards from total ownership.
		_pack_pull_count = mini(historical_pack_pulls, GUARANTEED_SPECIAL_PULL_NUMBER) # Preserves exact progress before pull 25 and caps later histories at the completed milestone.
		_guaranteed_special_awarded = historical_pack_pulls >= GUARANTEED_SPECIAL_PULL_NUMBER # Treats saves already beyond the 25th pull as having passed the one-time guarantee point.
		_save_guarantee_state() # Establishes persistent one-time guarantee state immediately for future sessions.
		return # Keeps the reconstructed progress for the current session.
	var save_file: FileAccess = FileAccess.open(COUNTER_SAVE_PATH, FileAccess.READ) # Opens the compact guarantee progress document for one sequential read.
	if save_file == null: # Detects filesystem failures while preserving safe in-memory defaults.
		push_error("could not read sticker special guarantee state") # Reports persistence failure for development diagnostics without blocking normal pack opening.
		return # Continues with the safe current-session state rather than using invalid data.
	var parsed_data: Variant = JSON.parse_string(save_file.get_as_text()) # Parses the complete compact guarantee document into Godot variants.
	if parsed_data is not Dictionary: # Rejects malformed guarantee data that does not contain the expected object root.
		push_warning("sticker special guarantee state was invalid and has been reset") # Reports recovery while keeping the core progression save untouched.
		_pack_pull_count = 0 # Restores a safe first-pull origin when the dedicated guarantee state cannot be trusted.
		_guaranteed_special_awarded = false # Restores the one-time guarantee as still available after malformed dedicated state recovery.
		_save_guarantee_state() # Replaces malformed data with the valid current structure.
		return # Keeps the recovered guarantee state for gameplay.
	var save_data: Dictionary = parsed_data # Narrows the validated JSON root for controlled typed access.
	_guaranteed_special_awarded = bool(save_data.get("guaranteed_special_awarded", false)) # Restores whether the one-time guarantee has already been consumed.
	_pack_pull_count = clampi(int(save_data.get("pack_pull_count", 0)), 0, GUARANTEED_SPECIAL_PULL_NUMBER) # Restores only meaningful progress up to the one-time milestone.
	if _guaranteed_special_awarded: # Normalizes completed guarantee saves defensively.
		_pack_pull_count = GUARANTEED_SPECIAL_PULL_NUMBER # Keeps completed state pinned to the one-time milestone rather than allowing malformed lower counts.

func _save_guarantee_state() -> void: # Persists the current one-time guarantee progress in a compact dedicated document.
	var save_file: FileAccess = FileAccess.open(COUNTER_SAVE_PATH, FileAccess.WRITE) # Opens the guarantee document for replacement with the latest authoritative progress.
	if save_file == null: # Detects a filesystem failure before serialization.
		push_error("could not write sticker special guarantee state") # Reports persistence failure without interrupting the current pack transaction.
		return # Leaves valid in-memory guarantee progress active for the current session.
	var save_data: Dictionary = {"pack_pull_count": _pack_pull_count, "guaranteed_special_awarded": _guaranteed_special_awarded} # Packages the persistent values required to preserve the one-time 25th-pull guarantee.
	save_file.store_string(JSON.stringify(save_data, "\t")) # Writes human-readable JSON for straightforward debugging and future migration work.
