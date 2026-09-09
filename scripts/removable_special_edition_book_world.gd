class_name RemovableSpecialEditionBookWorld
extends SpecialEditionBookWorld

const CONTROLLER_CURSOR_SPEED: float = 720.0 # Moves the physical right-stick cursor quickly enough to cross a full supported viewport without making precise sticker placement difficult.
const CONTROLLER_CURSOR_MARGIN: float = 12.0 # Keeps the controller cursor clear of the persistent navigation chrome and book footer edges.
const CONTROLLER_NAV_WIDTH: float = 160.0 # Matches the editor-authored persistent left navigation rail reserved from physical book interaction.
const CONTROLLER_TOP_HEIGHT: float = 64.0 # Matches the editor-authored top status bar reserved from physical book interaction.
const CONTROLLER_FOOTER_HEIGHT: float = 84.0 # Matches the editor-authored book footer reserved from physical book interaction.

var _controller_cursor_position: Vector2 = Vector2.ZERO # Stores the independent physical pointer used by the right stick without moving the operating-system mouse.
var _controller_cursor_initialized: bool = false # Tracks whether the physical cursor has received a valid viewport-relative starting point.

func set_active(active: bool) -> void: # Extends normal book activation with controller cursor and guidance ownership.
	super.set_active(active) # Preserves camera, environment, visibility, interaction suspension, and any carried placement preview behavior.
	var controller_mode: bool = active and _is_controller_mode() # Resolves the active input family only when this physical world owns presentation.
	_hud.set_controller_mode(controller_mode) # Keeps book footer guidance synchronized with the actual physical interaction device.
	if not controller_mode: # Removes the gamepad crosshair whenever mouse/keyboard or another destination owns the book.
		_hud.set_controller_cursor(Vector2.ZERO, false) # Hides the controller-only pointer without moving the operating-system cursor.
		return # Leaves mouse-oriented world behavior exactly as established.
	_ensure_controller_cursor() # Creates a safe initial physical aim point inside the unobscured book viewport.
	_hud.set_controller_cursor(_controller_cursor_position, true) # Shows the crosshair at the same screen coordinate used for world ray projection.
	if _manual_preview != null: # Repositions a carried collection sticker from the controller cursor instead of the unrelated mouse position.
		_update_manual_preview(_controller_cursor_position) # Reuses the exact page projection and full-sticker fit validation already used by mouse placement.
		_refresh_controller_placement_status() # Explains whether X can currently commit the controller-positioned sticker.

func begin_manual_placement(sticker_key: String, pending_index: int) -> bool: # Starts exact-edition collection placement with controller positioning when a gamepad owns input.
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

func _process(delta: float) -> void: # Preserves collection-return timing while continuously driving controller physical book interaction.
	super._process(delta) # Keeps the special-edition post-placement return-to-collection timer unchanged.
	if not _active or _controller == null: # Avoids hidden-world input polling and startup access before the game coordinator exists.
		return # Leaves inactive book simulation untouched.
	var controller_mode: bool = _is_controller_mode() # Reads the shared most-recent-input mode once for this frame.
	_hud.set_controller_mode(controller_mode) # Updates help and stale-cursor visibility only when the input family changes.
	if not controller_mode: # Gives mouse/keyboard users the original pointer interaction path exclusively.
		_hud.set_controller_cursor(Vector2.ZERO, false) # Hides the gamepad crosshair as soon as pointer/keyboard input retakes ownership.
		return # Avoids reading right-stick actions while controller mode is inactive.
	if _controller.is_gameplay_input_blocked(): # Suspends physical right-stick interaction beneath pause, inspection, collection, settings, and controller-keyboard modals.
		_hud.set_controller_cursor(Vector2.ZERO, false) # Removes the crosshair while another modal visually owns the screen.
		return # Leaves current physical placement and peel state safely suspended until the modal closes.
	_ensure_controller_cursor() # Re-establishes a valid cursor after a resize or first controller interaction.
	var movement: Vector2 = Input.get_vector(&"StickRight_West", &"StickRight_East", &"StickRight_North", &"StickRight_South") # Reads the dedicated physical hand stick independently from left-stick UI navigation.
	if movement.length_squared() > 0.0001: # Updates world aim only for meaningful right-stick displacement beyond the InputMap deadzone.
		_controller_cursor_position += movement * CONTROLLER_CURSOR_SPEED * delta # Converts normalized stick direction into frame-rate-independent screen-space travel.
		_clamp_controller_cursor() # Prevents the physical cursor entering persistent navigation, top-bar, or footer chrome.
	_hud.set_controller_cursor(_controller_cursor_position, true) # Keeps the visible crosshair exactly synchronized with the world ray coordinate every controller frame.
	if _manual_preview != null: # Gives selected collection-copy placement exclusive physical-cursor ownership.
		if movement.length_squared() > 0.0001: # Reprojects only when the right-stick target actually changes.
			_update_manual_preview(_controller_cursor_position) # Uses the established page-plane and complete-sheet bounds validation at the gamepad target.
			_refresh_controller_placement_status() # Tells the player whether the moved target is valid for X placement.
		return # Prevents a carried new sticker from also selecting or peeling existing page stickers.
	if Input.is_action_pressed(&"Button_X"): # Treats X hold as the physical grab while A remains reserved for focused interface controls.
		if _pressed_sticker != null and _active_sticker == null and _controller_cursor_position.distance_to(_pressed_screen_position) >= PEEL_DRAG_THRESHOLD_PIXELS: # Converts a held X plus deliberate right-stick motion into the same delayed realistic peel used by mouse dragging.
			_start_pressed_sticker_peel() # Reuses existing restacking, persistence, material-point capture, and peel initialization without a controller-specific physics implementation.
		if _active_sticker != null: # Updates physical deformation only after the same movement threshold has confirmed peel intent.
			var page_point: Variant = _screen_to_page(_controller_cursor_position) # Projects the controller crosshair onto the stable page plane used by mouse peeling.
			if page_point is Vector3: # Rejects any temporary cursor ray that cannot intersect the page plane safely.
				_active_sticker.update_drag(page_point as Vector3) # Feeds the controller target through the identical clicked-point-driven peel simulation.
				if _active_sticker.is_carried(): # Detects when the sheet has completely detached and can be repositioned across the spread.
					_hud.set_status("right stick to move · release X to place") # Describes the complete controller carry-and-drop interaction.
				else: # Handles the still-attached curl phase before full detachment.
					_hud.set_status("peeling · keep moving · release X to restick") # Makes partial peel and safe release behavior explicit.

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
		_begin_pointer_interaction(_controller_cursor_position) # Ray-picks the top settled sticker and captures its exact page material point using the existing click/drag candidate logic.
		if _pressed_sticker != null: # Confirms a selectable physical sticker was captured beneath the crosshair.
			_hud.set_status("release X to inspect · hold X + right stick to peel") # Exposes both gamepad outcomes before the player commits to either one.
		else: # Handles bare paper or a sticker still settling.
			_hud.set_status("right stick aim · X selects a sticker") # Keeps the controller interaction discoverable after an empty pick.
		get_viewport().set_input_as_handled() # Prevents another controller-aware surface from treating this physical grab as its own X action.
		return # Leaves the captured candidate waiting for motion threshold or release.
	if event.is_action_released(&"Button_X") and (_active_sticker != null or _pressed_sticker != null): # Completes the matching gamepad grab regardless of whether it stayed a tap or became a peel.
		_end_pointer_interaction(_controller_cursor_position) # Reuses exact-edition inspection in this subclass or established physical peel persistence depending on gesture state.
		get_viewport().set_input_as_handled() # Ensures one release cannot also trigger another controller interaction owner.

func _change_spread(direction: int) -> void: # Keeps a controller-positioned manual preview synchronized when page navigation changes the visible spread.
	super._change_spread(direction) # Preserves established page bounds, persistence, reconstruction, and mouse-preview reproject behavior.
	if _manual_preview != null and _is_controller_mode(): # Corrects the inherited mouse-based preview target only for active gamepad placement.
		_ensure_controller_cursor() # Keeps the existing right-stick position inside current viewport bounds after the page change.
		_update_manual_preview(_controller_cursor_position) # Projects the carried collection sticker onto the new spread at the controller cursor.
		_refresh_controller_placement_status() # Re-evaluates whether X can place the complete sticker on the new page pair.

func suspend_interaction() -> void: # Resolves controller and mouse physical gestures before modal or destination ownership changes.
	super.suspend_interaction() # Preserves active-peel completion and pending-click cancellation from the established book interaction path.
	_hud.set_controller_cursor(Vector2.ZERO, false) # Hides the physical crosshair while another presentation surface takes ownership.

func _end_pointer_interaction(screen_position: Vector2) -> void: # Resolves clicks or X taps into placement-aware inspection while preserving the existing peel release behavior.
	if _active_sticker != null: # Gives an already activated peel first ownership of the matching release.
		_finish_active_peel() # Preserves normal physical peel completion and persistence.
		return # Completes the drag release without opening inspection.
	if _pressed_sticker == null: # Ignores releases that do not belong to any book sticker press.
		return # Leaves the book unchanged when no gesture owns the pointer.
	if screen_position.distance_to(_pressed_screen_position) >= PEEL_DRAG_THRESHOLD_PIXELS: # Preserves delayed peel activation for large release-only pointer jumps.
		_start_pressed_sticker_peel() # Converts the candidate into the established physical peel interaction.
		if _active_sticker != null: # Verifies that delayed peel activation succeeded.
			var release_page_point: Variant = _screen_to_page(screen_position) # Projects the final mouse or controller position onto the page plane.
			if release_page_point is Vector3: # Applies only valid page-plane positions.
				_active_sticker.update_drag(release_page_point as Vector3) # Updates deformation to the actual release location.
			_finish_active_peel() # Persists the completed physical interaction.
		return # Prevents a drag from being interpreted as inspection.
	var runtime_id: int = _pressed_sticker.get_instance_id() # Resolves metadata for the exact clicked or controller-selected physical sticker.
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
