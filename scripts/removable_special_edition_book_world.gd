class_name RemovableSpecialEditionBookWorld
extends SpecialEditionBookWorld

func _end_pointer_interaction(screen_position: Vector2) -> void: # Resolves clicks into placement-aware inspection while preserving the existing peel release behavior.
	if _active_sticker != null: # Gives an already activated peel first ownership of the matching release.
		_finish_active_peel() # Preserves normal physical peel completion and persistence.
		return # Completes the drag release without opening inspection.
	if _pressed_sticker == null: # Ignores releases that do not belong to any book sticker press.
		return # Leaves the book unchanged when no gesture owns the pointer.
	if screen_position.distance_to(_pressed_screen_position) >= PEEL_DRAG_THRESHOLD_PIXELS: # Preserves delayed peel activation for large release-only pointer jumps.
		_start_pressed_sticker_peel() # Converts the candidate into the established physical peel interaction.
		if _active_sticker != null: # Verifies that delayed peel activation succeeded.
			var release_page_point: Variant = _screen_to_page(screen_position) # Projects the final pointer position onto the page plane.
			if release_page_point is Vector3: # Applies only valid page-plane positions.
				_active_sticker.update_drag(release_page_point as Vector3) # Updates deformation to the actual release location.
			_finish_active_peel() # Persists the completed physical interaction.
		return # Prevents a drag from being interpreted as inspection.
	var runtime_id: int = _pressed_sticker.get_instance_id() # Resolves metadata for the exact clicked physical sticker.
	var sticker_key: String = str(_sticker_paths.get(runtime_id, "")) # Preserves the exact normal/rainbow/silver/gold identity used by inspection rendering.
	var placement_id: String = str(_sticker_ids.get(runtime_id, "")) # Captures the stable physical placement ID so duplicate copies remain independently removable.
	_pressed_sticker = null # Releases pointer ownership before the modal takes control.
	var removable_controller: RemovableSpecialEditionGameController = _controller as RemovableSpecialEditionGameController # Narrows the coordinator to the placement-removal integration.
	if removable_controller != null and removable_controller.show_book_sticker_inspection(sticker_key, placement_id): # Opens inspection with the exact placement removal context.
		_hud.set_status("inspect · return to collection if you want to move it out of the book") # Explains the reversible collection flow after a successful open.
	else: # Handles missing placement metadata or unexpected resource failures safely.
		_hud.set_status("this sticker could not be opened") # Reports the failed inspection without changing physical state.

func refresh_after_placement_removal() -> void: # Rebuilds the current spread after the controller deletes one persistent placement.
	_rebuild_active_spread() # Recreates only the visible spread from authoritative remaining placement records.
	_refresh_page_navigation() # Updates placement totals and page controls immediately after removal.
	_hud.set_status("returned to collection") # Confirms that ownership remains and the physical copy is now loose again.
