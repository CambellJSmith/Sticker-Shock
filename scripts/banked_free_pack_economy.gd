class_name BankedFreePackEconomy
extends GuaranteedSpecialStickerEconomy

const BANK_SAVE_PATH: String = "user://sticker_free_pack_bank.json" # Stores rollover free-pack claims independently from the existing progression save.
const MAX_BANKED_FREE_PACKS: int = 5 # Caps unclaimed free packs so the player can save several rewards without unlimited accumulation.

var _banked_free_packs: int = 0 # Stores how many free pack claims are currently ready to use.
var _next_banked_pack_unix: int = 0 # Stores when the next banked claim will be earned while the bank is below its cap.

func initialize() -> void: # Restores the normal economy and edition guarantees before rebuilding the rollover bank.
	super.initialize() # Loads currency, inventory, paid-pack pricing state, and premium-edition milestone progress.
	_load_or_create_bank_state() # Restores the dedicated bank or migrates the previous single-cooldown state.
	_sync_free_pack_bank() # Credits any six-hour intervals that elapsed while the game was closed.

func get_free_pack_count() -> int: # Returns the current number of free pack claims ready to use.
	_sync_free_pack_bank() # Applies any elapsed real-world accrual before exposing the bank count.
	return _banked_free_packs # Returns the bounded ready-to-claim total.

func get_max_free_pack_count() -> int: # Exposes the rollover cap for player-facing UI.
	return MAX_BANKED_FREE_PACKS # Returns the fixed maximum number of stored free packs.

func can_claim_free_pack(catalog: StickerCatalog) -> bool: # Reports whether at least one banked reward can currently be opened.
	_sync_free_pack_bank() # Credits elapsed six-hour intervals before checking availability.
	return _banked_free_packs > 0 and not catalog.get_pack_names().is_empty() # Requires one stored claim and at least one valid authored pack.

func claim_free_pack(catalog: StickerCatalog) -> PackedStringArray: # Consumes one stored claim and grants one random authored five-sticker pack.
	_sync_free_pack_bank() # Ensures the ready count is current before the transaction begins.
	if _banked_free_packs <= 0 or catalog.get_pack_names().is_empty(): # Rejects claims when the bank is empty or no pack content exists.
		return PackedStringArray() # Leaves inventory and bank state unchanged on an invalid claim.
	var pack_names: PackedStringArray = catalog.get_pack_names() # Reads every authored pack eligible for a normal random free reward.
	var random_pack_index: int = _random_number_generator.randi_range(0, pack_names.size() - 1) # Selects one authored pack uniformly for this free claim.
	var random_pack_name: String = pack_names[random_pack_index] # Resolves the exact selected pack name for the draw.
	var base_pack: PackedStringArray = catalog.create_random_pack(PACK_SIZE, _random_number_generator, random_pack_name) # Draws the same number of stickers and rarity distribution as paid packs.
	if base_pack.size() != PACK_SIZE: # Protects a stored claim if malformed content cannot produce a complete reward.
		return PackedStringArray() # Leaves the bank unchanged when the reward cannot be constructed safely.
	var pack: PackedStringArray = _apply_special_rolls(base_pack) # Applies normal rainbow, silver, gold, and lifetime milestone logic to every free pull.
	_banked_free_packs = maxi(_banked_free_packs - 1, 0) # Consumes exactly one stored free-pack claim after a valid reward exists.
	if _banked_free_packs < MAX_BANKED_FREE_PACKS and _next_banked_pack_unix <= 0: # Restarts accrual when claiming from a previously full bank.
		_next_banked_pack_unix = _get_current_unix_time() + FREE_PACK_COOLDOWN_SECONDS # Schedules the next six-hour reward from the time capacity becomes available.
	_grant_pack(pack) # Adds every exact edition copy to persistent ownership.
	_save() # Persists the granted stickers through the established progression save.
	_save_bank_state() # Persists the consumed claim and next accrual timestamp atomically enough for the dedicated bank state.
	return pack # Returns edition-aware sticker identities for the existing reveal-only shop presentation.

func get_free_pack_seconds_remaining() -> int: # Returns time until the next banked claim, or zero when at least one claim is already ready.
	_sync_free_pack_bank() # Applies elapsed accrual before calculating player-facing timing.
	if _banked_free_packs > 0: # Treats any stored reward as immediately claimable regardless of the next accrual timer.
		return 0 # Keeps existing ready-state callers compatible.
	if _next_banked_pack_unix <= 0: # Handles a defensive missing timer while the bank is not full.
		_next_banked_pack_unix = _get_current_unix_time() + FREE_PACK_COOLDOWN_SECONDS # Repairs the timer from the current real-world moment.
		_save_bank_state() # Persists the repaired accrual schedule.
	return maxi(_next_banked_pack_unix - _get_current_unix_time(), 0) # Returns a nonnegative whole-second countdown.

func get_seconds_until_additional_free_pack() -> int: # Returns the timer for another banked claim even when one or more rewards are already ready.
	_sync_free_pack_bank() # Applies elapsed accrual before exposing the next interval.
	if _banked_free_packs >= MAX_BANKED_FREE_PACKS: # Stops accumulation while the rollover bank is full.
		return 0 # Reports no active countdown until capacity is freed by a claim.
	if _next_banked_pack_unix <= 0: # Repairs a missing timer while capacity remains available.
		_next_banked_pack_unix = _get_current_unix_time() + FREE_PACK_COOLDOWN_SECONDS # Starts a fresh six-hour accrual interval.
		_save_bank_state() # Persists the repaired next-reward timestamp.
	return maxi(_next_banked_pack_unix - _get_current_unix_time(), 0) # Returns the active countdown toward the next stored claim.

func _sync_free_pack_bank() -> void: # Converts elapsed real-world six-hour intervals into stored claims up to the rollover cap.
	if _banked_free_packs >= MAX_BANKED_FREE_PACKS: # Detects a full bank before doing timestamp arithmetic.
		_banked_free_packs = MAX_BANKED_FREE_PACKS # Clamps any malformed over-cap state back to the supported maximum.
		_next_banked_pack_unix = 0 # Pauses accrual completely while no storage capacity remains.
		return # Leaves the full bank unchanged until the player claims one.
	var now: int = _get_current_unix_time() # Reads one consistent UTC timestamp for the complete accrual calculation.
	if _next_banked_pack_unix <= 0: # Establishes a valid timer when none is currently running.
		_next_banked_pack_unix = now + FREE_PACK_COOLDOWN_SECONDS # Starts the next six-hour interval from the current moment.
		_save_bank_state() # Persists the newly established timer once.
		return # Leaves the current bank count unchanged until that interval elapses.
	if now < _next_banked_pack_unix: # Detects that the next reward has not yet matured.
		return # Avoids unnecessary persistence while no bank state changed.
	var elapsed_after_due: int = now - _next_banked_pack_unix # Measures complete time elapsed after the first currently due claim.
	var earned_packs: int = 1 + int(elapsed_after_due / FREE_PACK_COOLDOWN_SECONDS) # Converts the due claim plus subsequent complete intervals into rollover rewards.
	var available_slots: int = MAX_BANKED_FREE_PACKS - _banked_free_packs # Calculates remaining bank capacity before applying elapsed rewards.
	var credited_packs: int = mini(earned_packs, available_slots) # Limits accrual to the five-pack rollover cap.
	_banked_free_packs += credited_packs # Adds all rewards that fit in the bank in one constant-time catch-up step.
	if _banked_free_packs >= MAX_BANKED_FREE_PACKS: # Detects that catch-up filled the bank completely.
		_next_banked_pack_unix = 0 # Pauses further accrual until at least one stored pack is claimed.
	else: # Preserves exact wall-clock cadence when the bank still has room after catch-up.
		_next_banked_pack_unix += credited_packs * FREE_PACK_COOLDOWN_SECONDS # Advances the due timestamp by the number of intervals actually credited.
	_save_bank_state() # Persists the updated bank and next accrual timestamp after any earned reward.

func _load_or_create_bank_state() -> void: # Restores banked rewards or migrates the previous one-pack cooldown without losing entitlement.
	_banked_free_packs = 0 # Starts from a safe empty bank before reading disk state.
	_next_banked_pack_unix = 0 # Starts without an accrual timer before migration or restoration.
	if not FileAccess.file_exists(BANK_SAVE_PATH): # Detects the first run after introducing rollover free packs.
		_migrate_legacy_free_pack_state() # Converts the existing single cooldown into an equivalent bank/timer state.
		_save_bank_state() # Persists the migrated state immediately so future launches use the dedicated format.
		return # Leaves migration results active for the current session.
	var save_file: FileAccess = FileAccess.open(BANK_SAVE_PATH, FileAccess.READ) # Opens the compact rollover state for one sequential read.
	if save_file == null: # Detects filesystem access failure without damaging core progression.
		_migrate_legacy_free_pack_state() # Falls back to the legacy cooldown as the best available entitlement source.
		return # Continues with safe in-memory rollover state.
	var parsed_data: Variant = JSON.parse_string(save_file.get_as_text()) # Parses the small bank document into Godot variants.
	if parsed_data is not Dictionary: # Rejects malformed rollover data.
		_migrate_legacy_free_pack_state() # Reconstructs from the compatible legacy cooldown rather than discarding possible entitlement.
		_save_bank_state() # Replaces malformed data with the current valid structure.
		return # Continues with the rebuilt bank.
	var save_data: Dictionary = parsed_data as Dictionary # Narrows the validated document for strongly typed field access.
	_banked_free_packs = clampi(int(save_data.get("banked_free_packs", 0)), 0, MAX_BANKED_FREE_PACKS) # Restores only a valid bounded ready count.
	_next_banked_pack_unix = maxi(int(save_data.get("next_banked_pack_unix", 0)), 0) # Restores a nonnegative UTC next-accrual timestamp.
	if _banked_free_packs >= MAX_BANKED_FREE_PACKS: # Normalizes full banks from any older or manually edited state.
		_next_banked_pack_unix = 0 # Keeps accrual paused while the bank is full.

func _migrate_legacy_free_pack_state() -> void: # Converts the old ready-or-cooldown model into the new rollover bank without granting phantom packs.
	var now: int = _get_current_unix_time() # Reads the current UTC timestamp once for migration.
	if _next_free_pack_unix <= 0: # Treats a fresh/legacy save with no active cooldown as one immediately available free pack.
		_banked_free_packs = 1 # Preserves the old system's initial ready state.
		_next_banked_pack_unix = now + FREE_PACK_COOLDOWN_SECONDS # Starts accrual toward a second stored pack from migration time.
		return # Completes the no-cooldown migration path.
	if _next_free_pack_unix > now: # Preserves an old cooldown that has not yet matured.
		_banked_free_packs = 0 # Leaves no ready claim before the existing due time.
		_next_banked_pack_unix = _next_free_pack_unix # Carries the exact old eligibility timestamp into the rollover timer.
		return # Completes migration without changing remaining wait time.
	var elapsed_after_due: int = now - _next_free_pack_unix # Measures how long the previous single free pack has been ready.
	var earned_packs: int = 1 + int(elapsed_after_due / FREE_PACK_COOLDOWN_SECONDS) # Retroactively recognizes complete rollover intervals since the old due time.
	_banked_free_packs = mini(earned_packs, MAX_BANKED_FREE_PACKS) # Credits up to five claims from elapsed time.
	_next_banked_pack_unix = 0 if _banked_free_packs >= MAX_BANKED_FREE_PACKS else _next_free_pack_unix + earned_packs * FREE_PACK_COOLDOWN_SECONDS # Preserves cadence unless migration already fills the bank.

func _save_bank_state() -> void: # Persists the compact free-pack bank independently from core currency and collection state.
	var save_file: FileAccess = FileAccess.open(BANK_SAVE_PATH, FileAccess.WRITE) # Opens the dedicated rollover document for replacement.
	if save_file == null: # Detects filesystem failure before serialization.
		push_error("could not write free pack bank state") # Reports persistence failure without blocking current-session rewards.
		return # Leaves valid in-memory state active for the session.
	var save_data: Dictionary = {"version": 1, "banked_free_packs": _banked_free_packs, "next_banked_pack_unix": _next_banked_pack_unix} # Collects only rollover-specific persistent fields.
	save_file.store_string(JSON.stringify(save_data, "\t")) # Writes readable JSON for straightforward migration and debugging.
