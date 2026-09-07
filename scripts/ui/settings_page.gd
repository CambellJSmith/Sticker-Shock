class_name StickerSettingsPage extends MarginContainer # Owns native display controls and their saved state.

@onready var _fullscreen: GameButton = %fullscreen as GameButton # References the window-mode toggle.
@onready var _vsync: GameButton = %vsync as GameButton # References the synchronization toggle.

var _preferences: GamePreferences # Keeps display persistence in its existing model.

func configure(preferences: GamePreferences, back: Callable) -> void: # Binds persistent settings and the contextual back action.
	_preferences = preferences # Retains the existing preference store.
	_fullscreen.bind_action(_toggle_fullscreen) # Uses native release activation for the display toggle.
	_vsync.bind_action(_toggle_vsync) # Uses native activation for synchronization.
	(%back_button as GameButton).bind_action(back) # Returns to the surface that opened settings.
	refresh() # Presents the saved settings immediately.

func refresh() -> void: # Synchronizes text and toggle states from the preference model.
	_fullscreen.text = "on" if _preferences.is_fullscreen() else "off" # Makes the window-mode state explicit in text.
	_fullscreen.set_pressed_no_signal(_preferences.is_fullscreen()) # Keeps the native toggle appearance synchronized.
	_vsync.text = "on" if _preferences.is_vsync_enabled() else "off" # Makes synchronization state explicit in text.
	_vsync.set_pressed_no_signal(_preferences.is_vsync_enabled()) # Keeps the synchronization appearance synchronized.

func _toggle_fullscreen() -> void: # Applies and saves the requested window-mode change.
	_preferences.toggle_fullscreen() # Delegates persistence and platform behavior to the existing model.
	refresh() # Reflects the new state immediately.

func _toggle_vsync() -> void: # Applies and saves synchronization changes.
	_preferences.toggle_vsync() # Delegates display behavior and persistence.
	refresh() # Reflects the saved setting immediately.
