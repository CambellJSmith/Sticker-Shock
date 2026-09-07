class_name GameButton extends Button # Uses native button input, focus, and release behavior.

var _action: Callable = Callable() # Keeps the owning component's action private.

func bind_action(action: Callable) -> void: # Assigns a direct callback without connecting signals.
	_action = action # Stores the action supplied by the owner.

func invoke() -> void: # Gives controller confirmation the same guards as pointer activation.
	if is_visible_in_tree() and not disabled: # Rejects unavailable or hidden actions.
		_pressed() # Runs the same callback as a native button release.

func _pressed() -> void: # Handles Godot's native button activation hook.
	if not disabled and _action.is_valid(): # Rejects unavailable actions and expired owners.
		_action.call() # Dispatches directly to the component responsible for this action.
