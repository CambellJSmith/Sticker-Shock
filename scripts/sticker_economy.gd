class_name StickerEconomy
extends RefCounted

const SAVE_PATH: String = "user://sticker_progress.json" # Stores persistent player progression in Godot's writable per-user data directory.
const SAVE_VERSION: int = 1 # Identifies the current progression file structure for future migrations.
const STARTING_CURRENCY: int = 500 # Defines the initial in-game currency granted when no progression save exists.
const PACK_PRICE: int = 100 # Defines the in-game currency cost of one normal sticker pack.
const PACK_SIZE: int = 5 # Defines how many independently drawn stickers every normal or free pack grants.
const FREE_PACK_COOLDOWN_SECONDS: int = 6 * 60 * 60 # Defines the real-world cooldown applied after claiming a free pack.

var _currency: int = STARTING_CURRENCY # Stores the player's current spendable in-game currency balance.
var _next_free_pack_unix: int = 0 # Stores the UTC Unix timestamp when the next free pack becomes claimable.
var _owned_sticker_counts: Dictionary[String, int] = {} # Stores persistent ownership counts keyed by sticker resource path so duplicates remain meaningful.
var _random_number_generator: RandomNumberGenerator = RandomNumberGenerator.new() # Owns pack randomness without relying on global random-number state.

func initialize() -> void: # Initializes random generation and loads persistent economy state before the shop becomes interactive.
	_random_number_generator.randomize() # Seeds this economy instance from the operating system for independent pack draws each run.
	_load_or_create_save() # Restores progression or creates a clean first-run save when none exists.

func get_currency() -> int: # Exposes the player's current spendable in-game currency.
	return _currency # Returns the protected currency balance without exposing write access.

func get_pack_price() -> int: # Exposes the configured normal-pack purchase price for interface text and affordability checks.
	return PACK_PRICE # Returns the single economy authority for pack pricing.

func get_pack_size() -> int: # Exposes the number of stickers granted by every pack.
	return PACK_SIZE # Returns the single economy authority for pack contents count.

func add_currency(amount: int) -> void: # Adds positive game-earned currency and persists the updated balance for future gameplay rewards.
	if amount <= 0: # Rejects zero or negative rewards so callers cannot use this method to bypass spending rules.
		return # Leaves progression unchanged for invalid reward requests.
	_currency += amount # Applies the earned amount to the persistent balance.
	_save() # Persists the reward immediately so currency survives closing the game.

func can_buy_pack(catalog: StickerCatalog) -> bool: # Reports whether a normal pack purchase can succeed right now.
	return not catalog.is_empty() and _currency >= PACK_PRICE # Requires both available sticker content and enough in-game currency.

func buy_pack(catalog: StickerCatalog) -> PackedStringArray: # Purchases, grants, and persists one normal five-sticker pack as one atomic economy operation.
	if not can_buy_pack(catalog): # Rejects purchases that lack funds or pack-eligible sticker content.
		return PackedStringArray() # Returns no contents when the purchase cannot be completed.
	_currency -= PACK_PRICE # Deducts the pack cost before granting contents so the saved transaction remains internally consistent.
	var pack: PackedStringArray = catalog.create_random_pack(PACK_SIZE, _random_number_generator) # Draws the configured number of independent random stickers from the current catalogue.
	_grant_pack(pack) # Adds every drawn sticker to persistent ownership counts including duplicate copies.
	_save() # Persists currency and inventory together after the completed transaction.
	return pack # Returns the actual pack draw so the interface can reveal the acquired artwork.

func can_claim_free_pack(catalog: StickerCatalog) -> bool: # Reports whether the free real-world cooldown pack can be claimed now.
	return not catalog.is_empty() and get_free_pack_seconds_remaining() <= 0 # Requires available content and an elapsed saved cooldown timestamp.

func claim_free_pack(catalog: StickerCatalog) -> PackedStringArray: # Grants one free five-sticker pack and starts the next real-world cooldown.
	if not can_claim_free_pack(catalog): # Rejects early claims or claims when no pack content exists.
		return PackedStringArray() # Returns no contents without modifying the saved cooldown.
	var current_unix_time: int = _get_current_unix_time() # Captures one consistent UTC timestamp for the complete claim transaction.
	var pack: PackedStringArray = catalog.create_random_pack(PACK_SIZE, _random_number_generator) # Draws the same configured pack size used by purchased packs.
	_grant_pack(pack) # Adds the free pack contents to persistent ownership counts.
	_next_free_pack_unix = current_unix_time + FREE_PACK_COOLDOWN_SECONDS # Stores the exact future UTC timestamp when another free pack becomes eligible.
	_save() # Persists inventory and cooldown together so restarting cannot reset the waiting period.
	return pack # Returns the claimed contents for the same visual reveal path used by purchased packs.

func get_free_pack_seconds_remaining() -> int: # Returns the whole number of real-world seconds remaining before the next free claim.
	var seconds_remaining: int = _next_free_pack_unix - _get_current_unix_time() # Compares the saved UTC eligibility timestamp against the current system UTC Unix time.
	return maxi(seconds_remaining, 0) # Clamps elapsed cooldowns to zero so interface callers never receive negative time.

func get_owned_count(sticker_path: String) -> int: # Returns how many copies of one sticker the player currently owns.
	return maxi(int(_owned_sticker_counts.get(sticker_path, 0)), 0) # Reads the persistent path-keyed count while protecting callers from malformed negative data.

func get_total_owned_count() -> int: # Returns the total number of sticker copies collected across all designs.
	var total_owned: int = 0 # Accumulates every validated ownership count.
	for sticker_path: String in _owned_sticker_counts: # Visits every sticker design currently represented in the save file.
		total_owned += maxi(_owned_sticker_counts[sticker_path], 0) # Adds the number of owned copies while ignoring malformed negative values.
	return total_owned # Returns the complete duplicate-inclusive collection size.

func get_unique_owned_count() -> int: # Returns how many distinct sticker designs currently have at least one owned copy.
	var unique_owned: int = 0 # Accumulates only sticker designs with positive ownership.
	for sticker_path: String in _owned_sticker_counts: # Visits every persisted sticker design key.
		if _owned_sticker_counts[sticker_path] > 0: # Counts a design only when at least one usable copy exists.
			unique_owned += 1 # Adds the positively owned design to the distinct collection total.
	return unique_owned # Returns the duplicate-independent collection size.

func _grant_pack(pack: PackedStringArray) -> void: # Adds all drawn pack contents to the player's persistent duplicate-aware sticker inventory.
	for sticker_path: String in pack: # Processes every pack slot independently so duplicate draws increase ownership multiple times.
		var current_count: int = maxi(int(_owned_sticker_counts.get(sticker_path, 0)), 0) # Reads the existing validated ownership count for the drawn design.
		_owned_sticker_counts[sticker_path] = current_count + 1 # Grants one additional physical copy of the drawn sticker.

func _load_or_create_save() -> void: # Restores progression from disk or establishes first-run defaults when no valid save is available.
	_reset_to_defaults() # Starts from known safe values so any load failure has deterministic fallback state.
	if not FileAccess.file_exists(SAVE_PATH): # Detects first run before attempting to open a nonexistent progression file.
		_save() # Creates the initial writable save immediately so future transactions have established storage.
		return # Keeps the initialized defaults after creating the first-run save.
	var save_file: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.READ) # Opens the per-user progression file for a single sequential read.
	if save_file == null: # Detects operating-system or filesystem failures without losing the safe in-memory defaults.
		push_error("could not read sticker progression save") # Reports the persistence failure for debugging without crashing gameplay.
		return # Continues the session with defaults rather than using uninitialized state.
	var parsed_data: Variant = JSON.parse_string(save_file.get_as_text()) # Parses the complete small progression document directly into Godot variants.
	if parsed_data is not Dictionary: # Rejects corrupt or incompatible save content that does not contain an object root.
		push_warning("sticker progression save was invalid and has been reset") # Reports recovery so malformed user data is visible during development.
		_save() # Replaces the invalid document with the current valid default structure.
		return # Keeps the safe defaults already initialized in memory.
	var save_data: Dictionary = parsed_data # Narrows the validated JSON root for strongly typed dictionary access.
	_currency = maxi(int(save_data.get("currency", STARTING_CURRENCY)), 0) # Restores spendable currency while preventing malformed negative balances.
	_next_free_pack_unix = maxi(int(save_data.get("next_free_pack_unix", 0)), 0) # Restores the absolute free-pack eligibility timestamp across game sessions.
	var saved_owned_stickers: Variant = save_data.get("owned_stickers", {}) # Retrieves the persisted duplicate-aware inventory object for validation.
	if saved_owned_stickers is Dictionary: # Accepts inventory only when the JSON field has the expected object structure.
		var owned_dictionary: Dictionary = saved_owned_stickers # Narrows the validated ownership object for controlled reconstruction.
		for sticker_path: Variant in owned_dictionary.keys(): # Visits every saved ownership key without trusting its dynamic JSON type blindly.
			var normalized_path: String = str(sticker_path) # Converts JSON object keys into the resource path representation used by the catalogue.
			var owned_count: int = maxi(int(owned_dictionary.get(sticker_path, 0)), 0) # Restores each duplicate count while rejecting malformed negatives.
			if not normalized_path.is_empty() and owned_count > 0: # Keeps only meaningful persistent collection entries.
				_owned_sticker_counts[normalized_path] = owned_count # Restores the validated owned copies for the sticker design.

func _save() -> void: # Persists the complete economy state as one small JSON transaction in Godot's user data directory.
	var save_file: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.WRITE) # Opens the progression file for replacement with the newest authoritative state.
	if save_file == null: # Detects a filesystem failure before attempting to serialize progression.
		push_error("could not write sticker progression save") # Reports the persistence failure without interrupting the running simulation.
		return # Leaves the valid in-memory state available for the current session.
	var save_data: Dictionary = { # Collects all persistent economy fields into one versioned document.
		"version": SAVE_VERSION, # Records the file structure version for future migration logic.
		"currency": _currency, # Persists the current spendable in-game currency balance.
		"next_free_pack_unix": _next_free_pack_unix, # Persists the absolute UTC eligibility timestamp rather than a session-relative timer.
		"owned_stickers": _owned_sticker_counts.duplicate(true), # Persists duplicate-aware sticker ownership without sharing the mutable runtime dictionary reference.
	} # Completes the small serializable progression object.
	save_file.store_string(JSON.stringify(save_data, "\t")) # Writes human-readable JSON for straightforward debugging and future migration work.

func _reset_to_defaults() -> void: # Restores safe first-run progression values before loading or after future explicit reset flows.
	_currency = STARTING_CURRENCY # Restores the configured initial in-game balance.
	_next_free_pack_unix = 0 # Makes the first free pack immediately eligible on a fresh progression state.
	_owned_sticker_counts.clear() # Removes all previously held inventory entries from the in-memory state.

func _get_current_unix_time() -> int: # Returns the current real-world UTC Unix timestamp used exclusively for cross-session free-pack eligibility.
	return int(Time.get_unix_time_from_system()) # Converts Godot's sub-second system Unix time to whole seconds for compact persistent cooldown arithmetic.
