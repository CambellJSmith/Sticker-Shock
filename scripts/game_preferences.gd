class_name GamePreferences
extends RefCounted

const SAVE_PATH: String = "user://game_preferences.json" # Stores lightweight presentation preferences separately from progression data.
const SAVE_VERSION: int = 1 # Identifies the current preferences document structure for future migration.

var _fullscreen: bool = false # Stores whether the game should use fullscreen window mode.
var _vsync_enabled: bool = true # Stores whether vertical synchronization should be enabled for the display window.

func initialize() -> void: # Restores saved presentation preferences and applies them before the main menu becomes interactive.
	_load_or_create_save() # Loads validated settings or establishes safe defaults on first run.
	_apply_display_preferences() # Applies the restored window and synchronization configuration immediately.

func is_fullscreen() -> bool: # Exposes the current persisted fullscreen preference to the settings interface.
	return _fullscreen # Returns the protected fullscreen state without exposing direct mutation.

func is_vsync_enabled() -> bool: # Exposes the current persisted vertical-synchronization preference to the settings interface.
	return _vsync_enabled # Returns the protected synchronization state without exposing direct mutation.

func toggle_fullscreen() -> bool: # Toggles fullscreen mode, applies it immediately, persists it, and returns the new state.
	_fullscreen = not _fullscreen # Flips the authoritative fullscreen preference in memory.
	_apply_window_mode() # Applies the new window mode immediately so the player sees the setting change.
	_save() # Persists the updated preference for the next launch.
	return _fullscreen # Returns the resulting state for immediate interface refresh.

func toggle_vsync() -> bool: # Toggles vertical synchronization, applies it immediately, persists it, and returns the new state.
	_vsync_enabled = not _vsync_enabled # Flips the authoritative synchronization preference in memory.
	_apply_vsync() # Applies the new display-server synchronization mode immediately.
	_save() # Persists the updated preference for the next launch.
	return _vsync_enabled # Returns the resulting state for immediate interface refresh.

func _load_or_create_save() -> void: # Restores preferences from disk while recovering cleanly from missing or malformed documents.
	_fullscreen = false # Establishes the safe first-run windowed preference before attempting any file read.
	_vsync_enabled = true # Establishes the safe first-run synchronized preference before attempting any file read.
	if not FileAccess.file_exists(SAVE_PATH): # Detects first run before attempting to open a nonexistent preferences file.
		_save() # Creates the preferences file immediately using the safe defaults.
		return # Leaves first-run defaults active after creating storage.
	var save_file: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.READ) # Opens the small preferences document for one sequential read.
	if save_file == null: # Detects an operating-system or filesystem failure without invalidating safe defaults.
		push_warning("could not read game preferences") # Reports the persistence issue for development diagnostics.
		return # Continues with the initialized safe defaults.
	var parsed_data: Variant = JSON.parse_string(save_file.get_as_text()) # Parses the complete small JSON document into Godot variants.
	if parsed_data is not Dictionary: # Rejects malformed preference files that do not contain an object root.
		push_warning("game preferences were invalid and have been reset") # Reports recovery from invalid user data.
		_save() # Replaces malformed data with the current safe preference structure.
		return # Keeps the initialized defaults active.
	var save_data: Dictionary = parsed_data # Narrows the validated JSON root for typed preference reads.
	_fullscreen = bool(save_data.get("fullscreen", false)) # Restores the fullscreen preference with a safe fallback.
	_vsync_enabled = bool(save_data.get("vsync_enabled", true)) # Restores the synchronization preference with a safe fallback.

func _apply_display_preferences() -> void: # Applies every persisted display preference through the platform display server.
	_apply_window_mode() # Applies the persisted fullscreen or windowed mode.
	_apply_vsync() # Applies the persisted vertical-synchronization mode.

func _apply_window_mode() -> void: # Applies only the current fullscreen preference to the game window.
	if _fullscreen: # Selects fullscreen presentation when the persisted preference is enabled.
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN) # Requests standard fullscreen mode without changing game rendering state.
	else: # Selects normal desktop-window presentation when fullscreen is disabled.
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED) # Restores the standard resizable desktop window mode.

func _apply_vsync() -> void: # Applies only the current vertical-synchronization preference to the display server.
	if _vsync_enabled: # Selects synchronized presentation when the persisted preference is enabled.
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED) # Requests ordinary vertical synchronization for the main window.
	else: # Selects unsynchronized presentation when the preference is disabled.
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED) # Disables vertical synchronization without changing frame-rate logic.

func _save() -> void: # Persists the complete preference state as one small JSON document.
	var save_data: Dictionary = { # Builds the complete serialized preference root in one allocation.
		"version": SAVE_VERSION, # Stores the preferences schema version for future migration support.
		"fullscreen": _fullscreen, # Stores whether fullscreen should be restored next launch.
		"vsync_enabled": _vsync_enabled, # Stores whether vertical synchronization should be restored next launch.
	} # Completes the serialized preference object.
	var save_file: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.WRITE) # Opens the writable per-user preferences path for replacement.
	if save_file == null: # Detects filesystem failures before attempting to write the JSON payload.
		push_error("could not write game preferences") # Reports persistence failure without crashing the current session.
		return # Keeps the in-memory preference active even when persistence fails.
	save_file.store_string(JSON.stringify(save_data)) # Writes the complete compact preferences document atomically from the model's perspective.
