class_name StickerBookState
extends RefCounted

const SAVE_PATH: String = "user://sticker_book.json" # Stores persistent physical book placements separately from the economy save.
const SAVE_VERSION: int = 3 # Identifies the canonical-orientation multi-page persistent book-layout document format.
const MULTI_PAGE_SAVE_VERSION: int = 2 # Identifies the first schema that stored explicit absolute page numbers independently from x/z position.
const CANONICAL_YAW_DEGREES: float = 0.0 # Defines the only legal resting rotation for every sticker physically attached inside the book.
const MINIMUM_PAGE_COUNT: int = 2 # Guarantees that every book always contains at least one visible left/right spread.

var _placements: Array[Dictionary] = [] # Stores every physical sticker currently attached to any book page in persistent stack order.
var _pending_stickers: Array[String] = [] # Stores pack stickers that were won but have not yet been physically attached to the book.
var _next_placement_id: int = 1 # Stores the next monotonic identifier used to update moved stickers without relying on array indices.
var _page_count: int = MINIMUM_PAGE_COUNT # Stores the total number of persistent book pages and always remains an even spread-sized value.
var _active_spread_index: int = 0 # Stores the zero-based spread currently open when the player views or places stickers in the book.

func initialize() -> void: # Restores the complete multi-page physical book layout and any unfinished pack contents from user storage.
	_load_or_create_save() # Loads the persistent document or creates a valid empty first-run state.

func has_pending_stickers() -> bool: # Reports whether a pack still contains physical stickers waiting to be attached.
	return not _pending_stickers.is_empty() # Returns true whenever at least one won sticker has not yet entered the book.

func get_pending_count() -> int: # Returns the number of won stickers still waiting for placement.
	return _pending_stickers.size() # Exposes only the current count without leaking the mutable pending array.

func get_pending_sticker(index: int) -> String: # Returns one pending sticker resource path by stable reveal-order index.
	if index < 0 or index >= _pending_stickers.size(): # Rejects invalid reveal indices safely.
		return "" # Returns no resource path for invalid pending positions.
	return _pending_stickers[index] # Returns the requested pending sticker artwork path.

func get_pending_copy() -> PackedStringArray: # Returns an independent copy of every currently pending sticker in reveal order.
	var result: PackedStringArray = PackedStringArray() # Allocates a compact caller-owned path array.
	for sticker_path: String in _pending_stickers: # Visits every pending sticker without exposing the mutable source array.
		result.append(sticker_path) # Copies the resource path into the caller-owned result.
	return result # Returns the complete pending pack snapshot.

func set_pending_pack(pack: PackedStringArray) -> bool: # Starts one unfinished physical pack only when no previous pack remains unresolved.
	if has_pending_stickers(): # Prevents multiple physical packs from being interleaved and losing reveal identity.
		return false # Rejects the new pending pack until the current five stickers are dealt with.
	_pending_stickers.clear() # Guarantees the new pack starts from a clean pending collection.
	for sticker_path: String in pack: # Copies every won sticker in reveal order including duplicate designs.
		_pending_stickers.append(sticker_path) # Persists one physical pending copy for each pack slot.
	_save() # Saves the unfinished pack immediately so closing during the reveal cannot lose physical placement work.
	return not _pending_stickers.is_empty() # Reports whether a meaningful pending pack was established.

func get_placement_count() -> int: # Returns the total number of physical sticker copies currently attached across every persistent page without allocating a layout copy.
	return _placements.size() # Exposes only the count so lightweight UI refreshes remain constant-time as the book grows.

func get_placements_copy() -> Array[Dictionary]: # Returns a deep copy of all physical book placements across every persistent page.
	var result: Array[Dictionary] = [] # Allocates a caller-owned placement array.
	for placement: Dictionary in _placements: # Visits every persisted sticker record in stable logical order.
		result.append(placement.duplicate(true)) # Copies the placement deeply so callers cannot mutate persistence accidentally.
	return result # Returns the complete independent physical layout snapshot.

func get_placements_for_spread_copy(spread_index: int) -> Array[Dictionary]: # Returns deep-copied placements belonging only to one visible left/right spread.
	var result: Array[Dictionary] = [] # Allocates a caller-owned filtered placement array.
	var normalized_spread: int = clampi(spread_index, 0, maxi(get_spread_count() - 1, 0)) # Clamps the requested spread to the current book range.
	for placement: Dictionary in _placements: # Visits every persisted physical sticker record once.
		var page_index: int = maxi(int(placement.get("page", 0)), 0) # Retrieves the absolute persistent page assigned to this sticker.
		if StickerBookLayout.get_spread_index_for_page(page_index) != normalized_spread: # Rejects stickers that belong to another virtual spread.
			continue # Advances without copying hidden pages into the visible spread result.
		result.append(placement.duplicate(true)) # Copies the visible-spread placement deeply for rendering ownership isolation.
	return result # Returns every physical sticker currently attached to the requested spread.

func get_page_count() -> int: # Returns the total persistent page count including empty pages in the newest spread.
	return _page_count # Exposes the authoritative even page count without mutable access.

func get_spread_count() -> int: # Returns the number of left/right spreads currently present in the book.
	return maxi(floori(float(_page_count) / float(StickerBookLayout.PAGES_PER_SPREAD)), 1) # Converts the guaranteed-even page count into at least one visible spread.

func get_active_spread_index() -> int: # Returns the zero-based spread currently selected for book viewing and new placement.
	return _active_spread_index # Exposes the persisted active spread index.

func set_active_spread_index(spread_index: int) -> void: # Changes the currently open spread while keeping the requested index inside the existing book.
	var clamped_index: int = clampi(spread_index, 0, maxi(get_spread_count() - 1, 0)) # Restricts navigation to already-created spreads.
	if clamped_index == _active_spread_index: # Avoids rewriting the save when navigation resolves to the current spread.
		return # Leaves persistence untouched for a no-op spread selection.
	_active_spread_index = clamped_index # Stores the newly open spread as the authoritative navigation state.
	_save() # Persists page navigation so reopening the game returns to the same spread.

func append_spread(make_active: bool = true) -> int: # Adds one fresh left/right page pair and optionally opens it immediately.
	_page_count += StickerBookLayout.PAGES_PER_SPREAD # Extends the book by exactly one complete visible spread.
	var new_spread_index: int = get_spread_count() - 1 # Calculates the zero-based index of the newly appended page pair.
	if make_active: # Opens the new spread immediately when page creation was triggered by a full active spread.
		_active_spread_index = new_spread_index # Stores the fresh spread as the current placement and viewing target.
	_save() # Persists both the expanded page count and optional active-spread change atomically.
	return new_spread_index # Returns the new spread index for auto-packing or immediate live rendering.

func get_max_stack_order() -> int: # Returns the highest persistent paper layer currently used anywhere in the book.
	var maximum_stack: int = 0 # Starts at the base layer when the complete book is empty.
	for placement: Dictionary in _placements: # Visits every attached sticker record across every page.
		maximum_stack = maxi(maximum_stack, int(placement.get("stack", 0))) # Expands the maximum from each validated stored stack order.
	return maximum_stack # Returns the highest logical paper layer in the complete book.

func get_max_stack_order_for_page(page_index: int) -> int: # Returns the highest paper layer used on one absolute persistent page.
	var maximum_stack: int = 0 # Starts at the page base layer when no stickers are attached there.
	for placement: Dictionary in _placements: # Visits every physical sticker record once.
		if int(placement.get("page", 0)) != page_index: # Skips stickers attached to different virtual pages.
			continue # Advances without affecting this page's local layering value.
		maximum_stack = maxi(maximum_stack, int(placement.get("stack", 0))) # Tracks only stack values physically relevant to this page.
	return maximum_stack # Returns the highest local paper layer for the requested absolute page.

func get_max_stack_order_for_spread(spread_index: int) -> int: # Returns the highest paper layer currently visible across one left/right spread.
	var maximum_stack: int = 0 # Starts at the base layer for an empty spread.
	for placement: Dictionary in _placements: # Visits every attached sticker record across the book.
		var page_index: int = maxi(int(placement.get("page", 0)), 0) # Retrieves this sticker's absolute page assignment.
		if StickerBookLayout.get_spread_index_for_page(page_index) != spread_index: # Ignores hidden spreads when calculating visible paper height.
			continue # Advances without affecting the active spread's stack counter.
		maximum_stack = maxi(maximum_stack, int(placement.get("stack", 0))) # Tracks the highest visible paper layer across both active pages.
	return maximum_stack # Returns the active spread's maximum physical layer.

func commit_pending_placement(pending_index: int, sticker_size: Vector2, page_index: int, world_xz: Vector2, stack_order: int) -> Dictionary: # Converts one won pending sticker into an upright persistent physical placement on an explicit absolute page.
	if pending_index < 0 or pending_index >= _pending_stickers.size(): # Rejects stale reveal indices before changing any saved data.
		return {} # Returns no placement when the requested pending sticker no longer exists.
	if page_index < 0 or page_index >= _page_count: # Rejects placement records that target a virtual page that has not been created.
		return {} # Prevents invisible or orphaned page assignments from entering persistence.
	var sticker_path: String = _pending_stickers[pending_index] # Captures the exact physical sticker copy before removing it from the pending pack.
	var placement: Dictionary = _create_placement(sticker_path, sticker_size, page_index, world_xz, stack_order) # Builds the complete persistent multi-page placement record with canonical artwork orientation.
	_pending_stickers.remove_at(pending_index) # Removes exactly one physical pending copy while preserving duplicate entries in other slots.
	_placements.append(placement) # Adds the newly attached sticker to the persistent multi-page book layout.
	_save() # Persists the pending removal and new physical placement atomically in one document rewrite.
	return placement.duplicate(true) # Returns an independent record for immediate rendering in the active book scene.

func update_placement(placement_id: String, page_index: int, world_xz: Vector2, stack_order: int) -> void: # Persists movement or restacking while enforcing canonical artwork orientation for every attached sticker.
	if page_index < 0 or page_index >= _page_count: # Rejects movement into a virtual page that does not exist.
		return # Keeps the last valid persistent placement rather than creating an orphaned record.
	for placement_index: int in range(_placements.size()): # Searches the physical layout for the stable placement identifier.
		var placement: Dictionary = _placements[placement_index] # Retrieves the current persistent record for controlled mutation.
		if str(placement.get("id", "")) != placement_id: # Skips every sticker that does not match the moved physical copy.
			continue # Advances until the stable placement identifier is found.
		placement["page"] = page_index # Stores the absolute virtual page currently containing the sticker center.
		placement["x"] = world_xz.x # Stores the new flat visible-page world x coordinate.
		placement["z"] = world_xz.y # Stores the new flat visible-page world z coordinate.
		placement["yaw"] = CANONICAL_YAW_DEGREES # Enforces the original artwork orientation regardless of any temporary peel or inspection transform.
		placement["stack"] = maxi(stack_order, 0) # Stores its newest physical paper layer after being brought to the top.
		_placements[placement_index] = placement # Replaces the array entry with the updated persistent record.
		_save() # Writes the moved placement immediately so quitting after a drag cannot revert its location or page.
		return # Stops searching after the unique physical placement has been updated.

func save_now() -> void: # Exposes an explicit persistence flush for controlled shutdown handling.
	_save() # Writes the complete authoritative multi-page physical book state immediately.

func _create_placement(sticker_path: String, sticker_size: Vector2, page_index: int, world_xz: Vector2, stack_order: int) -> Dictionary: # Creates one normalized upright persistent placement document for a physical sticker.
	var placement_id: String = "sticker_%06d" % _next_placement_id # Creates a compact stable identifier that remains independent of array reordering.
	_next_placement_id += 1 # Reserves the next identifier before the new record can be persisted.
	return { # Returns the complete JSON-compatible multi-page placement record.
		"id": placement_id, # Stores the stable identifier used when this physical sticker is moved later.
		"path": sticker_path, # Stores the imported artwork resource that defines the sticker design.
		"size_x": maxf(sticker_size.x, 0.001), # Stores the original artwork width used to recreate identical physical dimensions.
		"size_y": maxf(sticker_size.y, 0.001), # Stores the original artwork height used to recreate identical physical dimensions.
		"page": page_index, # Stores the zero-based absolute book page containing this physical sticker.
		"x": world_xz.x, # Stores the flat visible-page world x coordinate reused whenever this virtual page is active.
		"z": world_xz.y, # Stores the flat visible-page world z coordinate reused whenever this virtual page is active.
		"yaw": CANONICAL_YAW_DEGREES, # Stores the canonical source-artwork orientation explicitly for compatibility and diagnostics.
		"stack": maxi(stack_order, 0), # Stores physical paper layering independently for exact overlap rendering.
	} # Completes the persistent sticker placement dictionary.

func _load_or_create_save() -> void: # Restores saved book state while migrating old two-page saves and recovering safely from malformed user files.
	_reset_to_defaults() # Establishes deterministic empty values before any filesystem operation can fail.
	if not FileAccess.file_exists(SAVE_PATH): # Detects a first-run book with no physical layout document yet.
		_save() # Creates the valid empty multi-page save immediately.
		return # Keeps the new empty layout in memory.
	var save_file: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.READ) # Opens the user book document for one complete read.
	if save_file == null: # Detects filesystem failures while retaining safe in-memory defaults.
		push_error("could not read sticker book save") # Reports the persistence problem for development diagnostics.
		return # Continues with the deterministic empty fallback.
	var parsed_data: Variant = JSON.parse_string(save_file.get_as_text()) # Parses the complete small JSON layout document into Godot variants.
	if parsed_data is not Dictionary: # Rejects corrupt content that does not contain the expected object root.
		push_warning("sticker book save was invalid and has been reset") # Reports recovery without terminating the game.
		_save() # Replaces malformed content with the current valid empty schema.
		return # Keeps the already initialized defaults.
	var save_data: Dictionary = parsed_data # Narrows the validated JSON root for typed dictionary access.
	var loaded_version: int = maxi(int(save_data.get("version", 1)), 1) # Retrieves the source schema version so legacy page and orientation fields can be migrated deliberately.
	var save_needs_rewrite: bool = loaded_version < SAVE_VERSION # Tracks whether successful migration or orientation normalization should be persisted immediately.
	_next_placement_id = maxi(int(save_data.get("next_placement_id", 1)), 1) # Restores the monotonic physical sticker identifier counter.
	_page_count = maxi(int(save_data.get("page_count", MINIMUM_PAGE_COUNT)), MINIMUM_PAGE_COUNT) # Restores explicit page count when present while preserving the minimum first spread.
	if posmod(_page_count, StickerBookLayout.PAGES_PER_SPREAD) != 0: # Detects malformed odd page counts that cannot represent complete visible spreads.
		_page_count += StickerBookLayout.PAGES_PER_SPREAD - posmod(_page_count, StickerBookLayout.PAGES_PER_SPREAD) # Rounds the page count upward to the next complete spread.
	_active_spread_index = maxi(int(save_data.get("active_spread", 0)), 0) # Restores the last viewed spread before final clamping against loaded content.
	var highest_page_index: int = 1 # Starts with the minimum first spread represented even when no stickers exist.
	var saved_placements: Variant = save_data.get("placements", []) # Retrieves the serialized physical book layout for validation.
	if saved_placements is Array: # Accepts placement data only when the field contains a JSON array.
		for raw_placement: Variant in saved_placements: # Validates every serialized physical sticker independently.
			if raw_placement is not Dictionary: # Rejects malformed array entries that cannot represent a placement.
				continue # Skips only the invalid record while preserving other usable stickers.
			var placement: Dictionary = raw_placement.duplicate(true) # Copies the validated placement so migration never mutates parser-owned data unexpectedly.
			if str(placement.get("path", "")).is_empty(): # Rejects records without an artwork resource path.
				continue # Skips unusable stickers that cannot be recreated.
			if loaded_version < MULTI_PAGE_SAVE_VERSION or not placement.has("page"): # Detects original two-page records that encoded page only through x/z position without remigrating valid version-two pages.
				var legacy_world_xz: Vector2 = Vector2(float(placement.get("x", 0.0)), float(placement.get("z", 0.0))) # Reconstructs the old visible-page center used for migration.
				var legacy_local_page: int = StickerBookLayout.get_local_page_index(legacy_world_xz) # Infers whether the legacy sticker lived inside the old left or right usable page bounds.
				if legacy_local_page < 0: # Handles old freely dragged stickers whose centers were saved slightly outside the conservative usable rectangles.
					legacy_local_page = 0 if legacy_world_xz.x < 0.0 else 1 # Uses the spine side as a stable fallback so old right-page stickers never migrate onto the left page accidentally.
				placement["page"] = legacy_local_page # Maps old left/right placements directly onto absolute pages zero and one.
			var normalized_page: int = maxi(int(placement.get("page", 0)), 0) # Normalizes any malformed negative page field safely.
			placement["page"] = normalized_page # Stores the normalized absolute page back into the runtime placement record.
			if not is_equal_approx(float(placement.get("yaw", CANONICAL_YAW_DEGREES)), CANONICAL_YAW_DEGREES): # Detects older or externally edited saves containing non-canonical book rotation.
				save_needs_rewrite = true # Records that orientation normalization must be written back after the load completes.
			placement["yaw"] = CANONICAL_YAW_DEGREES # Forces every loaded physical sticker back to its original upright artwork orientation.
			highest_page_index = maxi(highest_page_index, normalized_page) # Expands required book size to contain every loaded placement.
			_placements.append(placement) # Restores the complete normalized saved record with independent runtime ownership.
	_page_count = maxi(maxi(_page_count, highest_page_index + 1), MINIMUM_PAGE_COUNT) # Ensures explicit book size contains the highest page referenced by any sticker.
	if posmod(_page_count, StickerBookLayout.PAGES_PER_SPREAD) != 0: # Detects a loaded highest page that leaves the book ending on a single unpaired page.
		_page_count += StickerBookLayout.PAGES_PER_SPREAD - posmod(_page_count, StickerBookLayout.PAGES_PER_SPREAD) # Adds the partner page required for a complete final spread.
	_active_spread_index = clampi(_active_spread_index, 0, maxi(get_spread_count() - 1, 0)) # Restricts the restored active spread to the final migrated page range.
	var saved_pending: Variant = save_data.get("pending_stickers", []) # Retrieves any pack contents that were won but not attached before shutdown.
	if saved_pending is Array: # Accepts pending data only when represented by the expected JSON array.
		for raw_path: Variant in saved_pending: # Restores every physical pending copy in reveal order.
			var sticker_path: String = str(raw_path) # Normalizes each JSON value into the resource-path representation used by the catalogue.
			if not sticker_path.is_empty(): # Keeps only meaningful pending sticker entries.
				_pending_stickers.append(sticker_path) # Restores the unresolved physical pack copy for shutdown recovery auto-placement.
	if save_needs_rewrite: # Detects a successfully migrated or orientation-normalized document that should now be upgraded permanently.
		_save() # Writes normalized pages, canonical sticker orientation, active spread, and current version immediately.

func _save() -> void: # Persists multi-page physical placements and unfinished pack contents together as one authoritative JSON document.
	var save_file: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.WRITE) # Opens the per-user book save for complete replacement.
	if save_file == null: # Detects filesystem failures before attempting serialization.
		push_error("could not write sticker book save") # Reports the exact persistence layer that failed.
		return # Keeps the valid in-memory state for the current session.
	var save_data: Dictionary = { # Collects every persistent physical book field into one versioned object.
		"version": SAVE_VERSION, # Records the multi-page document structure version for future migrations.
		"next_placement_id": _next_placement_id, # Persists the monotonic identifier counter independently from sticker count.
		"page_count": _page_count, # Persists every created virtual page including empty pages in the newest spread.
		"active_spread": _active_spread_index, # Persists which left/right page pair should reopen on the next session.
		"placements": _placements.duplicate(true), # Persists every physical attachment including absolute page, size, location, canonical orientation, and stack.
		"pending_stickers": _pending_stickers.duplicate(), # Persists unresolved pack copies so abnormal shutdown can auto-place them next launch.
	} # Completes the JSON-compatible book state object.
	save_file.store_string(JSON.stringify(save_data, "\t")) # Writes readable JSON for straightforward debugging and future migration.

func _reset_to_defaults() -> void: # Clears runtime book state before loading or explicit future reset operations.
	_placements.clear() # Removes every attached sticker record from runtime memory.
	_pending_stickers.clear() # Removes every unfinished pack copy from runtime memory.
	_next_placement_id = 1 # Restores the first stable physical sticker identifier.
	_page_count = MINIMUM_PAGE_COUNT # Restores the guaranteed first left/right spread.
	_active_spread_index = 0 # Reopens the first spread for a new or reset book.
