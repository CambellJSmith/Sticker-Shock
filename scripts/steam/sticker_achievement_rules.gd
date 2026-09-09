class_name StickerAchievementRules # Evaluates Sticker-Shock achievement conditions from authoritative local progression without coupling gameplay to Steamworks calls.
extends RefCounted # Keeps the rule set allocation-free apart from small temporary collections created during explicit progression synchronization.

const FIRST_STICKER: StringName = &"STICKER_SHOCK_FIRST_STICKER" # Awards the first collected physical sticker copy.
const FIRST_PACK: StringName = &"STICKER_SHOCK_FIRST_PACK" # Awards the first successfully opened paid or free sticker pack.
const FIRST_PAID_PACK: StringName = &"STICKER_SHOCK_FIRST_PAID_PACK" # Awards the first successfully purchased sticker pack.
const FIRST_FREE_PACK: StringName = &"STICKER_SHOCK_FIRST_FREE_PACK" # Awards the first successfully claimed free sticker pack.
const FIRST_BOOK_PLACEMENT: StringName = &"STICKER_SHOCK_FIRST_BOOK_PLACEMENT" # Awards the first physical sticker committed to the persistent book.
const COLLECTION_10_PERCENT: StringName = &"STICKER_SHOCK_COLLECTION_10_PERCENT" # Awards discovery of at least ten percent of the current authored sticker catalogue.
const COLLECTION_25_PERCENT: StringName = &"STICKER_SHOCK_COLLECTION_25_PERCENT" # Awards discovery of at least one quarter of the current authored sticker catalogue.
const COLLECTION_50_PERCENT: StringName = &"STICKER_SHOCK_COLLECTION_50_PERCENT" # Awards discovery of at least half of the current authored sticker catalogue.
const COLLECTION_75_PERCENT: StringName = &"STICKER_SHOCK_COLLECTION_75_PERCENT" # Awards discovery of at least three quarters of the current authored sticker catalogue.
const COLLECTION_90_PERCENT: StringName = &"STICKER_SHOCK_COLLECTION_90_PERCENT" # Awards discovery of at least ninety percent of the current authored sticker catalogue.
const COMPLETE_COLLECTION: StringName = &"STICKER_SHOCK_COMPLETE_COLLECTION" # Awards discovery of every sticker design in the current authored catalogue.
const BOOK_25_PERCENT: StringName = &"STICKER_SHOCK_BOOK_25_PERCENT" # Awards physically filing distinct designs equal to at least one quarter of the current catalogue.
const BOOK_50_PERCENT: StringName = &"STICKER_SHOCK_BOOK_50_PERCENT" # Awards physically filing distinct designs equal to at least half of the current catalogue.
const COMPLETE_BOOK: StringName = &"STICKER_SHOCK_COMPLETE_BOOK" # Awards physically filing every current authored sticker design in the book.
const FIRST_DUPLICATE: StringName = &"STICKER_SHOCK_FIRST_DUPLICATE" # Awards owning more than one physical copy of at least one current sticker design.
const RAINBOW_EDITION: StringName = &"STICKER_SHOCK_RAINBOW_EDITION" # Awards collecting any rainbow-edition sticker.
const SILVER_EDITION: StringName = &"STICKER_SHOCK_SILVER_EDITION" # Awards collecting any silver-edition sticker.
const GOLD_EDITION: StringName = &"STICKER_SHOCK_GOLD_EDITION" # Awards collecting any gold-edition sticker.
const FULL_SPECTRUM: StringName = &"STICKER_SHOCK_FULL_SPECTRUM" # Awards owning at least one rainbow, silver, and gold sticker across the collection.
const FULL_FINISH: StringName = &"STICKER_SHOCK_FULL_FINISH" # Awards owning normal, rainbow, silver, and gold copies of the same authored design.
const LEGENDARY: StringName = &"STICKER_SHOCK_LEGENDARY" # Awards discovering any sticker authored at Legendary rarity.
const UNIQUE: StringName = &"STICKER_SHOCK_UNIQUE" # Awards discovering any sticker authored at Unique rarity.
const ALL_UNIQUES: StringName = &"STICKER_SHOCK_ALL_UNIQUES" # Awards discovering every Unique sticker currently present in the authored catalogue.
const ALL_PACKS: StringName = &"STICKER_SHOCK_ALL_PACKS" # Awards discovering at least one sticker from every currently purchasable authored pack.
const COMPLETE_ONE_PACK: StringName = &"STICKER_SHOCK_COMPLETE_ONE_PACK" # Awards discovering every random-pull design in any one current authored pack.
const ALL_RARITIES: StringName = &"STICKER_SHOCK_ALL_RARITIES" # Awards discovering at least one sticker from every rarity currently represented in the catalogue.
const FIRST_MARKET_SALE: StringName = &"STICKER_SHOCK_FIRST_MARKET_SALE" # Awards the first successful loose-copy sale at the collector exchange.

const EVENT_API_NAMES: Array[StringName] = [FIRST_PACK, FIRST_PAID_PACK, FIRST_FREE_PACK, FIRST_MARKET_SALE] # Lists event-history achievements that cannot always be reconstructed from current collection state alone.

static func is_event_api_name(api_name: StringName) -> bool: # Reports whether one achievement needs local event-history persistence for offline reconciliation.
	return EVENT_API_NAMES.has(api_name) # Accepts only the controlled event achievements authored by this rule set.

static func evaluate_progress(economy: StickerEconomy, catalog: StickerCatalog, book_state: StickerBookState) -> Array[StringName]: # Returns every state-derived achievement currently satisfied by authoritative progression and current authored content.
	var earned: Array[StringName] = [] # Stores satisfied API names without mutating Steamworks or gameplay state.
	if economy == null or catalog == null or book_state == null: # Rejects incomplete startup wiring before any progression scan.
		return earned # Returns no conditions until all authoritative models are available.
	var catalog_count: int = catalog.get_sticker_count() # Uses the live authored catalogue size so percentage milestones automatically scale when stickers are added later.
	if economy.get_total_owned_count() > 0: # Reconciles the original first-sticker achievement from persistent ownership on every startup.
		earned.append(FIRST_STICKER) # Awards the categorical first-copy milestone independently from catalogue size.
	if book_state.get_placement_count() > 0: # Reconciles the first physical filing milestone from persistent book state.
		earned.append(FIRST_BOOK_PLACEMENT) # Awards the categorical first-placement milestone.
	if catalog_count <= 0: # Prevents percentage or all-content conditions from becoming vacuously true in an empty or malformed catalogue.
		return earned # Keeps only categorical conditions that can be proven without authored sticker definitions.
	var discovered_count: int = 0 # Counts distinct current authored designs with at least one owned edition.
	var current_catalog_copy_count: int = 0 # Counts physical copies belonging to current authored designs so stale removed content cannot create a false duplicate achievement.
	var unique_total: int = 0 # Counts current authored Unique designs for the dynamically scaling all-Unique condition.
	var unique_owned: int = 0 # Counts current Unique designs actually discovered by the player.
	var has_rainbow: bool = false # Tracks whether any current design has an owned rainbow copy.
	var has_silver: bool = false # Tracks whether any current design has an owned silver copy.
	var has_gold: bool = false # Tracks whether any current design has an owned gold copy.
	var has_full_finish: bool = false # Tracks whether one current design is owned in all four supported finishes.
	var has_legendary: bool = false # Tracks whether any discovered current design has Legendary authored rarity.
	var has_unique: bool = false # Tracks whether any discovered current design has Unique authored rarity.
	var discovered_pack_names: Dictionary[String, bool] = {} # Tracks authored pack names represented by at least one discovered design.
	var catalogue_rarity_names: Dictionary[String, bool] = {} # Tracks every nonempty rarity currently authored in the catalogue.
	var discovered_rarity_names: Dictionary[String, bool] = {} # Tracks rarity bands represented by the player's discovered current designs.
	var pullable_designs_by_pack: Dictionary[String, int] = {} # Counts random-pull designs in each current pack so pack completion grows automatically with future additions.
	var discovered_pullable_designs_by_pack: Dictionary[String, int] = {} # Counts discovered random-pull designs in each current pack for dynamic one-pack completion.
	for index: int in range(catalog_count): # Scans each current authored design exactly once to derive all collection conditions in one pass.
		var sticker_path: String = catalog.get_sticker_path(index) # Resolves the canonical normal-edition artwork identity for this catalogue entry.
		if sticker_path.is_empty(): # Ignores malformed catalogue slots defensively.
			continue # Advances without allowing an invalid definition to affect achievement totals.
		var rarity_name: String = catalog.get_rarity_name(sticker_path) # Reads the authored rarity shared by every finish of this design.
		var pack_name: String = catalog.get_pack_name(sticker_path) # Reads the authored pack assignment shared by every finish of this design.
		if not rarity_name.is_empty(): # Includes only meaningful rarity labels in the dynamic rarity-coverage denominator.
			catalogue_rarity_names[rarity_name] = true # Adds the current authored rarity without hard-coding the number of rarity bands.
		var is_random_pull_design: bool = StickerCatalog.RARITY_WEIGHTS.has(rarity_name) and not pack_name.is_empty() # Matches the same weighted rarities that can actually appear in normal packs.
		if is_random_pull_design: # Counts pack-completion denominators only for designs obtainable from that pack's random draw.
			pullable_designs_by_pack[pack_name] = int(pullable_designs_by_pack.get(pack_name, 0)) + 1 # Expands this pack's target automatically when another pullable sticker is authored into it.
		var normal_count: int = economy.get_owned_count(sticker_path) # Reads owned ordinary copies of the current design.
		var rainbow_count: int = economy.get_owned_count(StickerVariant.make_edition_key(sticker_path, StickerVariant.EDITION_RAINBOW)) # Reads owned rainbow copies of the current design.
		var silver_count: int = economy.get_owned_count(StickerVariant.make_edition_key(sticker_path, StickerVariant.EDITION_SILVER)) # Reads owned silver copies of the current design.
		var gold_count: int = economy.get_owned_count(StickerVariant.make_edition_key(sticker_path, StickerVariant.EDITION_GOLD)) # Reads owned gold copies of the current design, including legacy special-suffix saves.
		var design_copy_count: int = normal_count + rainbow_count + silver_count + gold_count # Calculates physical copies of this current design across every finish.
		current_catalog_copy_count += design_copy_count # Accumulates current-content copies for duplicate detection.
		var design_discovered: bool = design_copy_count > 0 # Treats ownership of any finish as discovery of the underlying authored design.
		if rarity_name == StickerCatalog.UNIQUE_RARITY: # Counts Unique content independently from normal random-pull stickers.
			unique_total += 1 # Expands the all-Unique denominator automatically when a future Unique sticker is added.
			if design_discovered: # Credits this Unique design only when at least one copy is actually owned.
				unique_owned += 1 # Advances the dynamic all-Unique numerator.
		if not design_discovered: # Skips ownership-only metrics for undiscovered designs while retaining their catalogue denominator data above.
			continue # Advances to the next current authored sticker.
		discovered_count += 1 # Counts this design exactly once regardless of duplicate copies or premium finishes.
		if not pack_name.is_empty(): # Records pack representation only for stickers with an authored pack assignment.
			discovered_pack_names[pack_name] = true # Marks this pack represented without hard-coding current pack count.
		if not rarity_name.is_empty(): # Records rarity representation only for meaningful authored rarity labels.
			discovered_rarity_names[rarity_name] = true # Marks the rarity as collected for the dynamic all-rarities achievement.
		if is_random_pull_design: # Credits pack completion only for designs included in normal weighted draws.
			discovered_pullable_designs_by_pack[pack_name] = int(discovered_pullable_designs_by_pack.get(pack_name, 0)) + 1 # Advances this pack's dynamic completion numerator.
		has_rainbow = has_rainbow or rainbow_count > 0 # Records the first rainbow finish encountered without additional scans.
		has_silver = has_silver or silver_count > 0 # Records the first silver finish encountered without additional scans.
		has_gold = has_gold or gold_count > 0 # Records the first gold finish encountered without additional scans.
		has_full_finish = has_full_finish or (normal_count > 0 and rainbow_count > 0 and silver_count > 0 and gold_count > 0) # Detects one design represented in every currently supported finish.
		has_legendary = has_legendary or rarity_name == "Legendary" # Detects discovery of the established top random-pull rarity.
		has_unique = has_unique or rarity_name == StickerCatalog.UNIQUE_RARITY # Detects discovery of any code/custom-system Unique sticker.
	_append_fraction_achievement(earned, COLLECTION_10_PERCENT, discovered_count, catalog_count, 1, 10) # Awards ten-percent discovery using exact integer ratio comparison against the current catalogue.
	_append_fraction_achievement(earned, COLLECTION_25_PERCENT, discovered_count, catalog_count, 1, 4) # Awards quarter completion against the current catalogue size.
	_append_fraction_achievement(earned, COLLECTION_50_PERCENT, discovered_count, catalog_count, 1, 2) # Awards half completion against the current catalogue size.
	_append_fraction_achievement(earned, COLLECTION_75_PERCENT, discovered_count, catalog_count, 3, 4) # Awards three-quarter completion against the current catalogue size.
	_append_fraction_achievement(earned, COLLECTION_90_PERCENT, discovered_count, catalog_count, 9, 10) # Awards ninety-percent completion against the current catalogue size.
	if discovered_count >= catalog_count: # Requires every current authored design rather than a fixed historical sticker count.
		earned.append(COMPLETE_COLLECTION) # Awards full collection completion for the catalogue version the player is currently running.
	var placed_designs: Dictionary[String, bool] = _get_placed_current_designs(book_state, catalog) # Collapses physical book copies and finishes to distinct current authored designs.
	var placed_design_count: int = placed_designs.size() # Uses distinct designs so duplicate placement cannot shortcut book-completion milestones.
	_append_fraction_achievement(earned, BOOK_25_PERCENT, placed_design_count, catalog_count, 1, 4) # Awards quarter-book filing against the current catalogue size.
	_append_fraction_achievement(earned, BOOK_50_PERCENT, placed_design_count, catalog_count, 1, 2) # Awards half-book filing against the current catalogue size.
	if placed_design_count >= catalog_count: # Requires a physical book placement representing every current authored sticker design.
		earned.append(COMPLETE_BOOK) # Awards the fully filed dynamic catalogue milestone.
	if current_catalog_copy_count > discovered_count: # Detects at least one extra physical copy beyond the one-per-discovered-design minimum.
		earned.append(FIRST_DUPLICATE) # Awards owning a duplicate without imposing a fixed cumulative duplicate target.
	if has_rainbow: # Detects any current rainbow-edition ownership.
		earned.append(RAINBOW_EDITION) # Awards the rainbow finish milestone.
	if has_silver: # Detects any current silver-edition ownership.
		earned.append(SILVER_EDITION) # Awards the silver finish milestone.
	if has_gold: # Detects any current gold-edition ownership.
		earned.append(GOLD_EDITION) # Awards the gold finish milestone.
	if has_rainbow and has_silver and has_gold: # Requires representation of every premium finish currently implemented by StickerVariant.
		earned.append(FULL_SPECTRUM) # Awards premium-finish breadth without tying the condition to catalogue size.
	if has_full_finish: # Requires all four finishes of one underlying authored design.
		earned.append(FULL_FINISH) # Awards the single-design finish set milestone.
	if has_legendary: # Detects any discovered Legendary design.
		earned.append(LEGENDARY) # Awards the top normal-rarity discovery milestone.
	if has_unique: # Detects any discovered Unique design.
		earned.append(UNIQUE) # Awards the first Unique discovery milestone.
	if unique_total > 0 and unique_owned >= unique_total: # Avoids vacuous completion when no Unique stickers exist and scales automatically with future Unique additions.
		earned.append(ALL_UNIQUES) # Awards collection of every current Unique design.
	if _has_all_current_packs(discovered_pack_names, catalog.get_pack_names()): # Compares represented packs with the catalogue's current purchasable pack list.
		earned.append(ALL_PACKS) # Awards breadth across every current authored random-pull pack.
	if _has_completed_any_current_pack(pullable_designs_by_pack, discovered_pullable_designs_by_pack): # Checks each pack against its own current random-pull design count.
		earned.append(COMPLETE_ONE_PACK) # Awards full discovery of any one dynamically sized authored pack.
	if _contains_every_key(discovered_rarity_names, catalogue_rarity_names): # Compares collected rarity labels with every rarity currently represented by authored sticker definitions.
		earned.append(ALL_RARITIES) # Awards dynamic rarity breadth without assuming the current rarity list can never expand.
	return earned # Returns all currently satisfied state-derived achievements for idempotent Steam reconciliation.

static func _get_placed_current_designs(book_state: StickerBookState, catalog: StickerCatalog) -> Dictionary[String, bool]: # Returns distinct current authored designs represented by at least one physical book placement.
	var placed_designs: Dictionary[String, bool] = {} # Collapses duplicate physical copies and premium finishes to canonical artwork identities.
	for placement: Dictionary in book_state.get_placements_copy(): # Reads an independent persistent layout snapshot so achievement evaluation cannot mutate book state.
		var sticker_key: String = str(placement.get("path", "")) # Reads the exact normal-or-edition identity persisted by the physical book.
		var sticker_path: String = StickerVariant.get_art_path(sticker_key) # Normalizes premium finishes back to their shared authored design.
		if sticker_path.is_empty() or catalog.get_definition(sticker_path) == null: # Rejects malformed placements and removed legacy content from current-catalogue completion.
			continue # Advances without letting stale physical records satisfy new authored-content milestones.
		placed_designs[sticker_path] = true # Counts this current design once regardless of how many copies or finishes are physically filed.
	return placed_designs # Returns the distinct current physical-book design set.

static func _append_fraction_achievement(result: Array[StringName], api_name: StringName, current_count: int, total_count: int, numerator: int, denominator: int) -> void: # Appends one dynamically scaled percentage milestone when the exact integer ratio has been reached.
	if total_count <= 0 or denominator <= 0 or numerator <= 0: # Rejects invalid ratio definitions and empty denominators defensively.
		return # Prevents malformed content or constants from creating a vacuous achievement.
	if current_count * denominator >= total_count * numerator: # Uses integer cross multiplication so thresholds behave like ceiling percentages without floating-point rounding.
		result.append(api_name) # Records the satisfied milestone using the current catalogue-derived threshold.

static func _has_all_current_packs(discovered_pack_names: Dictionary[String, bool], current_pack_names: PackedStringArray) -> bool: # Reports whether at least one discovered design represents every currently purchasable authored pack.
	if current_pack_names.is_empty(): # Avoids vacuous completion in a catalogue with no valid random-pull packs.
		return false # Requires at least one real current pack before awarding pack breadth.
	for pack_name: String in current_pack_names: # Visits the catalogue-owned current pack list without hard-coding its size.
		if not discovered_pack_names.has(pack_name): # Detects the first current pack with no discovered design.
			return false # Reports incomplete breadth immediately.
	return true # Confirms every current pack is represented in the discovered collection.

static func _has_completed_any_current_pack(pullable_designs_by_pack: Dictionary[String, int], discovered_pullable_designs_by_pack: Dictionary[String, int]) -> bool: # Reports whether all random-pull designs in at least one current authored pack have been discovered.
	for pack_name: String in pullable_designs_by_pack: # Visits every pack whose current content includes at least one random-pull design.
		var required_count: int = maxi(pullable_designs_by_pack[pack_name], 0) # Reads this pack's live authored design denominator.
		if required_count <= 0: # Ignores malformed empty pack counters defensively.
			continue # Advances to another valid current pack.
		if int(discovered_pullable_designs_by_pack.get(pack_name, 0)) >= required_count: # Requires all current pullable designs in this exact pack.
			return true # Awards as soon as any one current pack is complete.
	return false # Reports that every current pack still has at least one undiscovered random-pull design.

static func _contains_every_key(discovered: Dictionary[String, bool], expected: Dictionary[String, bool]) -> bool: # Reports whether a discovered string-key set contains every key in a nonempty current-content denominator set.
	if expected.is_empty(): # Avoids vacuous completion when no meaningful authored categories exist.
		return false # Requires at least one current expected key.
	for expected_key: String in expected: # Visits each current authored category exactly once.
		if not discovered.has(expected_key): # Detects the first category not represented in the player's collection.
			return false # Reports incomplete category coverage immediately.
	return true # Confirms every current expected category is represented.