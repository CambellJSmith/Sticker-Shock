class_name StickerEconomy
extends RefCounted

const SAVE_PATH: String = "user://sticker_progress.json" # Stores persistent player progression in Godot's writable per-user data directory.
const SAVE_VERSION: int = 3 # Identifies progression containing separate normal and special-edition ownership keys.
const STARTING_CURRENCY: int = 500 # Defines the initial in-game currency granted when no progression save exists.
const PACK_PRICE: int = 100 # Defines the in-game currency cost shared by every purchasable sticker pack.
const PACK_SIZE: int = 5 # Defines how many independently drawn stickers every normal or free pack grants.
const FREE_PACK_COOLDOWN_SECONDS: int = 6 * 60 * 60 # Defines the real-world cooldown applied after claiming a free pack.

var _currency: int = STARTING_CURRENCY # Stores the player's current spendable in-game currency balance.
var _next_free_pack_unix: int = 0 # Stores the UTC Unix timestamp when the next free pack becomes claimable.
var _owned_sticker_counts: Dictionary[String, int] = {} # Stores ownership by per-copy edition identity so normal and special copies remain distinct.
var _redeemed_unique_ids: Dictionary[int, bool] = {} # Stores Unique sticker IDs already claimed through their exact case-sensitive codes.
var _selected_pack_name: String = "" # Stores the authored pack currently selected for the next paid purchase.
var _random_number_generator: RandomNumberGenerator = RandomNumberGenerator.new() # Owns pack and special-edition randomness without relying on global random-number state.

func initialize() -> void: # Initializes random generation and loads persistent economy state before the shop becomes interactive.
	_random_number_generator.randomize() # Seeds this economy instance from the operating system for independent pack draws each run.
	_load_or_create_save() # Restores progression or creates a clean first-run save when none exists.
	SteamAchievements.sync_first_sticker(get_total_owned_count()) # Reconciles existing collections so players who already own stickers receive the newly introduced achievement.

func get_currency() -> int: # Exposes the player's current spendable in-game currency.
	return _currency # Returns the protected currency balance without exposing write access.

func get_pack_price() -> int: # Exposes the configured normal-pack purchase price for interface text and affordability checks.
	return PACK_PRICE # Returns the single economy authority shared by every authored pack.

func get_pack_size() -> int: # Exposes the number of stickers granted by every pack.
	return PACK_SIZE # Returns the single economy authority for pack contents count.

func set_selected_pack_name(pack_name: String, catalog: StickerCatalog) -> void: # Updates the paid-purchase target only when the catalogue confirms the authored pack can generate normal pulls.
	_selected_pack_name = pack_name if catalog.has_normal_pack(pack_name) else "" # Stores a valid selected pack or clears stale selection when content changes.

func get_selected_pack_name() -> String: # Exposes the current paid-purchase pack selection for shop presentation.
	return _selected_pack_name # Returns the controlled authored pack name without exposing mutation.

func add_currency(amount: int) -> void: # Adds positive game-earned currency and persists the updated balance for future gameplay rewards.
	if amount <= 0: # Rejects zero or negative rewards so callers cannot use this method to bypass spending rules.
		return # Leaves progression unchanged for invalid reward requests.
	_currency += amount # Applies the earned amount to the persistent balance.
	_save() # Persists the reward immediately so currency survives closing the game.

func can_buy_pack(catalog: StickerCatalog) -> bool: # Reports whether the currently selected normal pack purchase can succeed right now.
	return _currency >= PACK_PRICE and catalog.has_normal_pack(_selected_pack_name) # Requires sufficient currency and one valid authored paid-pack selection.

func buy_pack(catalog: StickerCatalog) -> PackedStringArray: # Purchases, grants, and persists one selected five-sticker pack with independent special-edition rolls.
	if not can_buy_pack(catalog): # Rejects purchases that lack funds or a valid selected authored pack.
		return PackedStringArray() # Returns no contents when the purchase cannot be completed.
	var base_pack: PackedStringArray = catalog.create_random_pack(PACK_SIZE, _random_number_generator, _selected_pack_name) # Draws authored designs using the configured rarity weights.
	if base_pack.size() != PACK_SIZE: # Protects currency from being deducted if malformed content cannot produce a complete pack.
		return PackedStringArray() # Returns no contents without modifying persistent progression.
	var pack: PackedStringArray = _apply_special_rolls(base_pack) # Gives every individual pull its independent one-percent special-edition chance after design selection.
	_currency -= PACK_PRICE # Deducts the common pack cost only after a complete selected-pack draw exists.
	_grant_pack(pack) # Adds every normal or special copy to persistent edition-aware ownership counts.
	_save() # Persists currency and inventory together after the completed transaction.
	return pack # Returns edition-aware identities so reveal and collection presentation preserve special copies.

func can_claim_free_pack(catalog: StickerCatalog) -> bool: # Reports whether the random free real-world cooldown pack can be claimed now.
	return not catalog.get_pack_names().is_empty() and get_free_pack_seconds_remaining() <= 0 # Requires at least one normal authored pack and an elapsed saved cooldown timestamp.

func claim_free_pack(catalog: StickerCatalog) -> PackedStringArray: # Grants one free five-sticker pack from a randomly selected authored pack with independent special-edition rolls.
	if not can_claim_free_pack(catalog): # Rejects early claims or claims when no normal authored pack content exists.
		return PackedStringArray() # Returns no contents without modifying the saved cooldown.
	var pack_names: PackedStringArray = catalog.get_pack_names() # Reads every authored pack that can currently produce normal weighted draws.
	var random_pack_index: int = _random_number_generator.randi_range(0, pack_names.size() - 1) # Chooses one available authored pack independently for this six-hour reward.
	var random_pack_name: String = pack_names[random_pack_index] # Resolves the exact authored pack selected for the current free claim.
	var base_pack: PackedStringArray = catalog.create_random_pack(PACK_SIZE, _random_number_generator, random_pack_name) # Draws all free-pack designs from the one randomly selected authored pack.
	if base_pack.size() != PACK_SIZE: # Protects the cooldown from starting if malformed content cannot produce a complete free pack.
		return PackedStringArray() # Leaves progression unchanged when a complete reward cannot be granted.
	var pack: PackedStringArray = _apply_special_rolls(base_pack) # Rolls specialness independently for every granted copy rather than treating special as a rarity tier.
	var current_unix_time: int = _get_current_unix_time() # Captures one consistent UTC timestamp for the complete claim transaction.
	_grant_pack(pack) # Adds the free pack contents to persistent edition-aware ownership counts.
	_next_free_pack_unix = current_unix_time + FREE_PACK_COOLDOWN_SECONDS # Stores the exact future UTC timestamp when another free pack becomes eligible.
	_save() # Persists inventory and cooldown together so restarting cannot reset the waiting period.
	return pack # Returns edition-aware identities for the same reveal-only shop path used by purchased packs.

func redeem_unique_code(catalog: StickerCatalog, code: String) -> String: # Grants one normal-edition Unique sticker when its exact case-sensitive authored Name is entered for the first time.
	var sticker_path: String = catalog.get_unique_sticker_path_by_code(code) # Resolves only exact case-sensitive Unique Name matches through the authoritative catalogue.
	if sticker_path.is_empty(): # Rejects unknown codes without changing ownership or redemption state.
		return "" # Returns no sticker identity for an invalid code.
	var sticker_id: int = catalog.get_sticker_id(sticker_path) # Resolves the persistent numerical identity used to prevent repeated claims.
	if sticker_id <= 0 or _redeemed_unique_ids.has(sticker_id): # Rejects malformed definitions and Unique codes already redeemed on this save.
		return "" # Returns no reward when the code has already been claimed.
	_grant_sticker(sticker_path) # Code redemption is not a pack pull, so it grants the normal edition directly.
	_redeemed_unique_ids[sticker_id] = true # Permanently records this Unique code claim independently from general ownership counts.
	_save() # Persists the granted sticker and one-time redemption marker atomically.
	return sticker_path # Returns the exact normal-edition rewarded identity for reveal and collection flow.

func has_redeemed_unique(sticker_id: int) -> bool: # Reports whether one Unique sticker ID has already been claimed through its code.
	return sticker_id > 0 and _redeemed_unique_ids.has(sticker_id) # Returns true only for a valid ID recorded in persistent redemption state.

func get_free_pack_seconds_remaining() -> int: # Returns the whole number of real-world seconds remaining before the next free claim.
	var seconds_remaining: int = _next_free_pack_unix - _get_current_unix_time() # Compares the saved UTC eligibility timestamp against the current system UTC Unix time.
	return maxi(seconds_remaining, 0) # Clamps elapsed cooldowns to zero so interface callers never receive negative time.

func get_owned_count(sticker_key: String) -> int: # Returns how many copies of one exact normal or special edition the player owns.
	return maxi(int(_owned_sticker_counts.get(sticker_key, 0)), 0) # Reads the persistent edition-aware count while protecting callers from malformed negative data.

func get_total_owned_count() -> int: # Returns the total number of sticker copies collected across all designs and editions.
	var total_owned: int = 0 # Accumulates every validated ownership count.
	for sticker_key: String in _owned_sticker_counts: # Visits every normal and special edition represented in the save file.
		total_owned += maxi(_owned_sticker_counts[sticker_key], 0) # Adds the number of owned copies while ignoring malformed negative values.
	return total_owned # Returns the complete duplicate-inclusive collection size.

func get_unique_owned_count() -> int: # Returns how many distinct authored sticker designs have at least one normal or special copy.
	var discovered_paths: Dictionary[String, bool] = {} # Collapses edition identities back to their authored design for completion progress.
	for sticker_key: String in _owned_sticker_counts: # Visits every persisted edition identity.
		if _owned_sticker_counts[sticker_key] > 0: # Ignores empty or malformed inventory entries.
			discovered_paths[StickerVariant.get_art_path(sticker_key)] = true # Counts a special-only discovery as discovery of that underlying sticker design.
	return discovered_paths.size() # Returns collection completion independently from optional special variants.

func _apply_special_rolls(base_pack: PackedStringArray) -> PackedStringArray: # Converts authored design pulls into exact per-copy edition identities.
	var result: PackedStringArray = PackedStringArray() # Allocates one compact edition-aware result in the original pull order.
	for sticker_path: String in base_pack: # Processes every pull independently so duplicates can differ in specialness inside the same pack.
		var special: bool = _random_number_generator.randf() < StickerVariant.SPECIAL_PULL_CHANCE # Applies an exact independent one-percent Bernoulli roll after the sticker design is already chosen.
		result.append(StickerVariant.make_key(sticker_path, special)) # Stores the edition directly in the copy identity used by persistence and presentation.
	return result # Returns the complete normal/special pack without changing rarity probabilities.

func _grant_pack(pack: PackedStringArray) -> void: # Adds all edition-aware pack contents to the player's persistent duplicate-aware sticker inventory.
	for sticker_key: String in pack: # Processes every pack slot independently so duplicate editions increase ownership multiple times.
		_grant_sticker(sticker_key) # Reuses the one-copy grant path for consistent edition-aware ownership updates.

func _grant_sticker(sticker_key: String) -> void: # Adds exactly one physical copy of a normal or special sticker identity to persistent ownership.
	var collection_was_empty: bool = get_total_owned_count() <= 0 # Detects the exact zero-to-one collection transition before mutating ownership.
	var current_count: int = maxi(int(_owned_sticker_counts.get(sticker_key, 0)), 0) # Reads the existing validated ownership count for the exact edition.
	_owned_sticker_counts[sticker_key] = current_count + 1 # Grants one additional physical copy of that edition.
	if collection_was_empty: # Awards the achievement only for the first physical sticker transition rather than every pack slot.
		SteamAchievements.sync_first_sticker(1) # Reports the earned condition immediately while the sticker grant remains the single authoritative acquisition path.

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
		for sticker_key_variant: Variant in owned_dictionary.keys(): # Visits every saved ownership key without trusting its dynamic JSON type blindly.
			var sticker_key: String = str(sticker_key_variant) # Converts JSON object keys into the edition identity representation used at runtime.
			var owned_count: int = maxi(int(owned_dictionary.get(sticker_key_variant, 0)), 0) # Restores each duplicate count while rejecting malformed negatives.
			if not sticker_key.is_empty() and owned_count > 0: # Keeps only meaningful persistent collection entries.
				_owned_sticker_counts[sticker_key] = owned_count # Restores legacy normal paths and new special-suffixed keys without migration loss.
	var saved_redeemed_unique_ids: Variant = save_data.get("redeemed_unique_ids", []) # Retrieves one-time Unique code claims while remaining backward-compatible with older saves.
	if saved_redeemed_unique_ids is Array: # Accepts redemption state only when the JSON field has the expected array structure.
		for saved_id: Variant in saved_redeemed_unique_ids: # Visits each persisted numerical Unique sticker identifier once.
			var sticker_id: int = int(saved_id) # Converts JSON number variants into the strongly typed sticker identity used at runtime.
			if sticker_id > 0: # Keeps only meaningful positive sticker identifiers.
				_redeemed_unique_ids[sticker_id] = true # Restores the one-time redemption marker without altering general ownership.

func _save() -> void: # Persists the complete economy state as one small JSON transaction in Godot's user data directory.
	var save_file: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.WRITE) # Opens the progression file for replacement with the newest authoritative state.
	if save_file == null: # Detects a filesystem failure before attempting to serialize progression.
		push_error("could not write sticker progression save") # Reports the persistence failure without interrupting the running simulation.
		return # Leaves the valid in-memory state available for the current session.
	var redeemed_ids: Array[int] = [] # Builds a stable serializable list of one-time Unique sticker IDs.
	for sticker_id: int in _redeemed_unique_ids.keys(): # Copies every redeemed Unique identity out of the internal lookup.
		redeemed_ids.append(sticker_id) # Adds the positive numerical ID to the persistent array.
	redeemed_ids.sort() # Stabilizes the save representation for debugging and future migrations.
	var save_data: Dictionary = { # Collects all persistent economy fields into one versioned document.
		"version": SAVE_VERSION, # Records the file structure version for future migration logic.
		"currency": _currency, # Persists the current spendable in-game currency balance.
		"next_free_pack_unix": _next_free_pack_unix, # Persists the absolute UTC eligibility timestamp rather than a session-relative timer.
		"owned_stickers": _owned_sticker_counts.duplicate(true), # Persists normal and special ownership without sharing the mutable runtime dictionary reference.
		"redeemed_unique_ids": redeemed_ids, # Persists one-time Unique code claims independently from inventory counts.
	} # Completes the small serializable progression object.
	save_file.store_string(JSON.stringify(save_data, "\t")) # Writes human-readable JSON for straightforward debugging and future migration work.

func _reset_to_defaults() -> void: # Restores safe first-run progression values before loading or after future explicit reset flows.
	_currency = STARTING_CURRENCY # Restores the configured initial in-game balance.
	_next_free_pack_unix = 0 # Makes the first free pack immediately eligible on a fresh progression state.
	_owned_sticker_counts.clear() # Removes all previously held inventory entries from the in-memory state.
	_redeemed_unique_ids.clear() # Removes all one-time Unique code claims from the in-memory state.
	_selected_pack_name = "" # Clears the transient paid-pack selection so the shop can choose a current authored default.

func _get_current_unix_time() -> int: # Returns the current real-world UTC Unix timestamp used exclusively for cross-session free-pack eligibility.
	return int(Time.get_unix_time_from_system()) # Converts Godot's sub-second system Unix time to whole seconds for compact persistent cooldown arithmetic.
