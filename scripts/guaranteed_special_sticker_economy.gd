class_name GuaranteedSpecialStickerEconomy
extends StickerEconomy

const GUARANTEED_SPECIAL_INTERVAL: int = 25 # Defines the fixed pull cadence used for guaranteed special editions.
const COUNTER_SAVE_PATH: String = "user://sticker_special_counter.json" # Stores guarantee progress independently from the existing compatible economy save.

var _pulls_since_guaranteed_boundary: int = 0 # Tracks pack pulls within the current guarantee cycle across paid and free packs.

func initialize() -> void: # Initializes the normal economy first and then restores the persistent guarantee cadence.
	super.initialize() # Restores the existing currency, collection, cooldown, and redemption state through the established economy path.
	_load_or_create_guarantee_counter() # Restores guarantee progress or reconstructs it from existing collection history when first introduced.

func _apply_special_rolls(base_pack: PackedStringArray) -> PackedStringArray: # Converts authored pulls into edition-aware identities while enforcing the fixed guaranteed-special cadence.
	var result: PackedStringArray = PackedStringArray() # Stores the exact normal-or-special identity for each pull in original order.
	for sticker_path: String in base_pack: # Processes every paid or free pack pull independently in its real draw order.
		_pulls_since_guaranteed_boundary += 1 # Advances the persistent cadence exactly once for each actual pack sticker pull.
		var guaranteed_special: bool = _pulls_since_guaranteed_boundary >= GUARANTEED_SPECIAL_INTERVAL # Detects the fixed boundary pull that must become special regardless of random chance.
		var random_special: bool = _random_number_generator.randf() < StickerVariant.SPECIAL_PULL_CHANCE # Preserves the existing independent random special chance on every pull.
		var special: bool = guaranteed_special or random_special # Makes the boundary pull special while allowing earlier random specials without resetting the cadence.
		result.append(StickerVariant.make_key(sticker_path, special)) # Stores the exact edition identity used by reveal, collection, placement, and persistence.
		if guaranteed_special: # Detects completion of the current fixed cadence after awarding its guaranteed special.
			_pulls_since_guaranteed_boundary = 0 # Starts the next fixed pull cycle without being affected by random special results.
	_save_guarantee_counter() # Persists progress after the complete pack so quitting or switching pack types cannot reset the cadence.
	return result # Returns the complete edition-aware pack while leaving normal rarity selection unchanged.

func _load_or_create_guarantee_counter() -> void: # Restores fixed-cadence progress or establishes a compatible value for saves created before this feature existed.
	if not FileAccess.file_exists(COUNTER_SAVE_PATH): # Detects the first run after introducing persistent guaranteed-special tracking.
		var historical_pack_pulls: int = maxi(get_total_owned_count() - _redeemed_unique_ids.size(), 0) # Reconstructs prior pack pulls by excluding one-time code-redemption rewards from total ownership.
		_pulls_since_guaranteed_boundary = historical_pack_pulls % GUARANTEED_SPECIAL_INTERVAL # Aligns the new guarantee cadence with the player's existing pack-pull history where it can be reconstructed exactly.
		_save_guarantee_counter() # Establishes persistent cadence state immediately for future sessions.
		return # Keeps the reconstructed guarantee progress for the current session.
	var save_file: FileAccess = FileAccess.open(COUNTER_SAVE_PATH, FileAccess.READ) # Opens the compact guarantee progress document for one sequential read.
	if save_file == null: # Detects filesystem failures while preserving a safe in-memory default.
		push_error("could not read sticker special guarantee counter") # Reports persistence failure for development diagnostics without blocking normal pack opening.
		return # Continues with the safe current-session counter rather than using invalid data.
	var parsed_data: Variant = JSON.parse_string(save_file.get_as_text()) # Parses the complete compact guarantee document into Godot variants.
	if parsed_data is not Dictionary: # Rejects malformed counter data that does not contain the expected object root.
		push_warning("sticker special guarantee counter was invalid and has been reset") # Reports recovery while keeping the core progression save untouched.
		_pulls_since_guaranteed_boundary = 0 # Restores a safe cadence origin when the dedicated counter cannot be trusted.
		_save_guarantee_counter() # Replaces malformed counter data with the valid current structure.
		return # Keeps the recovered cadence state for gameplay.
	var save_data: Dictionary = parsed_data # Narrows the validated JSON root for controlled typed access.
	_pulls_since_guaranteed_boundary = clampi(int(save_data.get("pulls_since_guaranteed_boundary", 0)), 0, GUARANTEED_SPECIAL_INTERVAL - 1) # Restores only a valid in-cycle pull count so malformed values cannot skip the next guarantee.

func _save_guarantee_counter() -> void: # Persists the current fixed-cadence position in a compact dedicated document.
	var save_file: FileAccess = FileAccess.open(COUNTER_SAVE_PATH, FileAccess.WRITE) # Opens the guarantee document for replacement with the latest authoritative progress.
	if save_file == null: # Detects a filesystem failure before serialization.
		push_error("could not write sticker special guarantee counter") # Reports persistence failure without interrupting the current pack transaction.
		return # Leaves valid in-memory cadence progress active for the current session.
	var save_data: Dictionary = {"pulls_since_guaranteed_boundary": _pulls_since_guaranteed_boundary} # Packages the only persistent value required to preserve the fixed pull cadence.
	save_file.store_string(JSON.stringify(save_data, "\t")) # Writes human-readable JSON for straightforward debugging and future migration work.
