class_name BookHUD extends Control # Owns book guidance, page navigation, controller cursor presentation, and first-session onboarding.

@onready var _status: Label = %status as Label # Presents the current sticker interaction in plain language.
@onready var _hint: Label = %hint as Label # Gives supporting controls without covering the book.
@onready var _previous: GameButton = %previous_button as GameButton # Turns to the previous saved spread.
@onready var _next: GameButton = %next_button as GameButton # Turns to the next saved spread.
@onready var _cancel: GameButton = %cancel_button as GameButton # Cancels placement without consuming its pending copy.
@onready var _empty: Control = %empty as Control # Introduces collecting only when the book is genuinely empty.
@onready var _controller_cursor: Control = %controller_cursor as Control # Displays the right-stick physical interaction point independently from native UI focus.

var _book_state: StickerBookState # Reads persisted page and placement state.
var _placing: bool = false # Tracks whether manual placement owns the book interaction.
var _controller_mode: bool = false # Tracks whether book guidance should describe gamepad physical controls instead of mouse gestures.

func configure(world: BookWorld, book_state: StickerBookState, controller: GameController) -> void: # Binds HUD controls to their owning gameplay component.
	_book_state = book_state # Retains the authoritative page model.
	_previous.bind_action(world.request_spread_change.bind(-1)) # Uses native button semantics for page turns.
	_next.bind_action(world.request_spread_change.bind(1)) # Binds the forward page action.
	_cancel.bind_action(world.cancel_manual_placement) # Returns a selected copy to its open pack.
	(%open_packs as GameButton).bind_action(controller.show_shop) # Gives the blank book a clear next step.
	_controller_cursor.visible = false # Keeps the physical right-stick cursor hidden until controller input owns the book.
	refresh() # Initializes page bounds and the onboarding state.

func refresh() -> void: # Updates navigation and context guidance only when page, placement, or input mode changes.
	var spread: int = _book_state.get_active_spread_index() # Reads the currently saved spread.
	(%pages as Label).text = "%02d — %02d" % [spread * 2 + 1, spread * 2 + 2] # Labels the visible page pair compactly.
	_previous.disabled = spread <= 0 # Disables backward navigation at the first spread.
	_next.disabled = spread >= _book_state.get_spread_count() - 1 # Disables forward navigation at the final saved spread.
	if _controller_mode: # Describes the dedicated gamepad split between UI navigation and physical sticker interaction.
		_hint.text = "spread %d of %d · right stick aim · X inspect / peel" % [spread + 1, _book_state.get_spread_count()] # Keeps controller mechanics discoverable without taking over left-stick menu focus.
	else: # Preserves existing mouse guidance for players who most recently used pointer input.
		_hint.text = "spread %d of %d · click to inspect · drag to peel" % [spread + 1, _book_state.get_spread_count()] # Keeps page progress and core mouse controls together.
	_empty.visible = _book_state.get_placement_count() == 0 and not _placing # Avoids overlaying guidance while placing the first sticker.

func set_placing(placing: bool) -> void: # Switches between normal browsing and manual-placement controls.
	_placing = placing # Retains placement mode for onboarding visibility.
	_cancel.visible = placing # Offers cancellation only when a copy is being positioned.
	refresh() # Synchronizes the empty-book state and current controller/mouse hint with interaction mode.

func set_controller_mode(controller_mode: bool) -> void: # Updates book guidance when the application changes between controller and mouse/keyboard ownership.
	if _controller_mode == controller_mode: # Avoids redundant label work while the same input device remains active.
		return # Leaves current guidance and cursor state untouched.
	_controller_mode = controller_mode # Stores the newly active input family.
	if not controller_mode: # Hides the physical controller cursor as soon as mouse/keyboard input retakes ownership.
		_controller_cursor.visible = false # Prevents a stale gamepad pointer from remaining over normal mouse interaction.
	refresh() # Rewrites the compact footer hint for the newly active input family.

func set_controller_cursor(screen_position: Vector2, cursor_visible: bool) -> void: # Places the controller-only physical pointer at an exact viewport position.
	_controller_cursor.visible = cursor_visible # Shows the crosshair only while the controller owns book-world physical interaction.
	if not cursor_visible: # Skips layout updates when the cursor is intentionally hidden.
		return # Leaves its previous position cached harmlessly for later reactivation.
	_controller_cursor.position = screen_position - _controller_cursor.size * 0.5 # Centers the crosshair on the exact screen-space ray used for picking, peeling, and placement.

func set_status(message: String) -> void: # Updates contextual feedback without exposing label nodes.
	_status.text = message # Shows concise interaction guidance in the footer.

func owns_pointer(position: Vector2) -> bool: # Reserves HUD surfaces from physical picking.
	if (%footer as Control).get_global_rect().has_point(position): # Includes empty space inside the footer toolbar.
		return true # Prevents the toolbar background from starting a peel.
	return _empty.visible and (_empty.get_node("panel") as Control).get_global_rect().has_point(position) # Protects the first-session call to action.

func focus_primary() -> void: # Selects a useful native navigation action on book entry while physical controller interaction remains available through X/right stick.
	if _placing: # Prioritizes the safe exit from manual placement.
		_cancel.grab_focus() # Keeps A available for cancellation while X/right stick positions the sticker physically.
	elif _empty.visible: # Prioritizes collecting for a new book.
		(%open_packs as GameButton).grab_focus() # Gives new players the next step.
	elif not _next.disabled: # Supports advancing through an existing book.
		_next.grab_focus() # Focuses forward page navigation.
	elif not _previous.disabled: # Handles the last spread of a multi-spread book.
		_previous.grab_focus() # Focuses the available backward action.
