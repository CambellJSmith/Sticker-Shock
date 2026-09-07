class_name GameUI extends CanvasLayer # Coordinates navigation, modal ownership, and the persistent game shell.

@onready var _menu: StickerMainMenu = %main_menu as StickerMainMenu # References the independent title screen.
@onready var _shell: Control = %shell as Control # References persistent gameplay navigation.
@onready var _overlay: Control = %content_overlay as Control # Owns complete collection and settings pages.
@onready var _collection: CollectionBrowser = %collection_browser as CollectionBrowser # References the cached collection browser.
@onready var _settings: StickerSettingsPage = %settings_page as StickerSettingsPage # References native display preferences.
@onready var _pause: Control = %pause_overlay as Control # Owns pointer input while the game is paused.
@onready var _inspection: StickerInspection = %sticker_inspection as StickerInspection # Reuses the existing unrestricted 3D inspector.
@onready var _toast: Control = %toast as Control # Displays brief outcome feedback above the world.

var _controller: GameController # Retains the existing authoritative game coordinator.
var _economy: StickerEconomy # Reads currency and real-world pack eligibility.
var _catalog: StickerCatalog # Reads the discovered design count.
var _book_state: StickerBookState # Reads book and unresolved-pack progress.
var _destination: String = "main_menu" # Tracks the current route for back behavior and highlighting.
var _history: Array[String] = [] # Records the actual surfaces that opened collection or settings.
var _nav: Dictionary[String, GameButton] = {} # Maps gameplay destinations to their persistent buttons.
var _return_focus: Control # Remembers the exact control that opened a modal.
var _settings_from_pause: bool = false # Restores pause when returning from its settings shortcut.
var _next_stick_navigation_msec: int = 0 # Debounces analog stick motion so small axis updates do not skip menu items.
var _refresh_elapsed: float = 0.0 # Throttles countdown updates independently of rendering.
var _toast_remaining: float = 0.0 # Tracks the lifetime of outcome feedback.

func configure(controller: GameController, economy: StickerEconomy, catalog: StickerCatalog, book_state: StickerBookState, preferences: GamePreferences) -> void: # Binds composed interface components without signals.
	_controller = controller # Retains authoritative routing and transactions.
	_economy = economy # Retains read-only economy access for shell labels.
	_catalog = catalog # Retains the automatically discovered catalogue.
	_book_state = book_state # Retains saved placement and pending-copy state.
	_menu.configure(controller, economy, catalog, book_state, _navigate) # Binds title-screen navigation and progress.
	_collection.configure(economy, catalog, show_sticker_inspection) # Binds cached collection cards to the existing inspector.
	_settings.configure(preferences, _go_back) # Preserves contextual return behavior from settings.
	_nav = {"book": %nav_book as GameButton, "shop": %nav_shop as GameButton, "collection": %nav_collection as GameButton, "settings": %nav_settings as GameButton} # Establishes the persistent navigation mapping.
	for destination: String in _nav: # Binds each route once through native button activation.
		_nav[destination].bind_action(_navigate.bind(destination)) # Preserves release-to-activate pointer behavior.
	(%nav_home as GameButton).bind_action(_navigate.bind("main_menu")) # Binds the title-screen route.
	(%free_status as GameButton).bind_action(_navigate.bind("shop")) # Makes pack eligibility an actionable shop shortcut.
	(%pause_button as GameButton).bind_action(show_pause) # Gives mouse users a visible pause action.
	(%resume_button as GameButton).bind_action(hide_pause) # Restores the paused destination and focus.
	(%pause_settings as GameButton).bind_action(_open_pause_settings) # Opens settings with a route back to pause.
	(%pause_home as GameButton).bind_action(_navigate.bind("main_menu")) # Returns to the title screen safely.
	(%pause_quit as GameButton).bind_action(controller.request_quit) # Resolves pending copies through the existing shutdown path.
	_inspection.configure_actions() # Binds native inspection buttons independently of trackball input.
	notify_progress_changed() # Initializes static progress and countdown labels.

func show_main_menu() -> void: # Presents the title screen with a useful default action.
	_destination = "main_menu" # Records the root route.
	_history.clear() # Discards stale overlay navigation history.
	_settings_from_pause = false # Clears any abandoned settings return state.
	_close_modals() # Releases pause and inspection before changing destinations.
	_menu.visible = true # Shows the title composition.
	_shell.visible = false # Removes in-game chrome from the title screen.
	_menu.refresh() # Reflects the current save when returning to the menu.
	_menu.focus_primary.call_deferred() # Focuses after native container layout completes.

func show_destination(destination: String) -> void: # Presents a physical world or a composed screen-space page.
	_destination = destination # Records the current route for navigation and back behavior.
	_close_modals() # Ensures modals never leak into another route.
	_menu.visible = false # Hides the title screen during gameplay.
	_shell.visible = true # Presents the persistent navigation and status display.
	_collection.visible = destination == "collection" # Activates collection only on its own route.
	_settings.visible = destination == "settings" # Activates preferences only on their own route.
	_overlay.visible = _collection.visible or _settings.visible # Covers physical worlds only for complete UI pages.
	(%page_title as Label).text = {"book": "your book", "shop": "the pack shop", "collection": "collection", "settings": "settings"}.get(destination, "your book") # Uses concise player-facing destination names.
	for route: String in _nav: # Synchronizes the persistent selected state.
		_nav[route].set_pressed_no_signal(route == destination) # Highlights the destination without signals.
	if destination == "collection": # Performs collection work only on entry.
		_collection.refresh() # Reuses cards and refreshes ownership.
	elif destination == "settings": # Synchronizes saved display settings on entry.
		_settings.refresh() # Reflects actual persisted state.
	else: # Treats physical destinations as navigation roots.
		_history.clear() # Prevents old overlay history from affecting gameplay back behavior.
	_focus_destination.call_deferred() # Establishes focus after world HUD visibility is updated.
	_refresh_countdown() # Updates the single shared timer immediately.

func show_pause() -> void: # Freezes the world and gives the modal exclusive input ownership.
	if _menu.visible or _inspection.is_open() or _pause.visible: # Rejects redundant or stacked modal requests.
		return # Keeps the current top-level surface in control.
	_return_focus = get_viewport().gui_get_focus_owner() # Remembers the exact control active before pausing.
	_controller.prepare_for_modal() # Finishes an in-progress peel before suspending its input owner.
	_pause.visible = true # Places the full-screen input blocker above every gameplay button.
	get_tree().paused = true # Suspends pausable world processing while the UI remains active.
	(%resume_button as GameButton).grab_focus() # Selects the safe resume action.

func hide_pause() -> void: # Restores the same destination and its previous native focus.
	get_tree().paused = false # Resumes physical animation and gameplay processing.
	_pause.visible = false # Releases modal pointer ownership.
	_restore_focus() # Returns to the exact opener when it still exists.

func show_sticker_inspection(sticker_path: String) -> bool: # Inspects the original artwork without changing saved book orientation.
	var texture: Texture2D = load(sticker_path) as Texture2D # Reuses the imported artwork resource.
	if texture == null: # Handles missing or invalid resources without opening an empty modal.
		return false # Leaves the current destination intact.
	_return_focus = get_viewport().gui_get_focus_owner() # Remembers the collection card or book control that opened inspection.
	_controller.prepare_for_modal() # Resolves any active world gesture before input becomes modal.
	_inspection.open_inspection(texture, UIFormat.sticker_name(sticker_path), _catalog.get_default_size(sticker_path)) # Reuses the existing quaternion-based inspection scene.
	return true # Confirms that an inspectable resource was opened.

func is_pointer_over_interface(screen_position: Vector2) -> bool: # Separates world gestures from interactive shell regions.
	if blocks_world_input(): # Handles complete screens and modal surfaces first.
		return true # Gives the active screen complete pointer ownership.
	return (%nav_panel as Control).get_global_rect().has_point(screen_position) or (%top_bar as Control).get_global_rect().has_point(screen_position) # Reserves only the persistent chrome rectangles.

func blocks_world_input() -> bool: # Reports exclusive UI ownership to physical interaction components.
	return _menu.visible or _pause.visible or _inspection.is_open() or (_shell.visible and _overlay.visible) # Blocks world input beneath every full screen or modal.

func notify_progress_changed() -> void: # Updates progression only when authoritative models actually change.
	if _economy == null: # Handles early initialization safely.
		return # Defers presentation until dependencies are bound.
	(%currency as Label).text = "%d coins" % _economy.get_currency() # Keeps one currency display in the persistent shell.
	var pending: int = _book_state.get_pending_count() # Reads the unresolved pack-copy count.
	(%pending as Label).text = "%d to place" % pending if pending > 0 else "" # Shows only actionable pending progress.
	if _collection.is_visible_in_tree(): # Avoids collection work outside its active page.
		_collection.refresh() # Refreshes cached card ownership after a transaction.
	_menu.refresh() # Keeps the title-screen summary ready for return navigation.
	_refresh_countdown() # Updates pack eligibility after claiming a free pack.

func show_toast(message: String) -> void: # Presents short feedback for a completed action.
	(%toast_text as Label).text = message # Displays the transaction or placement outcome.
	_toast.visible = true # Shows the noninteractive notification.
	_toast_remaining = 3.0 # Starts its dismissal timer.

func _process(delta: float) -> void: # Updates lightweight time-dependent presentation.
	if _controller == null: # Avoids polling before configuration.
		return # Leaves startup initialization in control.
	_refresh_elapsed += delta # Accumulates time between visible countdown refreshes.
	if _refresh_elapsed >= 1.0: # Keeps real-world timers current without per-frame model scans.
		_refresh_elapsed = 0.0 # Starts the next timer interval.
		_refresh_countdown() # Updates only countdown-related labels.
	if _toast_remaining > 0.0: # Processes notification timing only while a notification is active.
		_toast_remaining = maxf(_toast_remaining - delta, 0.0) # Advances notification dismissal.
		_toast.visible = _toast_remaining > 0.0 # Removes expired feedback from the screen.

func _input(event: InputEvent) -> void: # Handles global back and focus while leaving native controls their normal input path.
	if _controller == null: # Ignores input before dependencies exist.
		return # Avoids routing into an uninitialized controller.
	if event is InputEventMouse: # Keeps frequent pointer movement on a minimal native-input path.
		if _inspection.is_open() and _inspection.handle_input(event): # Reserves only an active inspection-stage gesture.
			get_viewport().set_input_as_handled() # Stops stage gestures from reaching underlying physical worlds.
		return # Leaves native buttons and world picking to their normal GUI and unhandled-input paths.
	if event.is_action_pressed("Button_Start") and not _pause.visible and not _inspection.is_open(): # Lets start pause without cancelling manual placement.
		show_pause() # Suspends the current physical interaction safely.
		get_viewport().set_input_as_handled() # Prevents the pause action reaching native controls.
		return # Completes explicit pause handling.
	if event.is_action_pressed("Button_Start") or event.is_action_pressed("Button_B") or (event is InputEventKey and event.is_pressed() and not event.is_echo() and (event as InputEventKey).keycode == KEY_ESCAPE): # Recognizes standard back and pause inputs.
		_go_back() # Closes the topmost surface or pauses gameplay.
		get_viewport().set_input_as_handled() # Prevents this same event from reaching the world.
		return # Finishes exclusive global handling.
	if event.is_action_pressed("ui_focus_next") or event.is_action_pressed("ui_focus_prev"): # Handles tab traversal within the active scope.
		var controls: Array[Control] = _navigation_controls() # Excludes hidden and underlying modal controls.
		UIFocus.cycle_controls(controls, get_viewport().gui_get_focus_owner(), event.is_action_pressed("ui_focus_prev")) # Wraps native focus in the active scope.
		get_viewport().set_input_as_handled() # Suppresses unrestricted fallback traversal.
		return # Leaves the new focus owner selected without activation.
	if event.is_action_pressed("Button_A"): # Supports the project's controller confirmation action.
		var focus: Control = get_viewport().gui_get_focus_owner() # Reads the actual native focus owner.
		if focus is GameButton and _navigation_controls().has(focus): # Rejects hidden, disabled, or out-of-scope actions.
			(focus as GameButton).invoke() # Uses the same direct callback as native mouse and keyboard activation.
		get_viewport().set_input_as_handled() # Avoids double activation through built-in controller bindings.
		return # Completes controller confirmation.
	var direction: int = _navigation_direction(event) # Resolves keyboard and custom stick navigation.
	if direction >= 0 and get_viewport().gui_get_focus_owner() is not LineEdit: # Leaves text-editing arrow behavior native.
		if event is InputEventJoypadMotion: # Debounces repeated analog updates while the stick remains held.
			var now: int = Time.get_ticks_msec() # Reads a monotonic clock for controller focus repeat.
			if now < _next_stick_navigation_msec: # Rejects another axis update before the repeat interval.
				get_viewport().set_input_as_handled() # Prevents native fallback from skipping another focus item.
				return # Keeps the current menu item selected until the next repeat.
			_next_stick_navigation_msec = now + 180 # Schedules a deliberate next controller focus step.
		UIFocus.navigate_controls(_navigation_controls(), get_viewport().gui_get_focus_owner(), direction as Side) # Confines directional focus to the current screen or modal.
		get_viewport().set_input_as_handled() # Prevents a second native focus move from this event.
		return # Completes scoped directional navigation.
	if _inspection.is_open() and _inspection.handle_input(event): # Lets only the inspection stage consume trackball and zoom input.
		get_viewport().set_input_as_handled() # Prevents inspection gestures from reaching the book.

func _navigation_controls() -> Array[Control]: # Computes the active native focus scope only on navigation input.
	if _inspection.is_open(): # Restricts inspection navigation to its toolbar.
		return UIFocus.controls_in(_inspection) # Excludes collection cards and world controls beneath inspection.
	if _pause.visible: # Gives pause an isolated focus scope.
		return UIFocus.controls_in(_pause) # Excludes every underlying page and navigation control.
	if _menu.visible: # Restricts title-screen navigation to its visible actions.
		return UIFocus.controls_in(_menu) # Returns the title-screen focus order.
	var controls: Array[Control] = UIFocus.controls_in(_shell) # Includes visible navigation and complete UI pages.
	var world_ui: Control = _controller.get_active_world_ui() # Retrieves the active world's composed HUD.
	if world_ui != null and not _overlay.visible: # Adds world actions only during physical gameplay.
		controls.append_array(UIFocus.controls_in(world_ui)) # Includes pack choices and book page controls in keyboard traversal.
	return controls # Returns the currently permitted focus targets.

func _navigation_direction(event: InputEvent) -> int: # Maps directional UI events without reusing them for gameplay.
	if event.is_action_pressed("ui_left") or event.is_action_pressed("StickLeft_West"): # Detects leftward focus navigation.
		return SIDE_LEFT # Requests the native left neighbor.
	if event.is_action_pressed("ui_right") or event.is_action_pressed("StickLeft_East"): # Detects rightward focus navigation.
		return SIDE_RIGHT # Requests the native right neighbor.
	if event.is_action_pressed("ui_up") or event.is_action_pressed("StickLeft_North"): # Detects upward focus navigation.
		return SIDE_TOP # Requests the native upper neighbor.
	if event.is_action_pressed("ui_down") or event.is_action_pressed("StickLeft_South"): # Detects downward focus navigation.
		return SIDE_BOTTOM # Requests the native lower neighbor.
	return -1 # Leaves non-navigation input to its native control.

func _navigate(destination: String) -> void: # Opens a destination while preserving its real back path.
	_settings_from_pause = false # Clears any abandoned pause-specific return state.
	if destination == _destination and not _pause.visible: # Rejects redundant clicks on the current navigation tab.
		_nav[destination].set_pressed_no_signal(true) # Keeps the current route visually selected.
		return # Avoids unnecessary route changes or collection refreshes.
	if destination == "collection" or destination == "settings": # Records the opener for complete overlay destinations.
		_history.append(_destination) # Allows settings opened from collection to return there.
	_route(destination) # Delegates physical world ownership to the existing coordinator.

func _route(destination: String) -> void: # Resolves a known route to its authoritative controller method.
	match destination: # Keeps all route dispatch in one small mapping.
		"main_menu": _controller.show_main_menu() # Opens the dedicated title screen.
		"book": _controller.show_book() # Activates the saved book world.
		"shop": _controller.show_shop() # Activates the physical pack-reveal world.
		"collection": _controller.show_collection() # Opens the screen-space collection.
		"settings": _controller.show_settings() # Opens persisted display settings.

func _go_back() -> void: # Closes only the topmost surface before considering navigation or pause.
	if _inspection.is_open(): # Gives inspection priority over every underlying destination.
		_inspection.close_inspection() # Discards the temporary inspection transform.
		_restore_focus() # Returns to the selected collection card or book control.
	elif _pause.visible: # Handles an already-open pause modal.
		hide_pause() # Resumes the same destination.
	elif _overlay.visible and _shell.visible: # Returns complete UI pages to the surface that opened them.
		var destination: String = _history.pop_back() if not _history.is_empty() else "book" # Reads the actual prior destination with a safe fallback.
		var restore_pause: bool = _settings_from_pause # Preserves pause intent across the route transition.
		_settings_from_pause = false # Consumes the pause-specific return state.
		_route(destination) # Restores the previous page or world.
		if restore_pause: # Handles settings opened from pause.
			show_pause.call_deferred() # Reopens pause after the restored destination establishes focus.
	elif not _menu.visible: # Resolves manual placement before considering a new pause layer.
		if _controller.cancel_pending_placement(): # Gives escape and back a safe exit from manual placement.
			return # Keeps the selected copy unresolved in its pack.
		show_pause() # Freezes the current physical destination.

func _open_pause_settings() -> void: # Opens preferences with an explicit return to the paused destination.
	_history.append(_destination) # Records the surface beneath pause.
	_settings_from_pause = true # Marks the back action as a return to pause.
	_controller.show_settings() # Releases the pause modal while showing settings.

func _close_modals() -> void: # Clears transient input owners on a route change.
	get_tree().paused = false # Releases any paused world state.
	_pause.visible = false # Hides the pause input blocker.
	_inspection.close_inspection() # Closes the temporary inspection viewport.
	_toast.visible = false # Avoids carrying unrelated feedback to another screen.
	_toast_remaining = 0.0 # Cancels the old notification lifetime.

func _focus_destination() -> void: # Selects the useful action for the newly visible destination.
	if _collection.is_visible_in_tree(): # Prioritizes search on the collection page.
		_collection.focus_search() # Supports immediate typing.
	elif _settings.is_visible_in_tree(): # Prioritizes the first display option on the settings page.
		(_settings.get_node("%fullscreen") as Control).grab_focus() # Selects the native fullscreen toggle.
	else: # Gives physical destinations their own useful action focus.
		_controller.focus_active_world_ui() # Selects a claim action, pending sticker, or page control.
		if get_viewport().gui_get_focus_owner() == null: # Handles a populated single-spread book with no available page turn.
			_nav[_destination].grab_focus() # Keeps persistent navigation immediately usable from the keyboard.

func _restore_focus() -> void: # Restores a modal opener if it remains actionable.
	if is_instance_valid(_return_focus) and _return_focus.is_visible_in_tree() and not (_return_focus is BaseButton and (_return_focus as BaseButton).disabled): # Rejects expired, hidden, and disabled openers.
		_return_focus.grab_focus() # Returns to the exact native control the player used.
	else: # Handles world gestures and removed pack-choice controls.
		_focus_destination() # Selects the current destination's useful fallback.

func _refresh_countdown() -> void: # Updates real-world eligibility without rescanning ownership every frame.
	var remaining: int = _economy.get_free_pack_seconds_remaining() # Reads the persisted eligibility timestamp.
	(%free_status as GameButton).text = "free pack ready" if remaining <= 0 else "free pack · %s" % UIFormat.duration(remaining) # Keeps a single actionable timer in the shell.
	if _menu.visible: # Refreshes title-screen countdown text only while shown.
		_menu.refresh() # Keeps its free-pack shortcut synchronized.

func close_inspection() -> void: # Closes inspection from its native toolbar action.
	_inspection.close_inspection() # Releases the temporary artwork viewport.
	_restore_focus() # Restores the exact control that opened this modal.
