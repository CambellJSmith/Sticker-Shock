class_name MarketGameUI
extends GameUI

const CONTROLLER_KEYBOARD_SCENE: PackedScene = preload("res://scenes/ui/controller_keyboard.tscn") # Preloads the reusable in-game text-entry modal needed for controller-only search and Unique-code redemption.

var _controller_keyboard: ControllerKeyboard # Stores the controller text-entry modal above every ordinary UI destination.
var _controller_input_active: bool = false # Tracks the most recently used input family so world interactions and focus choose controller-appropriate behavior.

func _ready() -> void: # Composes the controller-only text-entry surface before the game coordinator configures normal destinations.
	_controller_keyboard = CONTROLLER_KEYBOARD_SCENE.instantiate() as ControllerKeyboard # Creates one persistent keyboard reused for every LineEdit in the application.
	add_child(_controller_keyboard) # Places the modal last in the CanvasLayer so it always renders above menus, worlds, pause, and inspection.

func configure(controller: GameController, economy: StickerEconomy, catalog: StickerCatalog, book_state: StickerBookState, preferences: GamePreferences) -> void: # Extends the established persistent game shell with market routing and complete controller support.
	super.configure(controller, economy, catalog, book_state, preferences) # Binds all existing book, packs, collection, settings, pause, inspection, and title-screen controls first.
	var market_button: GameButton = %nav_market as GameButton # References the editor-authored market navigation button in the shared left rail.
	_nav["market"] = market_button # Adds the collector exchange to the same destination-selection lookup used by existing routes.
	market_button.bind_action(_navigate.bind("market")) # Routes native activation through the established destination navigation path without signals.

func show_destination(destination: String) -> void: # Presents existing routes normally while giving the physical market world its own player-facing title.
	super.show_destination(destination) # Reuses shell visibility, navigation highlighting, modal closure, focus, and countdown handling.
	if destination == "market": # Corrects the base fallback title only for the collector exchange route.
		(%page_title as Label).text = "collector exchange" # Gives the market world an explicit title in the persistent top bar.

func is_controller_input_active() -> bool: # Reports whether the player's most recent meaningful input came from a gamepad.
	return _controller_input_active # Gives physical worlds one central input-mode authority without duplicating device heuristics.

func blocks_world_input() -> bool: # Extends modal ownership so controller text entry also suppresses physical world interaction.
	return (_controller_keyboard != null and _controller_keyboard.is_open()) or super.blocks_world_input() # Prevents sticker picking beneath the on-screen keyboard while preserving all established modal guards.

func _input(event: InputEvent) -> void: # Adds controller text, selector, and input-mode behavior before delegating ordinary navigation to GameUI.
	_update_input_mode(event) # Records meaningful controller versus mouse/keyboard use before any destination responds to this event.
	if _controller_keyboard != null and _controller_keyboard.is_open() and event.is_action_pressed("Button_Start"): # Keeps Start from opening pause underneath controller text entry.
		_controller_keyboard.cancel() # Treats Start as a safe modal escape while B remains the normal cancel action.
		get_viewport().set_input_as_handled() # Prevents the same Start press from reaching the base pause handler.
		return # Leaves the restored text field focused after closing the keyboard.
	if event.is_action_pressed("Button_A"): # Intercepts controller activation only for native controls that are not GameButton actions.
		var focus: Control = get_viewport().gui_get_focus_owner() # Reads the exact native control currently selected by controller navigation.
		var controls: Array[Control] = _navigation_controls() # Restricts special activation to the current modal/page focus scope.
		if focus is LineEdit and controls.has(focus): # Turns A on any text field into reliable in-game controller text entry.
			_controller_keyboard.open_for(focus as LineEdit) # Copies the field value into the reusable modal without requiring an operating-system keyboard.
			get_viewport().set_input_as_handled() # Prevents native text focus from consuming the same controller press.
			return # Gives the newly opened keyboard exclusive focus ownership.
		if focus is OptionButton and controls.has(focus): # Gives native pack selectors an explicit controller action without relying on popup-specific platform mappings.
			_cycle_option_button(focus as OptionButton, 1) # Advances to the next authored option while left/right can still move both directions.
			get_viewport().set_input_as_handled() # Prevents the OptionButton popup from opening from the same A press.
			return # Keeps focus on the selector after the deterministic one-step change.
	var direction: int = _navigation_direction(event) # Resolves the same keyboard, D-pad, and left-stick directions used by the base UI layer.
	if direction >= 0 and (event is InputEventJoypadMotion or event is InputEventJoypadButton): # Applies controller-only behavior without changing keyboard editing semantics.
		var focus: Control = get_viewport().gui_get_focus_owner() # Reads the current target before deciding whether this direction edits or navigates.
		if focus is OptionButton and (direction == SIDE_LEFT or direction == SIDE_RIGHT): # Uses horizontal directions to change the selected pack in place.
			_cycle_option_button(focus as OptionButton, -1 if direction == SIDE_LEFT else 1) # Moves exactly one option with wrapping for complete controller access.
			get_viewport().set_input_as_handled() # Prevents the same stick/D-pad press from moving UI focus away from the selector.
			return # Leaves the updated OptionButton selected.
		if focus is LineEdit: # Lets a controller escape text fields that otherwise reserve arrow-direction behavior for caret movement.
			if not _controller_navigation_repeat_ready(event): # Applies the same analog debounce as the base focus-navigation path.
				get_viewport().set_input_as_handled() # Suppresses native caret movement while waiting for the next deliberate controller step.
				return # Keeps the current focus until the repeat interval expires.
			UIFocus.navigate_controls(_navigation_controls(), focus, direction as Side) # Moves to the next control instead of trapping a controller inside an uneditable native field.
			get_viewport().set_input_as_handled() # Prevents native LineEdit caret movement from the handled controller direction.
			return # Completes the controller-only text-field escape path.
	super._input(event) # Preserves established A-on-GameButton, B/back, Start/pause, left-stick navigation, mouse interaction, and inspection dispatch.

func _navigation_controls() -> Array[Control]: # Gives controller text entry an isolated focus scope above every underlying menu and world HUD.
	if _controller_keyboard != null and _controller_keyboard.is_open(): # Detects the topmost controller-only modal before inspection or pause scopes.
		return UIFocus.controls_in(_controller_keyboard) # Restricts left-stick/D-pad/A input to visible keyboard keys and actions.
	return super._navigation_controls() # Preserves normal title, pause, inspection, page, market, shop, collection, and settings focus scopes.

func _go_back() -> void: # Closes controller text entry before delegating B/Escape behavior to lower UI layers.
	if _controller_keyboard != null and _controller_keyboard.is_open(): # Gives the keyboard first ownership of the universal back action.
		_controller_keyboard.cancel() # Discards temporary edits and restores the original LineEdit focus.
		return # Prevents B from also leaving the current gameplay destination.
	super._go_back() # Preserves inspection close, pause resume, overlay history, and gameplay pause behavior.

func _close_modals() -> void: # Clears controller text entry alongside existing pause, inspection, and toast state on route changes.
	if _controller_keyboard != null and _controller_keyboard.is_open(): # Handles explicit navigation while a text field is being edited.
		_controller_keyboard.cancel() # Discards unaccepted text before the field's page is hidden.
	super._close_modals() # Preserves all established modal and global pause cleanup.

func _focus_destination() -> void: # Chooses controller-friendly initial focus without weakening keyboard/mouse search behavior.
	if _collection.is_visible_in_tree() and _controller_input_active: # Avoids placing a controller directly into a native text caret on collection entry.
		_collection.focus_controller() # Selects the first actionable owned sticker or a safe empty-state fallback.
		return # Leaves the collection's controller focus established without the base search-first override.
	super._focus_destination() # Preserves search-first keyboard entry, settings focus, and physical-world primary actions for every other case.

func _route(destination: String) -> void: # Extends authoritative destination dispatch with the collector market world.
	if destination == "market": # Handles the one route unknown to the base GameUI implementation.
		if _controller is SpecialEditionGameController: # Requires the edition-aware root controller that owns the third physical world.
			(_controller as SpecialEditionGameController).show_market() # Transfers camera, environment, HUD, and market polling ownership through the controller.
		return # Prevents the base route matcher from ignoring the new destination.
	super._route(destination) # Preserves all established main-menu, book, packs, collection, and settings routing unchanged.

func _update_input_mode(event: InputEvent) -> void: # Tracks only meaningful device activity so stationary axes or incidental pointer events do not flicker UI behavior.
	if event is InputEventJoypadButton: # Treats deliberate gamepad button presses as immediate controller ownership.
		if (event as InputEventJoypadButton).pressed: # Ignores button releases because the corresponding press already established mode.
			_controller_input_active = true # Makes subsequent world entry and collection focus controller-native.
		return # Avoids classifying the same event as keyboard/mouse input.
	if event is InputEventJoypadMotion: # Treats substantial analog motion as controller ownership while ignoring resting-axis noise.
		if absf((event as InputEventJoypadMotion).axis_value) >= 0.30: # Requires a deliberate displacement above typical hardware drift.
			_controller_input_active = true # Switches world interaction and focus defaults to gamepad behavior.
		return # Leaves insignificant analog noise unable to change the current mode.
	if event is InputEventMouseButton: # Treats a real pointer click as an intentional switch back to mouse interaction.
		if (event as InputEventMouseButton).pressed: # Uses the press rather than release to establish device ownership immediately.
			_controller_input_active = false # Restores mouse-oriented physical placement and collection search focus.
		return # Completes pointer-button classification.
	if event is InputEventMouseMotion: # Uses meaningful mouse travel rather than stationary events to switch modes.
		if (event as InputEventMouseMotion).relative.length_squared() >= 4.0: # Filters tiny operating-system cursor jitter while a controller is in use.
			_controller_input_active = false # Restores mouse-oriented world pointing after deliberate movement.
		return # Completes pointer-motion classification.
	if event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).is_echo(): # Treats deliberate physical-keyboard input as non-controller ownership.
		_controller_input_active = false # Keeps native LineEdit editing and keyboard-first collection search behavior intact.

func _cycle_option_button(option: OptionButton, step: int) -> void: # Changes one native selector deterministically without opening a popup that may have platform-specific controller behavior.
	if option.disabled or option.item_count <= 0 or step == 0: # Rejects unavailable, empty, and no-op selector changes.
		return # Leaves the current authored option untouched.
	var current_index: int = option.selected if option.selected >= 0 else 0 # Normalizes an unselected control to the first available item.
	option.select(posmod(current_index + step, option.item_count)) # Wraps exactly one item forward or backward while the owning HUD polls the selected index.

func _controller_navigation_repeat_ready(event: InputEvent) -> bool: # Shares the base analog-repeat timing when controller directions are intercepted before GameUI can process them.
	if event is not InputEventJoypadMotion: # Treats discrete D-pad/button directions as immediately ready.
		return true # Allows every separate digital press to move exactly once.
	var now: int = Time.get_ticks_msec() # Reads the same monotonic clock used by the base navigation debounce.
	if now < _next_stick_navigation_msec: # Rejects another held-stick update before the established repeat interval.
		return false # Keeps focus stable until deliberate repeat timing permits another movement.
	_next_stick_navigation_msec = now + 180 # Matches the base UI's analog navigation repeat cadence.
	return true # Allows this intercepted controller direction to move focus once.
