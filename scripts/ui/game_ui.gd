class_name GameUI
extends CanvasLayer

const COLLECTION_ITEM_SCENE: PackedScene = preload("res://scenes/ui/collection_item.tscn") # Preloads the reusable editor-authored collection card used for automatically discovered sticker designs.
const STATUS_REFRESH_INTERVAL: float = 0.25 # Limits real-world countdown and lightweight progression-label refresh work to four updates per second.
const TOAST_DURATION: float = 2.2 # Defines how long compact contextual navigation messages remain visible before automatic dismissal.
const DESTINATION_MAIN_MENU: String = "main_menu" # Defines the route identifier for the dedicated startup surface.
const DESTINATION_BOOK: String = "book" # Defines the route identifier for the physical multi-page sticker book.
const DESTINATION_SHOP: String = "shop" # Defines the route identifier for the physically separate pack shop.
const DESTINATION_COLLECTION: String = "collection" # Defines the route identifier for the complete sticker collection browser.
const DESTINATION_SETTINGS: String = "settings" # Defines the route identifier for persistent display preferences.

@onready var _main_menu: Control = $main_menu as Control # References the full-screen startup menu shown before any gameplay destination owns presentation.
@onready var _menu_book_button: Button = $main_menu/layout/menu_column/book_button as Button # References the primary main-menu route into the physical sticker book.
@onready var _menu_shop_button: Button = $main_menu/layout/menu_column/shop_button as Button # References the main-menu route into the separate sticker shop.
@onready var _menu_collection_button: Button = $main_menu/layout/menu_column/collection_button as Button # References the main-menu route into collection browsing.
@onready var _menu_settings_button: Button = $main_menu/layout/menu_column/settings_button as Button # References the main-menu route into persistent settings.
@onready var _menu_quit_button: Button = $main_menu/layout/menu_column/quit_button as Button # References the main-menu desktop quit action.
@onready var _menu_currency: Label = $main_menu/layout/summary_panel/margin/content/currency as Label # References the startup summary's spendable currency field.
@onready var _menu_collection: Label = $main_menu/layout/summary_panel/margin/content/collection as Label # References the startup summary's unique collection completion field.
@onready var _menu_book_state: Label = $main_menu/layout/summary_panel/margin/content/discoveries as Label # References the startup summary's multi-page book and unresolved-pack state field.
@onready var _menu_free_pack: Label = $main_menu/layout/summary_panel/margin/content/free_pack as Label # References the startup summary's real-world free-pack field.

@onready var _shell: Control = $shell as Control # References the persistent navigation shell shown around every non-menu destination.
@onready var _nav_book: Button = $shell/nav_panel/margin/content/book as Button # References the persistent route into the physical book world.
@onready var _nav_shop: Button = $shell/nav_panel/margin/content/shop as Button # References the persistent route into the separate shop world.
@onready var _nav_collection: Button = $shell/nav_panel/margin/content/collection as Button # References the persistent route into collection browsing.
@onready var _nav_settings: Button = $shell/nav_panel/margin/content/settings as Button # References the persistent route into settings.
@onready var _nav_main_menu: Button = $shell/nav_panel/margin/content/main_menu as Button # References the persistent route back to the dedicated startup menu.
@onready var _page_title: Label = $shell/top_bar/margin/content/page_title as Label # References the compact destination title in the persistent top bar.
@onready var _top_currency: Label = $shell/top_bar/margin/content/status/currency as Label # References the always-visible spendable currency value.
@onready var _top_free_pack: Label = $shell/top_bar/margin/content/status/free_pack as Label # References the always-visible free-pack eligibility status.
@onready var _top_book_state: Label = $shell/top_bar/margin/content/status/discoveries as Label # References the always-visible page-count and unresolved-pack status.
@onready var _toast_panel: PanelContainer = $shell/toast as PanelContainer # References the transient contextual message layered over shell content.
@onready var _toast_label: Label = $shell/toast/label as Label # References the transient contextual message text.

@onready var _content_overlay: Control = $shell/content_overlay as Control # References the full content-area host used by non-3D destinations.
@onready var _collection_page: Control = $shell/content_overlay/collection_page as Control # References the complete editor-authored collection browser.
@onready var _collection_grid: GridContainer = $shell/content_overlay/collection_page/panel/margin/content/scroll/grid as GridContainer # References the responsive grid that receives reusable collection cards.
@onready var _collection_progress: Label = $shell/content_overlay/collection_page/panel/margin/content/header/progress as Label # References the unique-design completion summary on the collection page.
@onready var _collection_total: Label = $shell/content_overlay/collection_page/panel/margin/content/header/total as Label # References the duplicate-inclusive total-copy summary on the collection page.
@onready var _settings_page: Control = $shell/content_overlay/settings_page as Control # References the complete editor-authored settings destination.
@onready var _fullscreen_button: Button = $shell/content_overlay/settings_page/panel/margin/content/display/fullscreen as Button # References the persisted fullscreen toggle.
@onready var _vsync_button: Button = $shell/content_overlay/settings_page/panel/margin/content/display/vsync as Button # References the persisted vertical-synchronization toggle.

@onready var _pause_overlay: Control = $pause_overlay as Control # References the modal pause surface that sits above whichever shell destination is currently active.
@onready var _sticker_inspection: StickerInspection = $sticker_inspection as StickerInspection # References the dedicated isolated 3D inspection modal used to zoom and freely rotate a temporary presentation without mutating the book.
@onready var _pause_resume_button: Button = $pause_overlay/panel/margin/content/resume_button as Button # References the primary pause action that returns to the current destination.
@onready var _pause_book_button: Button = $pause_overlay/panel/margin/content/book_button as Button # References the pause shortcut into the physical book.
@onready var _pause_shop_button: Button = $pause_overlay/panel/margin/content/shop_button as Button # References the pause shortcut into the sticker shop.
@onready var _pause_settings_button: Button = $pause_overlay/panel/margin/content/settings_button as Button # References the pause shortcut into settings.
@onready var _pause_main_menu_button: Button = $pause_overlay/panel/margin/content/main_menu_button as Button # References the pause route back to the dedicated startup menu.
@onready var _pause_quit_button: Button = $pause_overlay/panel/margin/content/quit_button as Button # References the pause desktop quit action.

var _controller: GameController # Stores the authoritative game coordinator used for navigation, pack-safe quitting, and physical destination ownership.
var _economy: StickerEconomy # Stores persistent currency, collection counts, pack price, and free-pack cooldown for read-only interface presentation.
var _catalog: StickerCatalog # Stores automatically discovered sticker artwork used by the collection browser and completion summaries.
var _book_state: StickerBookState # Stores multi-page placements, page count, active spread, and unresolved pack copies for interface summaries.
var _preferences: GamePreferences # Stores persisted display preferences manipulated by the settings destination.
var _current_destination: String = DESTINATION_MAIN_MENU # Stores the currently presented route for navigation highlighting, back behavior, and page-title text.
var _refresh_accumulator: float = 0.0 # Accumulates elapsed time between lightweight progression and real-world countdown refreshes.
var _toast_remaining: float = 0.0 # Stores the remaining lifetime of the current transient shell message.
var _overlay_returns_to_main_menu: bool = false # Remembers whether collection or settings was opened from the startup menu instead of an in-game destination.

func configure(controller: GameController, economy: StickerEconomy, catalog: StickerCatalog, book_state: StickerBookState, preferences: GamePreferences) -> void: # Binds authoritative models once and initializes every persistent UX surface without signals.
	_controller = controller # Stores the coordinator used for every route change and controlled desktop quit.
	_economy = economy # Stores progression data used for currency, collection, and free-pack presentation.
	_catalog = catalog # Stores the complete discovered artwork catalogue used by collection browsing.
	_book_state = book_state # Stores page and pending-pack state used by menu and top-bar summaries.
	_preferences = preferences # Stores persisted display preferences manipulated by settings controls.
	_toast_panel.visible = false # Keeps contextual guidance hidden until an actual message is requested.
	_pause_overlay.visible = false # Keeps the modal pause surface absent during startup.
	_sticker_inspection.close_inspection() # Keeps the separate sticker inspection modal absent until the player deliberately clicks a settled book sticker.
	_refresh_all_labels() # Populates menu, top-bar, and collection summary text immediately from authoritative data.
	_refresh_settings() # Populates settings controls from the preferences already applied by the display server.

func show_main_menu() -> void: # Presents the dedicated startup surface and hides every in-game navigation layer.
	_current_destination = DESTINATION_MAIN_MENU # Records the route so escape and confirmation behavior remain deterministic.
	_overlay_returns_to_main_menu = false # Clears overlay back-stack state because the true top-level menu is now visible.
	_sticker_inspection.close_inspection() # Ensures a modal inspection can never remain above the top-level startup route.
	_main_menu.visible = true # Shows the complete startup menu.
	_shell.visible = false # Hides persistent game navigation, world chrome, collection, settings, and toast surfaces.
	_set_pause_visible(false) # Ensures no stale pause modal remains above the main menu after a route change.
	_refresh_all_labels() # Refreshes progress summaries so returning to the menu reflects the current save immediately.
	_menu_book_button.grab_focus.call_deferred() # Gives keyboard/controller navigation a deterministic initial focus anchor.

func show_destination(destination: String) -> void: # Presents one in-game destination inside the persistent navigation shell.
	_current_destination = destination # Stores the selected route for title, focus, highlighting, and back behavior.
	_sticker_inspection.close_inspection() # Clears any book-only inspection modal before navigating to another destination.
	if destination == DESTINATION_BOOK or destination == DESTINATION_SHOP: # Detects a concrete physical destination that becomes the new navigation base.
		_overlay_returns_to_main_menu = false # Clears any prior main-menu overlay return path once gameplay has been entered explicitly.
	_main_menu.visible = false # Removes the startup menu whenever an in-game destination is selected.
	_shell.visible = true # Shows the persistent navigation rail and status bar around all in-game destinations.
	_set_pause_visible(false) # Clears any pause modal because route changes are explicit player actions.
	_collection_page.visible = destination == DESTINATION_COLLECTION # Shows collection content only on its dedicated route.
	_settings_page.visible = destination == DESTINATION_SETTINGS # Shows settings content only on its dedicated route.
	_content_overlay.visible = _collection_page.visible or _settings_page.visible # Covers the 3D content area only for complete screen-space destinations.
	_page_title.text = _page_title_for(destination) # Converts the internal route identifier into a concise player-facing heading.
	_refresh_nav_highlight() # Marks exactly one navigation destination as current.
	_refresh_all_labels() # Synchronizes current currency, page, pack, and free-pack information immediately after navigation.
	if destination == DESTINATION_COLLECTION: # Performs potentially larger catalogue work only when collection is actually opened.
		_rebuild_collection() # Populates one reusable card per automatically discovered sticker design.
		_nav_collection.grab_focus.call_deferred() # Gives controller navigation a deterministic anchor on the collection destination.
	elif destination == DESTINATION_SETTINGS: # Synchronizes mutable display state only when settings becomes visible.
		_refresh_settings() # Updates setting labels after any platform-side changes applied earlier in the session.
		_fullscreen_button.grab_focus.call_deferred() # Focuses the first actionable setting for keyboard/controller navigation.
	elif destination == DESTINATION_SHOP: # Handles the physically separate shop destination.
		_nav_shop.grab_focus.call_deferred() # Focuses the matching route without interfering with mouse interaction in the 3D shop.
	else: # Handles the physical book destination and any safe future default route.
		_nav_book.grab_focus.call_deferred() # Focuses the matching book route for deterministic navigation.

func show_pause() -> void: # Opens a modal pause surface and genuinely suspends pausable gameplay processing underneath it.
	if _sticker_inspection.is_open(): # Prevents pause from stacking another modal above sticker inspection.
		return # Leaves inspection as the sole active modal until the player closes it explicitly.
	if _main_menu.visible: # Prevents a redundant pause layer from appearing over the startup menu.
		return # Leaves the dedicated menu as the sole top-level navigation surface.
	_set_pause_visible(true) # Shows the modal dimmer and pause card before suspending the game tree.
	get_tree().paused = true # Freezes pausable 3D worlds, animations, input owners, and physics while this always-processing UI remains active.
	_pause_resume_button.grab_focus.call_deferred() # Gives keyboard/controller users an explicit safe resume focus target.

func hide_pause() -> void: # Closes the modal pause surface and restores normal processing without changing the current destination.
	get_tree().paused = false # Restores pausable world processing before returning control to the underlying destination.
	_set_pause_visible(false) # Removes the modal dimmer and pause card from pointer and focus ownership.
	_focus_current_destination() # Restores a deterministic navigation focus anchor for the destination that remained underneath pause.

func is_pointer_over_interface(screen_position: Vector2) -> bool: # Reports whether a pointer press belongs to global screen-space UX rather than an underlying physical world.
	if _sticker_inspection.is_open(): # Treats the inspection modal as complete screen ownership regardless of pointer position.
		return true # Prevents every book click, peel, and page control from reacting beneath inspection.
	if _main_menu.visible: # Treats the complete startup surface as owned interface space.
		return true # Prevents hidden physical destinations from reacting anywhere under the main menu.
	if _pause_overlay.visible: # Treats the modal pause surface as complete input ownership.
		return true # Prevents paused physical content from reacting through the dimmed background.
	if not _shell.visible: # Handles the brief startup interval before a route has been presented.
		return false # Leaves pointer routing unchanged while no global shell is visible.
	if _content_overlay.visible: # Treats collection and settings as complete content-area ownership.
		return true # Prevents inactive physical destinations from interpreting clicks beneath those pages.
	if ($shell/nav_panel as Control).get_global_rect().has_point(screen_position): # Detects pointer ownership inside the persistent left navigation rail.
		return true # Prevents world interaction underneath global navigation controls.
	if ($shell/top_bar as Control).get_global_rect().has_point(screen_position): # Detects pointer ownership inside the persistent top status bar.
		return true # Prevents world interaction underneath destination and progression chrome.
	if _toast_panel.visible and _toast_panel.get_global_rect().has_point(screen_position): # Detects the transient message panel while it is visible.
		return true # Prevents physical interaction through visible guidance.
	return false # Leaves the unobstructed content viewport available to the active physical destination.

func blocks_world_input() -> bool: # Reports whether a complete screen-space or modal state should suppress physical-world input entirely.
	if _sticker_inspection.is_open(): # Treats inspection as a modal gameplay state even though the underlying book remains visible.
		return true # Blocks all physical-world input until the temporary inspection transform is dismissed.
	if _main_menu.visible: # Treats the startup menu as a complete non-gameplay state.
		return true # Blocks physical interaction while both worlds are visually inactive.
	if _pause_overlay.visible: # Treats pause as modal regardless of the destination underneath it.
		return true # Blocks physical input even before SceneTree pause propagation reaches all nodes.
	if _content_overlay.visible: # Treats collection and settings as complete screen-space content destinations.
		return true # Blocks physical interaction while their cameras and environments are already released.
	return false # Allows normal world input on unobstructed book and shop destinations.


func show_sticker_inspection(sticker_path: String) -> bool: # Opens one settled book sticker in a separate fully rotatable inspection presentation that never changes its physical saved orientation.
	if _catalog == null or sticker_path.is_empty(): # Rejects inspection before the catalogue exists or when the runtime sticker has no valid artwork identity.
		return false # Leaves the book untouched when inspection cannot identify a source texture.
	var texture_resource: Resource = ResourceLoader.load(sticker_path, "Texture2D") # Loads the exact imported artwork represented by the clicked physical sticker.
	if texture_resource is not Texture2D: # Rejects missing or incompatible artwork without disturbing the selected book sticker.
		return false # Reports that no modal could be opened for the invalid resource.
	var display_name: String = _catalog.get_display_name(sticker_path) # Resolves the same predictable catalogue name used by other sticker presentation surfaces.
	var sticker_size: Vector2 = _catalog.get_default_size(sticker_path) # Retrieves the physical source dimensions required to match the book sticker aspect ratio.
	_sticker_inspection.open_inspection(texture_resource as Texture2D, display_name, sticker_size) # Builds the independent zoomable and freely rotatable 3D inspection presentation.
	return true # Reports that inspection now owns the modal input surface.

func notify_progress_changed() -> void: # Refreshes progression-dependent UX after transactions, page creation, or physical placement without signals.
	_refresh_all_labels() # Synchronizes menu summaries and the persistent top bar immediately after authoritative state changes.
	if _current_destination == DESTINATION_COLLECTION: # Keeps visible collection ownership counts current after future progression mutations.
		_rebuild_collection() # Recreates the data-driven collection cards from the latest authoritative ownership state.

func show_toast(message: String) -> void: # Displays one compact non-blocking guidance message above the current shell destination.
	_toast_label.text = message # Writes the supplied contextual guidance into the editor-authored message field.
	_toast_panel.visible = true # Shows the transient panel above current world or overlay content.
	_toast_remaining = TOAST_DURATION # Restarts the complete readable lifetime for repeated or replaced guidance.

func _process(delta: float) -> void: # Advances lightweight status refresh and transient-message timing while also processing during pause.
	_refresh_accumulator += delta # Accumulates elapsed time toward the next progression and real-world countdown refresh.
	if _refresh_accumulator >= STATUS_REFRESH_INTERVAL: # Limits repeated text formatting and system-clock reads to a small fixed cadence.
		_refresh_accumulator = 0.0 # Restarts the lightweight refresh interval.
		_refresh_all_labels() # Updates currency, collection progress, page state, pending copies, and free-pack timing.
	if _toast_remaining > 0.0: # Advances contextual guidance only while a message has an active lifetime.
		_toast_remaining = maxf(_toast_remaining - delta, 0.0) # Counts down without allowing negative lifetime state.
		if _toast_remaining <= 0.0: # Detects the exact refresh where the message lifetime completes.
			_toast_panel.visible = false # Hides the message without changing route, focus, or gameplay state.

func _input(event: InputEvent) -> void: # Owns all global menu, persistent navigation, pause, collection, and settings actions directly without signals.
	if _controller == null: # Protects editor previews and startup frames before authoritative runtime binding is complete.
		return # Leaves unconfigured interface input untouched.
	if _sticker_inspection.is_open(): # Gives the inspection modal absolute input priority over navigation, pause, and the physical book.
		_sticker_inspection.handle_input(event) # Routes zoom, three-axis rotation, reset, close, and escape directly into the isolated inspection presentation.
		if not _sticker_inspection.is_open(): # Detects the exact input event that closed the modal through escape or its explicit close control.
			_focus_current_destination() # Restores deterministic book-shell keyboard/controller focus after the temporary modal releases ownership.
		get_viewport().set_input_as_handled() # Prevents the same modal-owned event from leaking into any world or shell interaction system.
		return # Completes all input routing inside inspection before ordinary global UX handling begins.
	if event is InputEventKey: # Handles standard desktop escape and confirm keys alongside project-specific controller actions.
		var key_event: InputEventKey = event as InputEventKey # Narrows the event for strongly typed key-code and repeat-state access.
		if key_event.pressed and not key_event.echo and key_event.keycode == KEY_ESCAPE: # Gives escape deterministic back/pause semantics across every route.
			_handle_back_or_pause() # Routes escape according to main-menu, overlay-page, pause, or gameplay destination state.
			get_viewport().set_input_as_handled() # Prevents the same escape event from reaching any underlying physical world behavior.
			return # Completes the escape action as the sole response for this event.
		if key_event.pressed and not key_event.echo and (key_event.keycode == KEY_ENTER or key_event.keycode == KEY_SPACE): # Supports desktop confirmation without relying on button pressed signals.
			_activate_focused_button() # Routes the currently focused editor-authored button through the same explicit action table as pointer input.
			get_viewport().set_input_as_handled() # Prevents confirmation from propagating into physical interactions.
			return # Completes focused-button confirmation as the sole action.
	if _event_action_pressed(event, &"Button_Start"): # Supports the project's established controller start-button naming without requiring a signal connection.
		_handle_start_button() # Toggles pause consistently without stealing escape's overlay-page back behavior.
		get_viewport().set_input_as_handled() # Prevents the same controller action from reaching physical-world input systems.
		return # Completes the start-button action.
	if _event_action_pressed(event, &"Button_A"): # Supports the project's established primary controller confirmation action.
		_activate_focused_button() # Routes controller confirmation through the same explicit button action table.
		get_viewport().set_input_as_handled() # Prevents the confirmation action from affecting world input in the same frame.
		return # Completes controller confirmation.
	if event is not InputEventMouseButton: # Restricts pointer routing to discrete button presses while allowing controls to render their own hover state normally.
		return # Leaves mouse motion and wheel events available to active world interactions outside the shell.
	var mouse_button: InputEventMouseButton = event as InputEventMouseButton # Narrows the event for strongly typed button and position access.
	if not mouse_button.pressed or mouse_button.button_index != MOUSE_BUTTON_LEFT: # Uses only primary-button press events for interface action routing.
		return # Leaves releases and other buttons to their destination-specific systems.
	var button: Button = _button_at_position(mouse_button.position) # Resolves the exact visible enabled editor-authored button beneath the pointer.
	if button == null: # Detects clicks on non-action interface chrome or unobstructed world content.
		return # Leaves the event available to physical destinations when no global action control owns it.
	_activate_button(button) # Executes the selected route or setting through the explicit no-signal action table.
	get_viewport().set_input_as_handled() # Marks the UI click handled so no unhandled-input systems can also react.

func _handle_back_or_pause() -> void: # Applies conventional escape behavior according to the current UX layer.
	if _pause_overlay.visible: # Gives an open modal pause surface first priority.
		hide_pause() # Returns to the exact destination that remained underneath the modal.
		return # Completes modal dismissal without changing route.
	if _main_menu.visible: # Keeps escape inert at the true top level rather than unexpectedly quitting the application.
		return # Leaves the main menu stable and predictable.
	if _current_destination == DESTINATION_COLLECTION or _current_destination == DESTINATION_SETTINGS: # Treats full content pages as navigational children of whichever surface opened them.
		if _overlay_returns_to_main_menu: # Detects an overlay page entered directly from the dedicated startup menu.
			_controller.show_main_menu() # Returns to the actual navigation parent instead of unexpectedly dropping into a gameplay world.
		else: # Handles overlays opened from the persistent in-game shell or pause menu.
			_controller.resume_last_gameplay_destination() # Returns to the player's previous physical book or shop context.
		return # Completes conventional back navigation from an overlay destination.
	show_pause() # Opens pause from physical book or shop gameplay destinations.

func _handle_start_button() -> void: # Gives the controller start button conventional modal pause semantics everywhere outside the startup menu.
	if _main_menu.visible: # Prevents start from creating a pause modal over a menu that already owns navigation.
		return # Leaves startup navigation unchanged.
	if _pause_overlay.visible: # Detects an already-open pause surface.
		hide_pause() # Resumes the destination underneath the modal.
	else: # Handles any active shell destination that is not currently paused.
		show_pause() # Opens the modal pause surface and suspends pausable processing.

func _button_at_position(screen_position: Vector2) -> Button: # Resolves one actionable global interface button beneath the pointer without signals or dynamic scene searching.
	var candidates: Array[Button] = [ # Builds a small fixed action table containing every editor-authored global button.
		_menu_book_button, _menu_shop_button, _menu_collection_button, _menu_settings_button, _menu_quit_button, # Includes all dedicated main-menu actions.
		_nav_book, _nav_shop, _nav_collection, _nav_settings, _nav_main_menu, # Includes all persistent navigation-rail actions.
		_fullscreen_button, _vsync_button, # Includes all currently implemented settings controls.
		_pause_resume_button, _pause_book_button, _pause_shop_button, _pause_settings_button, _pause_main_menu_button, _pause_quit_button, # Includes every modal pause action.
	] # Completes the fixed global button action table.
	for candidate: Button in candidates: # Tests only the small known global action set instead of traversing the scene tree.
		if candidate == null or not candidate.visible or candidate.disabled: # Skips unavailable controls before performing rectangle work.
			continue # Advances directly to the next possible action control.
		if not candidate.is_visible_in_tree(): # Rejects children of hidden route containers such as main menu, shell, or pause.
			continue # Prevents hidden button rectangles from stealing clicks from visible destinations.
		if candidate.get_global_rect().has_point(screen_position): # Tests the pointer against the control's final container-computed screen rectangle.
			return candidate # Returns the first exact visible action control containing the pointer.
	return null # Reports that the pointer is not over any global action button.

func _activate_focused_button() -> void: # Routes keyboard or controller confirmation through the same explicit action table used by pointer input.
	var focus_owner: Control = get_viewport().gui_get_focus_owner() # Retrieves the single Control currently owning keyboard/controller focus.
	if focus_owner is not Button: # Rejects labels, containers, absent focus, and any future non-button focus owner.
		return # Leaves confirmation inert when there is no actionable focused button.
	_activate_button(focus_owner as Button) # Executes the focused button through the same no-signal action routing used by mouse input.

func _activate_button(button: Button) -> void: # Executes one global interface action from an exact editor-authored button reference.
	if button == _menu_book_button or button == _nav_book or button == _pause_book_button: # Handles every route into the physical sticker book.
		_controller.show_book() # Delegates world ownership and persistent shell presentation to the authoritative coordinator.
	elif button == _menu_shop_button or button == _nav_shop or button == _pause_shop_button: # Handles every route into the physically separate shop.
		_controller.show_shop() # Delegates world ownership and reveal continuity to the authoritative coordinator.
	elif button == _menu_collection_button or button == _nav_collection: # Handles collection browsing from startup and persistent navigation.
		_overlay_returns_to_main_menu = button == _menu_collection_button # Records the correct back-stack parent before the route changes.
		_controller.show_collection() # Opens the complete collection content page while preserving physical worlds in memory.
	elif button == _menu_settings_button or button == _nav_settings or button == _pause_settings_button: # Handles every route into display settings.
		_overlay_returns_to_main_menu = button == _menu_settings_button # Records whether escape from settings should return to startup rather than gameplay.
		_controller.show_settings() # Opens settings through the authoritative navigation path and clears pause if necessary.
	elif button == _nav_main_menu or button == _pause_main_menu_button: # Handles non-destructive return to the dedicated startup menu.
		_controller.show_main_menu() # Hides physical destinations and refreshes the startup progression summary without quitting.
	elif button == _menu_quit_button or button == _pause_quit_button: # Handles every intentional desktop quit action.
		_controller.request_quit() # Resolves pending pack stickers, flushes persistence, and quits through the controlled shutdown path.
	elif button == _pause_resume_button: # Handles the modal primary resume action.
		hide_pause() # Restores pausable world processing while leaving the current destination unchanged.
	elif button == _fullscreen_button: # Handles the persisted fullscreen setting without signals.
		_preferences.toggle_fullscreen() # Applies and saves the new window-mode preference immediately.
		_refresh_settings() # Updates the button label to describe the resulting state.
	elif button == _vsync_button: # Handles the persisted vertical-synchronization setting without signals.
		_preferences.toggle_vsync() # Applies and saves the new synchronization preference immediately.
		_refresh_settings() # Updates the button label to describe the resulting state.

func _refresh_all_labels() -> void: # Synchronizes menu and persistent-shell progression displays with authoritative models.
	if _economy == null or _catalog == null or _book_state == null: # Protects editor previews and startup frames before runtime binding is complete.
		return # Leaves placeholder scene text untouched until authoritative state exists.
	var currency: int = _economy.get_currency() # Reads spendable currency once so all visible surfaces show exactly the same balance.
	var unique_owned: int = _economy.get_unique_owned_count() # Reads distinct collected designs once for consistent completion display.
	var total_catalog: int = _catalog.get_sticker_count() # Reads the current automatically discovered catalogue size once for completion display.
	var total_owned: int = _economy.get_total_owned_count() # Reads duplicate-inclusive owned copies once for the startup summary.
	var page_count: int = _book_state.get_page_count() # Reads the persistent number of physical pages currently present in the book.
	var placement_count: int = _book_state.get_placement_count() # Reads the attached sticker-copy count in constant time without deep-copying the complete multi-page layout.
	var pending_count: int = _book_state.get_pending_count() # Reads how many won pack stickers remain unresolved in the current reveal transaction.
	var free_seconds: int = _economy.get_free_pack_seconds_remaining() # Reads the real-world free-pack wait once for consistent menu and top-bar text.
	_menu_currency.text = "currency\n%d coins" % currency # Shows the current spendable balance as a compact two-line startup summary.
	_menu_collection.text = "collection\n%d / %d designs  ·  %d copies" % [unique_owned, total_catalog, total_owned] # Shows both unique completion and duplicate ownership without needing another screen.
	_menu_book_state.text = "sticker book\n%d pages  ·  %d placed  ·  %d waiting" % [page_count, placement_count, pending_count] # Shows persistent book growth and any unresolved pack work in one concise summary.
	_menu_free_pack.text = "free pack\n%s" % _free_pack_text(free_seconds) # Shows current free-pack readiness or remaining real-world wait.
	_top_currency.text = "coins  %d" % currency # Shows spendable currency continuously across every in-game destination.
	_top_free_pack.text = "free_pack  %s" % _free_pack_text(free_seconds) # Shows free-pack readiness or countdown continuously across the shell.
	_top_book_state.text = "pages  %d  ·  waiting  %d" % [page_count, pending_count] # Shows compact book growth and unresolved pack state in the persistent top bar.
	if pending_count > 0: # Highlights unresolved pack contents directly on the primary startup route.
		_menu_book_button.text = "open book    %d waiting" % pending_count # Makes the primary action communicate outstanding physical placement work.
	else: # Handles normal book entry without unresolved pack contents.
		_menu_book_button.text = "open book" # Uses the clean default primary-action label.
	if free_seconds <= 0 and not _catalog.is_empty(): # Highlights a claimable free pack directly in primary navigation.
		_menu_shop_button.text = "sticker shop    free pack ready" # Surfaces the time-sensitive reward without creating a blocking popup.
	else: # Handles an active cooldown or unavailable catalogue.
		_menu_shop_button.text = "sticker shop" # Uses the stable default route label.

func _refresh_nav_highlight() -> void: # Updates persistent navigation state so exactly one destination reads as selected.
	_nav_book.button_pressed = _current_destination == DESTINATION_BOOK # Highlights the book route only while the physical book owns content.
	_nav_shop.button_pressed = _current_destination == DESTINATION_SHOP # Highlights the shop route only while the physical shop owns content.
	_nav_collection.button_pressed = _current_destination == DESTINATION_COLLECTION # Highlights collection only while its full page is visible.
	_nav_settings.button_pressed = _current_destination == DESTINATION_SETTINGS # Highlights settings only while its full page is visible.

func _refresh_settings() -> void: # Synchronizes setting-button labels with currently persisted and applied display preferences.
	if _preferences == null: # Protects editor previews before the preferences model is configured.
		return # Leaves placeholder labels untouched until authoritative preferences exist.
	_fullscreen_button.text = "fullscreen    %s" % _on_off(_preferences.is_fullscreen()) # Describes current fullscreen state directly on its action control.
	_vsync_button.text = "vsync         %s" % _on_off(_preferences.is_vsync_enabled()) # Describes current synchronization state directly on its action control.

func _rebuild_collection() -> void: # Recreates the collection grid from the current automatic catalogue and duplicate-aware ownership data.
	for child: Node in _collection_grid.get_children(): # Visits only data-driven collection entries currently parented to the editor-authored grid.
		child.queue_free() # Schedules stale cards for safe deletion before the latest catalogue view is constructed.
	var total_catalog: int = _catalog.get_sticker_count() # Reads catalogue size once for loop bounds and completion text.
	for catalog_index: int in range(total_catalog): # Creates exactly one reusable card for every currently discovered sticker design.
		var sticker_path: String = _catalog.get_sticker_path(catalog_index) # Retrieves the stable resource path for the current design.
		var texture_resource: Resource = ResourceLoader.load(sticker_path, "Texture2D") # Loads imported artwork through Godot's shared resource cache for the 2D preview.
		if texture_resource is not Texture2D: # Skips malformed or unexpectedly imported resources without breaking the rest of the collection page.
			continue # Advances directly to the next valid catalogue entry.
		var item: CollectionItem = COLLECTION_ITEM_SCENE.instantiate() as CollectionItem # Instantiates the reusable editor-authored collection card scene.
		_collection_grid.add_child(item) # Parents the card into the responsive GridContainer managed by the scene layout.
		item.configure(_catalog.get_display_name(sticker_path), texture_resource as Texture2D, _economy.get_owned_count(sticker_path)) # Populates artwork, readable design name, and duplicate count from authoritative models.
	_collection_progress.text = "%d / %d designs collected" % [_economy.get_unique_owned_count(), total_catalog] # Shows distinct-design completion against the live automatic catalogue.
	_collection_total.text = "%d total sticker copies" % _economy.get_total_owned_count() # Shows duplicate-inclusive ownership beside unique completion.

func _focus_current_destination() -> void: # Restores deterministic focus after closing pause without changing route state.
	if _current_destination == DESTINATION_COLLECTION: # Restores the collection navigation anchor when collection remains visible.
		_nav_collection.grab_focus.call_deferred() # Gives controller navigation a predictable collection focus target.
	elif _current_destination == DESTINATION_SETTINGS: # Restores the first actionable settings control when settings remains visible.
		_fullscreen_button.grab_focus.call_deferred() # Gives controller navigation immediate access to settings actions.
	elif _current_destination == DESTINATION_SHOP: # Restores the shop navigation anchor when the physical shop remains underneath pause.
		_nav_shop.grab_focus.call_deferred() # Keeps controller focus consistent with the visible destination.
	else: # Handles the physical book and safe future fallback destinations.
		_nav_book.grab_focus.call_deferred() # Restores focus to the persistent book navigation route.

func _set_pause_visible(visible_state: bool) -> void: # Applies modal pause visibility and pointer ownership in one place.
	_pause_overlay.visible = visible_state # Shows or hides the complete modal surface including its dimmer and action card.

func _page_title_for(destination: String) -> String: # Converts one internal route identifier into a concise player-facing destination heading.
	match destination: # Uses a small fixed branch table for the complete known route set.
		DESTINATION_BOOK: # Handles the physical multi-page book destination.
			return "sticker book" # Returns the compact book heading.
		DESTINATION_SHOP: # Handles the physically separate pack shop destination.
			return "sticker shop" # Returns the compact shop heading.
		DESTINATION_COLLECTION: # Handles the full collection browser destination.
			return "collection" # Returns the compact collection heading.
		DESTINATION_SETTINGS: # Handles persistent display preferences.
			return "settings" # Returns the compact settings heading.
		_: # Handles unexpected or future route values safely.
			return "sticker book" # Falls back to the core game destination rather than exposing an internal identifier.

func _free_pack_text(seconds_remaining: int) -> String: # Formats real-world free-pack eligibility for stable compact menu and top-bar presentation.
	if seconds_remaining <= 0: # Handles an immediately claimable free pack.
		return "ready" # Uses a clear availability word instead of displaying a zero timer.
	var safe_seconds: int = maxi(seconds_remaining, 0) # Protects formatting if the cooldown crosses zero between model reads.
	var hours: int = safe_seconds / 3600 # Calculates complete remaining real-world hours with integer arithmetic.
	var minutes: int = (safe_seconds % 3600) / 60 # Calculates complete remaining minutes after removing whole hours.
	var seconds: int = safe_seconds % 60 # Calculates remaining seconds after removing complete minutes.
	return "%02d:%02d:%02d" % [hours, minutes, seconds] # Returns a fixed-width countdown that avoids visible layout jitter.

func _on_off(enabled: bool) -> String: # Converts a boolean display preference into compact readable settings text.
	if enabled: # Handles the enabled state.
		return "on" # Returns the compact enabled label.
	return "off" # Returns the compact disabled label.

func _event_action_pressed(event: InputEvent, action_name: StringName) -> bool: # Safely tests an optional project controller action without producing missing-action warnings.
	if not InputMap.has_action(action_name): # Checks the InputMap because controller actions can be supplied or remapped by the wider project.
		return false # Treats an unavailable optional action as inactive.
	return event.is_action_pressed(action_name) # Uses Godot's action abstraction when the requested project action exists.
