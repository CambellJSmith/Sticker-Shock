extends Node # Runs one-time sticker-content cleanup before the main scene initializes.

const MIGRATION_MARKER_PATH: String = "user://sticker_content_reset_v1.done" # Records that legacy individual sticker content has already been cleared.
const BOOK_SAVE_PATH: String = "user://sticker_book.json" # Points to the persistent physical book placement save.
const ECONOMY_SAVE_PATH: String = "user://sticker_progress.json" # Points to the persistent sticker ownership and economy save.

func _init() -> void: # Performs the migration before gameplay systems load their persistent state.
	if FileAccess.file_exists(MIGRATION_MARKER_PATH): # Detects users whose individual sticker content has already been cleared.
		return # Leaves all future sticker content untouched after the one-time migration has completed.
	var book_cleared: bool = _clear_book_stickers() # Removes placed and pending individual stickers while preserving book structure and navigation state.
	var ownership_cleared: bool = _clear_owned_stickers() # Removes owned individual sticker records while preserving currency and free-pack timing.
	if not book_cleared or not ownership_cleared: # Detects any migration failure that should be retried on a later launch.
		return # Avoids writing the completion marker until every existing sticker record has been handled safely.
	_write_migration_marker() # Prevents the cleanup from running again after users add new custom sticker content.

func _clear_book_stickers() -> bool: # Clears individual sticker instances from the persistent book save without removing book-system data.
	if not FileAccess.file_exists(BOOK_SAVE_PATH): # Skips cleanup when no prior book save exists.
		return true # Treats an absent save as already free of legacy individual stickers.
	var save_file: FileAccess = FileAccess.open(BOOK_SAVE_PATH, FileAccess.READ) # Opens the existing book save for controlled migration.
	if save_file == null: # Detects a read failure without risking replacement of inaccessible user data.
		return false # Requests a retry on the next launch because the legacy sticker records may still exist.
	var parsed_data: Variant = JSON.parse_string(save_file.get_as_text()) # Parses the current book save into Godot data.
	if parsed_data is not Dictionary: # Rejects malformed saves that the normal book loader already knows how to recover from.
		return false # Requests a retry rather than marking potentially sticker-bearing data as cleared.
	var save_data: Dictionary = parsed_data # Narrows the validated root into the mutable save dictionary.
	save_data["placements"] = [] # Removes every individual sticker already attached to book pages.
	save_data["pending_stickers"] = [] # Removes every individual sticker waiting in an unfinished pack reveal.
	save_data["next_placement_id"] = 1 # Restarts sticker instance identifiers after the complete content clear.
	var write_file: FileAccess = FileAccess.open(BOOK_SAVE_PATH, FileAccess.WRITE) # Opens the same save for complete replacement.
	if write_file == null: # Detects a write failure before serialization.
		return false # Requests a retry because the cleared state could not be persisted.
	write_file.store_string(JSON.stringify(save_data, "\t")) # Persists the sticker-free book state while retaining non-sticker book metadata.
	return true # Confirms that all individual book sticker records were removed successfully.

func _clear_owned_stickers() -> bool: # Clears individual sticker ownership entries without resetting unrelated economy progression.
	if not FileAccess.file_exists(ECONOMY_SAVE_PATH): # Skips cleanup when no prior economy save exists.
		return true # Treats an absent save as already free of legacy owned stickers.
	var save_file: FileAccess = FileAccess.open(ECONOMY_SAVE_PATH, FileAccess.READ) # Opens the existing economy save for controlled migration.
	if save_file == null: # Detects a read failure without risking replacement of inaccessible user data.
		return false # Requests a retry on the next launch because legacy ownership records may still exist.
	var parsed_data: Variant = JSON.parse_string(save_file.get_as_text()) # Parses the current economy save into Godot data.
	if parsed_data is not Dictionary: # Rejects malformed saves that the normal economy loader already knows how to recover from.
		return false # Requests a retry rather than marking potentially sticker-bearing data as cleared.
	var save_data: Dictionary = parsed_data # Narrows the validated root into the mutable save dictionary.
	save_data["owned_stickers"] = {} # Removes every individual owned sticker while preserving currency and cooldown fields.
	var write_file: FileAccess = FileAccess.open(ECONOMY_SAVE_PATH, FileAccess.WRITE) # Opens the same economy save for complete replacement.
	if write_file == null: # Detects a write failure before serialization.
		return false # Requests a retry because the cleared ownership state could not be persisted.
	write_file.store_string(JSON.stringify(save_data, "\t")) # Persists the sticker-free ownership state with unrelated economy progress intact.
	return true # Confirms that all individual owned sticker records were removed successfully.

func _write_migration_marker() -> void: # Records successful completion so future custom sticker content is never cleared automatically.
	var marker_file: FileAccess = FileAccess.open(MIGRATION_MARKER_PATH, FileAccess.WRITE) # Creates the durable one-time migration marker.
	if marker_file == null: # Detects an unexpected marker-write failure.
		return # Allows a later launch to retry the migration rather than pretending it completed.
	marker_file.store_string("complete") # Stores a minimal marker payload whose existence is sufficient for future startup checks.
