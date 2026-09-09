class_name RemovableStickerInspection
extends StickerInspection

@onready var _return_to_collection_button: Button = $bottom_bar/return_to_collection as Button # References the explicit action that removes the inspected physical placement from the book.

var _return_to_collection_action: Callable # Stores the exact placement-removal callback supplied by the book controller.

func configure_actions() -> void: # Binds the existing inspection controls plus the collection-return action without signals.
	super.configure_actions() # Preserves close, zoom, and reset behavior from the established inspection surface.
	(_return_to_collection_button as GameButton).bind_action(_return_to_collection) # Routes the new action through the same native button abstraction as the rest of the UI.

func set_return_to_collection_action(action: Callable) -> void: # Configures whether the currently inspected sticker can be removed from the book.
	_return_to_collection_action = action # Retains the exact placement callback for this modal session.
	_return_to_collection_button.visible = action.is_valid() # Shows removal only when inspection came from a removable physical book placement.
	_return_to_collection_button.disabled = not action.is_valid() # Prevents stale focus activation when no placement context exists.

func close_inspection() -> void: # Clears removal context whenever the modal closes.
	_return_to_collection_action = Callable() # Prevents a later inspection from reusing a stale physical placement callback.
	if is_instance_valid(_return_to_collection_button): # Protects teardown before the editor-authored button has completed ready state.
		_return_to_collection_button.visible = false # Hides the book-only action until another physical placement supplies context.
	super.close_inspection() # Preserves the established rendering shutdown and modal visibility behavior.

func _return_to_collection() -> void: # Removes the exact inspected placement and returns its owned copy to collection availability.
	if not _return_to_collection_action.is_valid(): # Rejects stale or non-book inspection sessions.
		return # Leaves the inspection unchanged when no authoritative removal callback exists.
	var action: Callable = _return_to_collection_action # Copies the callback before closing clears modal state.
	close_and_restore_focus() # Releases inspection input before the physical book is rebuilt.
	action.call() # Lets the authoritative controller remove the exact placement, refresh collection state, and rebuild the visible spread.
