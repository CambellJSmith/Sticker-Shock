class_name RemovableSpecialEditionBookWorld
extends SpecialEditionBookWorld

const CONTROLLER_CURSOR_SPEED: float = 720.0 # Moves the physical right-stick cursor quickly enough to cross a full supported viewport without making precise sticker placement difficult.
const CONTROLLER_CURSOR_MARGIN: float = 12.0 # Keeps the controller cursor clear of the persistent navigation chrome and book footer edges.
const CONTROLLER_NAV_WIDTH: float = 160.0 # Matches the editor-authored persistent left navigation rail reserved from physical book interaction.
const CONTROLLER_TOP_HEIGHT: float = 64.0 # Matches the editor-authored top status bar reserved from physical book interaction.
const CONTROLLER_FOOTER_HEIGHT: float = 84.0 # Matches the editor-authored book footer reserved from physical book interaction.

var _controller_cursor_position: Vector2 = Vector2.ZERO # Stores the independent physical pointer used by the right stick without moving the operating-system mouse.
var _controller_cursor_initialized: bool = false # Tracks whether the physical cursor has received a valid viewport-relative starting point.
var _peel_target_sticker: Sticker # Stores the settled sticker currently owning the glowing nearest-alpha-edge peel handle.
var _peel_target_world_point: Vector3 = Vector3.ZERO # Stores the exact page-plane alpha-edge point currently shown by the glowing peel marker.
var _pressed_pointer_page_point: Vector3 = Vector3.ZERO # Stores the real page-plane pointer position at press independently from the edge-constrained material peel origin.
var _edge_drag_mapping_active: bool = false # Remaps later mouse/controller movement into edge-origin-relative drag coordinates without adding the pointer-to-edge offset as fake peel movement.

func set_active(active: bool) -> void: # Extends normal book activation with controller cursor, alpha-edge peel targeting, and guidance ownership.
	super.set_active(active) # Preserves camera, environment, visibility, interaction suspension, and any carried placement preview behavior.
	if not active: # Clears targeting presentation whenever this physical world relinquishes ownership.
		_clear_peel_target() # Prevents a stale glowing edge handle remaining above another destination or modal.
	var controller_mode: bool = active and _is_controller_mode() # Resolves the active input family only when this physical world owns presentation.
	_hud.set_controller_mode(controller_mode) # Keeps book footer guidance synchronized with the actual physical interaction device.
	if not controller_mode: # Removes the gamepad crosshair whenever mouse/keyboard or another destination owns the book.
		_hud.set_controller_cursor(Vector2.ZERO, false) # Hides the controller-only pointer without moving the operating-system cursor.
		if active and _manual_preview == null: # Gives an already positioned desktop mouse an immediate peel-edge preview on book entry.
			_update_peel_target(get_viewport().get_mouse_position()) # Resolves the current hover target without requiring an extra mouse twitch after navigation.
		return # Leaves mouse-oriented world behavior exactly as established.
	_ensure_controller_cursor() # Creates a safe initial physical aim point inside the unobscured book viewport.
	_hud.set_controller_cursor(_controller_cursor_position, true) # Shows the crosshair at the same screen coordinate used for world ray projection.
	if _manual_preview != null: # Repositions a carried collection sticker from the controller cursor instead of the unrelated mouse position.
		_update_manual_preview(_controller_cursor_position) # Reuses the exact page projection and full-sticker fit validation already used by mouse placement.
		_refresh_controller_placement_status() # Explains whether X can currently commit the controller-positioned sticker.
	else: # Shows the peel handle immediately when the remembered controller cursor already rests on a settled sticker.
		_update_peel_target(_controller_cursor_position) # Uses the same nearest-alpha-edge targeting path as desktop hover.

func begin_manual_placement(sticker_key: String, pending_index: int) -> bool: # Starts exact-edition collection placement with controller positioning when a gamepad owns input.
	_clear_peel_target() # Gives the carried collection copy exclusive physical targeting presentation before the placement preview appears.
	var started: bool = super.begin_manual_placement(sticker_key, pending_index) # Preserves edition material setup, reservation identity, page-fit state, and mouse placement support.
	if not started: # Rejects controller setup when the established physical preview could not be created.
		return false # Reports the original placement failure unchanged.
	if _is_controller_mode(): # Replaces the mouse-derived initial target only for a player currently using a controller.
		_ensure_controller_cursor() # Guarantees a valid unobscured screen-space placement target exists.
		_hud.set_controller_mode(true) # Switches footer help to the right-stick/X controller mapping immediately.
		_hud.set_controller_cursor(_controller_cursor_position, true) # Shows the independent physical placement crosshair.
		_update_manual_preview(_controller_cursor_position) # Projects the reserved sticker beneath the gamepad cursor rather than the operating-system mouse.
		_refresh_controller_placement_status() # Shows the valid/invalid X placement instruction after the initial projection.
	return true # Confirms the selected collection copy entered the established physical placement flow.

func _process(delta: float) -> void: # Preserves collection-return timing while continuously driving controller physical book interaction and alpha-edge peel targeting.
	super._process(delta) # Keeps the special-edition post-placement return-to-collection timer unchanged.
	if not _active or _controller == null: # Avoids hidden-world input polling and startup access before the game coordinator exists.
		return # Leaves inactive book simulation untouched.
	var controller_mode: bool = _is_controller_mode() # Reads the shared most-recent-input mode once for this frame.
	_hud.set_controller_mode(controller_mode) # Updates help and stale-cursor visibility only when the input family changes.
	if not controller_mode: # Gives mouse/keyboard users the inherited pointer event path exclusively.
		_hud.set_controller_cursor(Vector2.ZERO, false) # Hides the gamepad crosshair as soon as pointer/keyboard input retakes ownership.
		return # Avoids reading right-stick actions while controller mode is inactive.
	if _controller.is_gameplay_input_blocked(): # Suspends physical right-stick interaction beneath pause, inspection, collection, settings, and controller-keyboard modals.
		_hud.set_controller_cursor(Vector2.ZERO, false) # Removes the crosshair while another modal visually owns the screen.
		_clear_peel_target() # Removes the edge handle together with physical book ownership while a modal is active.
		return # Leaves current physical placement and peel state safely suspended until the modal closes.
	_ensure_controller_cursor() # Re-establishes a valid cursor after a resize or first controller interaction.
	var movement: Vector2 = Input.get_vector(&"StickRight_West", &"StickRight_East", &"StickRight_North", &"StickRight_South") # Reads the dedicated physical hand stick independently from left-stick UI navigation.
	if movement.length_squared() > 0.0001: # Updates world aim only for meaningful right-stick displacement beyond the InputMap deadzone.
		_controller_cursor_position += movement * CONTROLLER_CURSOR_SPEED * delta # Converts normalized stick direction into frame-rate-independent screen-space travel.
		_clamp_controller_cursor() # Prevents the physical cursor entering persistent navigation, top-bar, or footer chrome.
	_hud.set_controller_cursor(_controller_cursor_position, true) # Keeps the visible crosshair exactly synchronized with the world ray coordinate every controller frame.
	if _manual_preview != null: # Gives selected collection-copy placement exclusive physical-cursor ownership.
		_clear_peel_target() # Keeps the peel-origin dot hidden while the right stick is positioning a new sticker instead.
		if movement.length_squared() > 0.0001: # Reprojects only when the right-stick target actually changes.
			_update_manual_preview(_controller_cursor_position) # Uses the established page-plane and complete-sheet bounds validation at the gamepad target.
			_refresh_controller_placement_status() # Tells the player whether the moved target is valid for X placement.
		return # Prevents a carried new sticker from also selecting or peeling existing page stickers.
	if _pressed_sticker == null and _active_sticker == null: # Lets the free right-stick cursor continuously choose an edge point before the player commits to X.
		_update_peel_target(_controller_cursor_position) # Moves the glowing dot around the targeted sticker's outer alpha contour toward the controller cursor.
	if Input.is_action_pressed(&"Button_X"): # Treats X hold as the physical grab while A remains reserved for focused interface controls.
		if _pressed_sticker != null and _active_sticker == null and _controller_cursor_position.distance_to(_pressed_screen_position) >= PEEL_DRAG_THRESHOLD_PIXELS: # Converts a held X plus deliberate right-stick motion into the same delayed realistic peel used by mouse dragging.
			_start_pressed_sticker_peel() # Freezes the selected alpha-edge point as the physical peel origin before deformation begins.
		if _active_sticker != null: # Updates physical deformation only after the same movement threshold has confirmed peel intent.
			var page_point: Variant = _screen_to_page(_controller_cursor_position) # Projects and edge-origin-remaps the controller crosshair onto the stable page plane used by mouse peeling.
			if page_point is Vector3: # Rejects any temporary cursor ray that cannot intersect the page plane safely.
				_active_sticker.update_drag(page_point as Vector3) # Feeds the controller movement delta through the identical realistic peel simulation from the frozen edge origin.
				if _active_sticker.is_carried(): # Detects when the sheet has completely detached and can be repositioned across the spread.
					_hud.set_status("right stick to move · release X to place") # Describes the complete controller carry-and-drop interaction.
				else: # Handles the still-attached portion of the realistic peel.
					_hud.set_status("peeling from the white dot · release X to restick") # Makes the new visible edge-origin rule explicit during the curl.

func _input(event: InputEvent) -> void: # Adds controller physical press/release semantics while preserving the complete inherited mouse gesture path.
	super._input(event) # Lets the established mouse release owner finish gestures exactly as before.
	if not _active or _controller == null or _controller.is_gameplay_input_blocked(): # Rejects controller world input while hidden, unconfigured, paused, inspected, or covered by a full-screen page.
		return # Leaves the current topmost interface in sole control.
	if not _is_controller_mode(): # Keeps X from becoming a second physical input path when mouse/keyboard currently owns interaction.
		return # Leaves original mouse picking and native UI semantics unchanged.
	if not event.is_action(&"Button_X"): # Ignores every controller action except the dedicated physical book interaction button.
		return # Leaves A/B/Start, shoulders, inspection controls, and left-stick navigation to their existing owners.
	_ensure_controller_cursor() # Guarantees the event uses a valid physical screen-space target even if X is the first gamepad input in the book.
	_hud.set_controller_cursor(_controller_cursor_position, true) # Shows the exact target before any selection or placement result is evaluated.
	if event.is_action_pressed(&"Button_X"): # Starts a physical gamepad interaction on the press just like mouse button-down captures a sticker.
		if _manual_preview != null: # Treats X as the explicit stick-down action while a collection copy is being positioned.
			_commit_manual_placement() # Reuses the authoritative pending-identity validation and persistent placement transaction.
			get_viewport().set_input_as_handled() # Prevents the placement press from reaching any future controller-aware node underneath the book.
			return # Completes the one-shot placement action without beginning an existing-sticker grab.
		_begin_pointer_interaction(_controller_cursor_position) # Captures the current nearest alpha-edge point while preserving tap-versus-drag intent.
		if _pressed_sticker != null: # Confirms a selectable physical sticker was captured beneath the crosshair.
			_hud.set_status("white dot is the peel point · release X to inspect · move while held to peel") # Exposes the frozen edge handle before the player commits to physical movement.
		else: # Handles bare paper or a sticker still settling.
			_hud.set_status("right stick aim · X selects a sticker") # Keeps the controller interaction discoverable after an empty pick.
		get_viewport().set_input_as_handled() # Prevents another controller-aware surface from treating this physical grab as its own X action.
		return # Leaves the captured candidate waiting for motion threshold or release.
	if event.is_action_released(&"Button_X") and (_active_sticker != null or _pressed_sticker != null): # Completes the matching gamepad grab regardless of whether it stayed a tap or became a peel.
		_end_pointer_interaction(_controller_cursor_position) # Reuses exact-edition inspection or established physical peel persistence depending on gesture state.
		get_viewport().set_input_as_handled() # Ensures one release cannot also trigger another controller interaction owner.

func _unhandled_input(event: InputEvent) -> void: # Extends inherited mouse behavior with continuous alpha-edge hover targeting while leaving all gesture ownership in the established book controller.
	super._unhandled_input(event) # Preserves mouse placement, tap-to-inspect, thresholded peeling, and active drag updates through the overridden edge-aware helpers below.
	if not _active or _controller == null or _controller.is_gameplay_input_blocked(): # Rejects hover targeting while the book is hidden or covered by a modal surface.
		_clear_peel_target() # Prevents a stale edge marker remaining visible when physical input is unavailable.
		return # Leaves the topmost interface in sole control.
	if event is not InputEventMouseMotion: # Updates free desktop edge targeting only when the pointer actually moves.
		return # Leaves button presses/releases to the inherited gesture state machine.
	if _is_controller_mode(): # Prevents incidental mouse motion from competing with the right-stick target after controller mode has been established.
		return # Leaves controller targeting to the continuous process path above.
	var mouse_motion: InputEventMouseMotion = event as InputEventMouseMotion # Narrows the event for strongly typed pointer coordinates.
	if _manual_preview != null or _active_sticker != null: # Hides the peel preview while placing a new sticker or actively deforming one.
		_clear_peel_target() # Removes the dot until normal resting-sticker targeting resumes.
		return # Leaves the current physical interaction visually unambiguous.
	if _pressed_sticker == null: # Allows the free mouse to move the dot, but freezes it as soon as a press captures the chosen edge point.
		_update_peel_target(mouse_motion.position) # Projects the hover point onto the closest real outer alpha-contour segment.

func _begin_pointer_interaction(screen_position: Vector2) -> void: # Captures one settled sticker while freezing the nearest outer-alpha point as the potential peel origin.
	if _active_sticker != null or _pressed_sticker != null: # Prevents a second press from stealing gesture ownership.
		return # Keeps one deterministic sticker candidate until the matching release.
	_update_peel_target(screen_position) # Ensures a button press without prior motion still resolves the correct current sticker and edge point.
	super._begin_pointer_interaction(screen_position) # Reuses authoritative ray picking, settle guards, tap-versus-drag threshold state, and player feedback.
	if _pressed_sticker == null: # Handles bare paper, settling stickers, and any failed inherited selection.
		_clear_peel_target() # Removes any hover marker that did not become a valid press candidate.
		return # Leaves the inherited failure status intact.
	var pointer_page_point: Variant = super._screen_to_page(screen_position) # Reads the real press position on the page without active-drag remapping.
	if pointer_page_point is not Vector3: # Rejects the unlikely case of a camera ray that cannot reach the page plane reliably.
		_pressed_sticker = null # Releases the inherited candidate because its movement origin cannot be established safely.
		_clear_peel_target() # Removes the frozen edge handle together with the invalid press.
		return # Leaves no partially initialized peel state behind.
	_pressed_pointer_page_point = pointer_page_point as Vector3 # Stores the true pointer origin so only later directional movement contributes to peel displacement.
	_pressed_page_point = _get_closest_peel_edge_world(_pressed_sticker, _pressed_pointer_page_point) # Replaces the old arbitrary clicked material point with the exact nearest exterior alpha-boundary point.
	_peel_target_sticker = _pressed_sticker # Keeps targeting ownership on the captured physical sticker while the press waits for movement intent.
	_peel_target_world_point = _pressed_page_point # Freezes the visible dot exactly where a future drag will begin peeling.
	_hud.set_peel_target(_camera.unproject_position(_peel_target_world_point), true, true) # Brightens the dot to communicate that this alpha-edge point is now armed and no longer follows the pointer.

func _start_pressed_sticker_peel() -> void: # Converts the frozen alpha-edge press candidate into the established realistic peel without treating pointer-to-edge offset as drag movement.
	if _pressed_sticker == null or _active_sticker != null: # Rejects activation without a unique settled candidate.
		return # Leaves current gesture state unchanged when no peel can begin.
	_edge_drag_mapping_active = true # Enables edge-origin-relative pointer remapping before the inherited activation transfers ownership into the physical Sticker.
	super._start_pressed_sticker_peel() # Preserves restacking, persistence safety, stack height, and shader drag initialization while using the frozen edge point stored in _pressed_page_point.
	if _active_sticker == null: # Detects any unexpected inherited activation failure defensively.
		_edge_drag_mapping_active = false # Disables remapping when no active physical peel actually owns input.
	_clear_peel_target() # Hides the preview dot once the sticker itself visibly begins curling from that exact location.

func _screen_to_page(screen_position: Vector2) -> Variant: # Preserves normal page projection while remapping active peel movement so the edge origin and real pointer origin remain independent.
	var raw_page_point: Variant = super._screen_to_page(screen_position) # Resolves the actual mouse/controller ray intersection through the established camera/page-plane implementation.
	if raw_page_point is not Vector3: # Preserves inherited projection failure semantics unchanged.
		return raw_page_point # Leaves callers to handle the invalid projection exactly as before.
	if not _edge_drag_mapping_active or _active_sticker == null: # Uses normal physical page coordinates outside an active edge-origin peel.
		return raw_page_point # Preserves placement, targeting, page navigation, and every non-peel projection path.
	var raw_point: Vector3 = raw_page_point as Vector3 # Narrows the valid current pointer position for movement-delta calculation.
	return _pressed_page_point + (raw_point - _pressed_pointer_page_point) # Applies only actual post-press pointer movement to the frozen alpha-edge origin, eliminating artificial displacement from an interior press to its edge handle.

func _finish_active_peel() -> void: # Finishes the inherited realistic peel and releases edge-origin movement remapping for subsequent targeting.
	super._finish_active_peel() # Preserves partial resticking, detached landing, persistence, page reassignment, and stack-order updates.
	_edge_drag_mapping_active = false # Returns page projection to normal coordinates immediately after the gesture releases physical ownership.
	_pressed_pointer_page_point = Vector3.ZERO # Clears the no-longer-needed real press origin for the completed gesture.
	_clear_peel_target() # Keeps the edge marker absent while the released sticker autonomously settles back onto the page.

func _change_spread(direction: int) -> void: # Keeps controller placement synchronized while clearing peel targeting before visible sticker nodes change.
	_clear_peel_target() # Prevents a marker tied to the old spread surviving reconstruction or page navigation.
	super._change_spread(direction) # Preserves established page bounds, persistence, reconstruction, and mouse-preview reproject behavior.
	if _manual_preview != null and _is_controller_mode(): # Corrects the inherited mouse-based preview target only for active gamepad placement.
		_ensure_controller_cursor() # Keeps the existing right-stick position inside current viewport bounds after the page change.
		_update_manual_preview(_controller_cursor_position) # Projects the carried collection sticker onto the new spread at the controller cursor.
		_refresh_controller_placement_status() # Re-evaluates whether X can place the complete sticker on the new page pair.
	elif _manual_preview == null and _is_controller_mode(): # Re-evaluates the remembered right-stick target on the newly visible spread immediately.
		_update_peel_target(_controller_cursor_position) # Moves the dot to any settled sticker now under the controller cursor on the new pages.

func suspend_interaction() -> void: # Resolves controller and mouse physical gestures before modal or destination ownership changes.
	super.suspend_interaction() # Preserves active-peel completion and pending-click cancellation from the established book interaction path.
	_edge_drag_mapping_active = false # Ensures modal/destination suspension can never leave page projection in the edge-relative drag coordinate space.
	_pressed_pointer_page_point = Vector3.ZERO # Clears any frozen pointer origin abandoned by a cancelled pending press.
	_clear_peel_target() # Hides the glowing edge handle while another presentation surface owns the screen.
	_hud.set_controller_cursor(Vector2.ZERO, false) # Hides the physical crosshair while another presentation surface takes ownership.

func _end_pointer_interaction(screen_position: Vector2) -> void: # Resolves clicks or X taps into placement-aware inspection while preserving edge-origin physical peel release behavior.
	if _active_sticker != null: # Gives an already activated peel first ownership of the matching release.
		_finish_active_peel() # Preserves normal physical peel completion and clears edge-relative mapping.
		return # Completes the drag release without opening inspection.
	if _pressed_sticker == null: # Ignores releases that do not belong to any book sticker press.
		_clear_peel_target() # Removes any stale target left after an externally cancelled press.
		return # Leaves the book unchanged when no gesture owns the pointer.
	if screen_position.distance_to(_pressed_screen_position) >= PEEL_DRAG_THRESHOLD_PIXELS: # Preserves delayed peel activation for large release-only pointer jumps.
		_start_pressed_sticker_peel() # Converts the candidate into the established physical peel from the frozen white-dot edge point.
		if _active_sticker != null: # Verifies that delayed peel activation succeeded.
			var release_page_point: Variant = _screen_to_page(screen_position) # Projects and remaps the final mouse or controller position into edge-origin-relative movement coordinates.
			if release_page_point is Vector3: # Applies only valid page-plane positions.
				_active_sticker.update_drag(release_page_point as Vector3) # Updates deformation to the actual release movement relative to the frozen edge origin.
			_finish_active_peel() # Persists the completed physical interaction and clears edge targeting state.
		return # Prevents a drag from being interpreted as inspection.
	var runtime_id: int = _pressed_sticker.get_instance_id() # Resolves metadata for the exact clicked or controller-selected physical sticker.
	var sticker_key: String = str(_sticker_paths.get(runtime_id, "")) # Preserves the exact normal/rainbow/silver/gold identity used by inspection rendering.
	var placement_id: String = str(_sticker_ids.get(runtime_id, "")) # Captures the stable physical placement ID so duplicate copies remain independently removable.
	_pressed_sticker = null # Releases pointer ownership before the modal takes control.
	_pressed_pointer_page_point = Vector3.ZERO # Clears the frozen real pointer origin because this gesture stayed an inspection tap.
	_edge_drag_mapping_active = false # Guarantees normal page projection before opening the independent inspection modal.
	_clear_peel_target() # Removes the white edge dot while inspection visually owns the selected sticker.
	var removable_controller: RemovableSpecialEditionGameController = _controller as RemovableSpecialEditionGameController # Narrows the coordinator to the placement-removal integration.
	if removable_controller != null and removable_controller.show_book_sticker_inspection(sticker_key, placement_id): # Opens inspection with the exact placement removal context.
		_hud.set_status("inspect · return to collection if you want to move it out of the book") # Explains the reversible collection flow after a successful open.
	else: # Handles missing placement metadata or unexpected resource failures safely.
		_hud.set_status("this sticker could not be opened") # Reports the failed inspection without changing physical state.

func refresh_after_placement_removal() -> void: # Rebuilds the current spread after the controller deletes one persistent placement.
	_clear_peel_target() # Releases any edge target referencing the physical sticker node that is about to be reconstructed or removed.
	_rebuild_active_spread() # Recreates only the visible spread from authoritative remaining placement records.
	_refresh_page_navigation() # Updates placement totals and page controls immediately after removal.
	_hud.set_status("returned to collection") # Confirms that ownership remains and the physical copy is now loose again.

func _update_peel_target(screen_position: Vector2) -> void: # Moves the glowing peel handle to the exterior alpha-border point nearest the current free mouse or controller cursor.
	if _manual_preview != null or _active_sticker != null or _pressed_sticker != null: # Gives placement and committed gestures exclusive control instead of moving the handle underneath them.
		return # Leaves a pending pressed marker frozen and active peels hidden until the gesture resolves.
	if _controller != null and (_controller.is_gameplay_input_blocked() or _controller.is_pointer_over_game_ui(screen_position)): # Rejects physical targeting beneath modal or persistent screen-space interface controls.
		_clear_peel_target() # Removes any previous sticker target when the pointer enters UI-owned screen space.
		return # Leaves native interface interaction unambiguous.
	if _hud.owns_pointer(screen_position): # Rejects the book footer and empty-book onboarding panel independently from the global UI shell.
		_clear_peel_target() # Hides the edge dot whenever the book HUD itself owns the pointer.
		return # Prevents HUD chrome from selecting stickers behind it.
	var selected_sticker: Sticker = _pick_sticker(screen_position) # Ray-picks the top physical sticker under the free pointer using the established sticker-only collision layer.
	if selected_sticker == null or not selected_sticker.can_begin_drag(): # Requires one fully settled physical copy before offering a peel origin.
		_clear_peel_target() # Removes the marker over bare paper and while landing/returning stickers are not manipulable.
		return # Waits until a settled sticker is actually targeted.
	var page_point: Variant = super._screen_to_page(screen_position) # Projects the free pointer onto the stable flat page without any active-drag remapping.
	if page_point is not Vector3: # Handles camera rays that cannot reach the page plane reliably.
		_clear_peel_target() # Removes the marker rather than presenting an edge point without a corresponding drag plane position.
		return # Leaves physical targeting idle until projection becomes valid.
	var edge_world_point: Vector3 = _get_closest_peel_edge_world(selected_sticker, page_point as Vector3) # Finds the continuous nearest point on this sticker's cached non-hole outer alpha contour.
	_peel_target_sticker = selected_sticker # Retains the target identity so press can freeze the exact same physical sticker and border location.
	_peel_target_world_point = edge_world_point # Stores the current world-space peel handle on the page plane.
	_hud.set_peel_target(_camera.unproject_position(edge_world_point), true, false) # Places the glowing screen-space dot directly over the real alpha-edge position while it follows the free pointer.

func _pick_sticker(screen_position: Vector2) -> Sticker: # Finds the top physical Sticker under one screen position without starting any interaction state.
	var ray_origin: Vector3 = _camera.project_ray_origin(screen_position) # Converts the pointer into a world-space camera ray origin.
	var ray_direction: Vector3 = _camera.project_ray_normal(screen_position) # Converts the pointer into the matching normalized world-space ray direction.
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(ray_origin, ray_origin + ray_direction * PICK_DISTANCE, 1) # Creates a sticker-only query using the same collision layer as inherited interaction.
	query.collide_with_areas = true # Allows intersection with Sticker Area3D picking volumes.
	query.collide_with_bodies = false # Excludes unrelated book geometry from edge-target selection.
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query) # Finds the nearest physical sticker beneath the pointer.
	if hit.is_empty(): # Handles bare paper or transparent space outside every sticker picking rectangle.
		return null # Reports no target without creating gesture state.
	var collider: Variant = hit.get("collider") # Reads the selected physics object without assuming every future layer-one area is a sticker.
	if collider is not Sticker: # Rejects unrelated areas defensively.
		return null # Keeps peel targeting isolated from non-sticker interactables.
	return collider as Sticker # Returns the top physical sticker for read-only edge targeting.

func _get_closest_peel_edge_world(sticker: Sticker, pointer_page_point: Vector3) -> Vector3: # Converts a page pointer into the nearest cached exterior alpha-boundary point on one resting physical sticker.
	var visual: StickerMesh = sticker.get_node_or_null("visual") as StickerMesh # Reads the Sticker-owned geometry helper solely through its stable runtime composition node for cached silhouette access.
	if visual == null: # Handles an unexpectedly incomplete sticker composition defensively.
		return pointer_page_point # Falls back to the old direct material point rather than blocking peeling entirely.
	var local_pointer_3d: Vector3 = sticker.global_transform.affine_inverse() * pointer_page_point # Converts the page pointer into undeformed sticker-local coordinates while the selected sticker is resting.
	var local_edge: Vector2 = visual.get_closest_outer_edge_point(Vector2(local_pointer_3d.x, local_pointer_3d.z)) # Projects continuously onto the real cached alpha contour rather than snapping to simplified polygon vertices.
	var world_edge: Vector3 = sticker.global_transform * Vector3(local_edge.x, 0.0, local_edge.y) # Converts the chosen local material-edge position back into the sticker's current world placement.
	world_edge.y = pointer_page_point.y # Keeps peel deformation anchored on the stable page plane while preserving the contour's exact x/z location.
	return world_edge # Returns the physical material origin used by both the visible white dot and the eventual peel shader.

func _clear_peel_target() -> void: # Releases current hover/aim targeting and hides its glowing screen-space marker.
	_peel_target_sticker = null # Releases the runtime Sticker reference so spread reconstruction and removals cannot leave stale ownership.
	_peel_target_world_point = Vector3.ZERO # Clears the previous edge position after its visual marker disappears.
	_hud.set_peel_target(Vector2.ZERO, false) # Hides the white dot without moving unrelated controller cursor presentation.

func _is_controller_mode() -> bool: # Reads controller ownership through the actual removable game coordinator without reaching into UI implementation details.
	var removable_controller: RemovableSpecialEditionGameController = _controller as RemovableSpecialEditionGameController # Narrows the generic book coordinator to the application root used by this concrete world scene.
	return removable_controller != null and removable_controller.is_controller_input_active() # Uses the controller's public device-mode boundary as the single source of truth.

func _ensure_controller_cursor() -> void: # Initializes or clamps the physical gamepad cursor inside the unobscured gameplay viewport.
	var bounds: Rect2 = _get_controller_cursor_bounds() # Reads responsive bounds derived from current viewport size and persistent UI chrome dimensions.
	if not _controller_cursor_initialized: # Creates a predictable first position only once per application session.
		_controller_cursor_position = Vector2(bounds.position.x + bounds.size.x * 0.68, bounds.position.y + bounds.size.y * 0.50) # Starts over the right-hand page rather than the center spine for immediately useful placement.
		_controller_cursor_initialized = true # Preserves the player's physical hand position across navigation and inspection visits.
	_clamp_controller_cursor() # Repairs the cached target after any window resize or supported viewport geometry change.

func _clamp_controller_cursor() -> void: # Restricts the physical gamepad cursor to the visible book area not covered by persistent interface chrome.
	var bounds: Rect2 = _get_controller_cursor_bounds() # Resolves the current safe interaction rectangle from live viewport dimensions.
	_controller_cursor_position.x = clampf(_controller_cursor_position.x, bounds.position.x, bounds.end.x) # Prevents right-stick aim moving behind the left navigation rail or outside the right edge.
	_controller_cursor_position.y = clampf(_controller_cursor_position.y, bounds.position.y, bounds.end.y) # Prevents aim moving behind the top status bar, book footer, or outside the viewport.

func _get_controller_cursor_bounds() -> Rect2: # Calculates the responsive physical interaction rectangle left unobscured by the persistent game UI.
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size # Reads the current logical viewport used by camera projection and screen-space UI.
	var minimum: Vector2 = Vector2(CONTROLLER_NAV_WIDTH + CONTROLLER_CURSOR_MARGIN, CONTROLLER_TOP_HEIGHT + CONTROLLER_CURSOR_MARGIN) # Reserves the persistent left and top chrome plus a small visual margin.
	var maximum: Vector2 = Vector2(maxf(viewport_size.x - CONTROLLER_CURSOR_MARGIN, minimum.x), maxf(viewport_size.y - CONTROLLER_FOOTER_HEIGHT - CONTROLLER_CURSOR_MARGIN, minimum.y)) # Reserves the book footer and protects pathological resize frames from inverted bounds.
	return Rect2(minimum, maximum - minimum) # Returns a normalized safe cursor rectangle used for both initialization and continuous clamping.

func _refresh_controller_placement_status() -> void: # Formats controller-specific manual-placement feedback from the existing authoritative full-sheet validity state.
	if _manual_preview == null: # Rejects status updates after the selected copy has already been committed or cancelled.
		return # Leaves the latest placement outcome message visible.
	if _manual_target_valid: # Confirms the complete physical sticker fits inside the currently targeted page.
		_hud.set_status("right stick to position · X to place") # Exposes the exact controller commit action while allowing further adjustment.
	else: # Handles page margins, spine, and any target where the full sheet would extend outside a valid page.
		_hud.set_status("right stick to position · keep the whole sticker inside a page") # Explains why X cannot commit at the current crosshair location.
