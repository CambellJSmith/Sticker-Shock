class_name UIFocus extends RefCounted # Centralizes deterministic focus scopes for pages and modals.

static func controls_in(root: Node) -> Array[Control]: # Collects visible interactive controls in scene order.
	var controls: Array[Control] = [] # Holds the current scope's eligible controls.
	_collect(root, controls) # Traverses only the supplied interface subtree.
	return controls # Returns the focus scope without retaining scene references.

static func cycle_controls(controls: Array[Control], current: Control, backwards: bool) -> void: # Keeps tab navigation inside the active page or modal.
	if controls.is_empty(): # Handles an interface with no actionable content.
		return # Leaves focus untouched when no target exists.
	var index: int = controls.find(current) # Finds the current position within this scope.
	var step: int = -1 if backwards else 1 # Chooses navigation direction from the input.
	controls[posmod(index + step, controls.size())].grab_focus() # Wraps focus within this scope.

static func navigate_controls(controls: Array[Control], current: Control, direction: Side) -> void: # Resolves native directional neighbors inside the current scope.
	if controls.is_empty(): # Handles empty navigation scopes safely.
		return # Avoids selecting controls underneath a modal.
	if not controls.has(current): # Recovers focus when a route or filter hid its previous owner.
		controls[0].grab_focus() # Selects the first available action.
		return # Defers directional movement until focus exists.
	var next: Control = current.find_valid_focus_neighbor(direction) # Uses native spatial focus navigation.
	if controls.has(next): # Keeps spatial movement inside the active scope.
		next.grab_focus() # Selects the eligible spatial neighbor.
	else: # Handles boundaries without escaping into the background interface.
		cycle_controls(controls, current, direction == SIDE_TOP or direction == SIDE_LEFT) # Wraps within the current scope.

static func _collect(root: Node, controls: Array[Control]) -> void: # Walks editor-authored interface nodes recursively.
	if root is Control: # Applies visibility and focus rules to interface nodes.
		var control: Control = root as Control # Narrows the node to its UI type.
		if not control.is_visible_in_tree(): # Skips hidden pages and filtered collection entries.
			return # Excludes the entire hidden subtree.
		if control.focus_mode == Control.FOCUS_ALL and not (control is BaseButton and (control as BaseButton).disabled): # Includes native actionable controls only.
			controls.append(control) # Preserves predictable scene-order tab navigation.
	for child: Node in root.get_children(): # Visits each remaining descendant once per navigation event.
		_collect(child, controls) # Adds eligible controls without per-frame traversal.
