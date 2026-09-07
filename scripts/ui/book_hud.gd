class_name BookHUD extends Control # Owns book guidance, page navigation, and first-session onboarding.

@onready var _status: Label = %status as Label # Presents the current sticker interaction in plain language.
@onready var _hint: Label = %hint as Label # Gives supporting controls without covering the book.
@onready var _previous: GameButton = %previous_button as GameButton # Turns to the previous saved spread.
@onready var _next: GameButton = %next_button as GameButton # Turns to the next saved spread.
@onready var _cancel: GameButton = %cancel_button as GameButton # Cancels placement without consuming its pending copy.
@onready var _empty: Control = %empty as Control # Introduces collecting only when the book is genuinely empty.

var _book_state: StickerBookState # Reads persisted page and placement state.
var _placing: bool = false # Tracks whether manual placement owns the book interaction.

func configure(world: BookWorld, book_state: StickerBookState, controller: GameController) -> void: # Binds HUD controls to their owning gameplay component.
	_book_state = book_state # Retains the authoritative page model.
	_previous.bind_action(world.request_spread_change.bind(-1)) # Uses native button semantics for page turns.
	_next.bind_action(world.request_spread_change.bind(1)) # Binds the forward page action.
	_cancel.bind_action(world.cancel_manual_placement) # Returns a selected copy to its open pack.
	(%open_packs as GameButton).bind_action(controller.show_shop) # Gives the blank book a clear next step.
	refresh() # Initializes page bounds and the onboarding state.

func refresh() -> void: # Updates navigation only when page or placement state changes.
	var spread: int = _book_state.get_active_spread_index() # Reads the currently saved spread.
	(%pages as Label).text = "%02d — %02d" % [spread * 2 + 1, spread * 2 + 2] # Labels the visible page pair compactly.
	_previous.disabled = spread <= 0 # Disables backward navigation at the first spread.
	_next.disabled = spread >= _book_state.get_spread_count() - 1 # Disables forward navigation at the final saved spread.
	_hint.text = "spread %d of %d · click to inspect · drag to peel" % [spread + 1, _book_state.get_spread_count()] # Keeps page progress and core controls together.
	_empty.visible = _book_state.get_placement_count() == 0 and not _placing # Avoids overlaying guidance while placing the first sticker.

func set_placing(placing: bool) -> void: # Switches between normal browsing and manual-placement controls.
	_placing = placing # Retains placement mode for onboarding visibility.
	_cancel.visible = placing # Offers cancellation only when a copy is being positioned.
	refresh() # Synchronizes the empty-book state with interaction mode.

func set_status(message: String) -> void: # Updates contextual feedback without exposing label nodes.
	_status.text = message # Shows concise interaction guidance in the footer.

func owns_pointer(position: Vector2) -> bool: # Reserves HUD surfaces from physical picking.
	if (%footer as Control).get_global_rect().has_point(position): # Includes empty space inside the footer toolbar.
		return true # Prevents the toolbar background from starting a peel.
	return _empty.visible and (_empty.get_node("panel") as Control).get_global_rect().has_point(position) # Protects the first-session call to action.

func focus_primary() -> void: # Selects a useful keyboard action on book entry.
	if _placing: # Prioritizes the safe exit from manual placement.
		_cancel.grab_focus() # Focuses cancellation while the mouse positions a sticker.
	elif _empty.visible: # Prioritizes collecting for a new book.
		(%open_packs as GameButton).grab_focus() # Gives new players the next step.
	elif not _next.disabled: # Supports advancing through an existing book.
		_next.grab_focus() # Focuses forward page navigation.
	elif not _previous.disabled: # Handles the last spread of a multi-spread book.
		_previous.grab_focus() # Focuses the available backward action.
