class_name BookWorld
extends Node3D

const PICK_DISTANCE: float = 100.0 # Defines the maximum camera ray length used for physical sticker selection on the book.
const MANUAL_RETURN_DELAY: float = 0.34 # Keeps the book visible long enough to see a manually placed sticker complete its bounce-and-slam before returning to the shop.
const PEEL_DRAG_THRESHOLD_PIXELS: float = 7.0 # Separates a deliberate inspection click from a peel drag without making the sticker feel unresponsive.

@onready var _camera: Camera3D = $world/camera as Camera3D # References the dedicated book-world camera used for page projection and sticker picking.
@onready var _environment_node: WorldEnvironment = $world/environment as WorldEnvironment # References the dedicated book lighting environment so inactive worlds cannot compete for the shared World3D environment.
@onready var _interface: CanvasLayer = $interface as CanvasLayer # References the book HUD layer so it can be hidden independently from Node3D world visibility.
@onready var _sticker_root: Node3D = $world/stickers as Node3D # References the composition node that owns every persistent physical sticker attached to the book.
@onready var _status_label: Label = $interface/top_left/panel/content/status as Label # References the compact contextual interaction status text.
@onready var _shop_button: Button = $interface/top_right/shop_button as Button # References the editor-authored button that transitions from the book into the separate shop world.
@onready var _cancel_button: Button = $interface/top_right/cancel_button as Button # References the editor-authored manual-placement cancellation button shown only while carrying a newly won sticker.
@onready var _previous_spread_button: Button = $interface/page_navigation/panel/content/previous_spread as Button # References the editor-authored control used to turn backward through existing book spreads.
@onready var _page_label: Label = $interface/page_navigation/panel/content/page_label as Label # References the editor-authored label showing the absolute page numbers currently visible.
@onready var _next_spread_button: Button = $interface/page_navigation/panel/content/next_spread as Button # References the editor-authored control used to turn forward through already-created book spreads.

var _controller: GameController # Stores the root coordinator that owns world switching, pack transactions, and authoritative persistent models.
var _environment_resource: Environment # Stores the book environment resource while this world is inactive and its WorldEnvironment is deliberately cleared.
var _book_state: StickerBookState # Stores the authoritative persistent physical book layout and unresolved pack contents.
var _catalog: StickerCatalog # Stores automatic sticker artwork discovery and aspect-preserving default physical sizes.
var _active: bool = false # Stores whether this world currently owns player input and its camera.
var _active_sticker: Sticker # Stores the already attached sticker currently owning a realistic peel gesture.
var _pressed_sticker: Sticker # Stores the settled sticker currently held as a click-or-drag candidate before the peel threshold is crossed.
var _pressed_screen_position: Vector2 = Vector2.ZERO # Stores the initial screen coordinate used to distinguish inspection clicks from peel drags.
var _pressed_page_point: Vector3 = Vector3.ZERO # Stores the exact page-plane material point captured on press so delayed peel activation still begins at the correct location.
var _active_placement_id: String = "" # Stores the persistent physical sticker identifier matching the active peel gesture.
var _active_placement_page: int = 0 # Stores the absolute virtual page containing the attached sticker currently being peeled.
var _active_spread_index: int = 0 # Stores the zero-based left/right page pair currently rendered in this physical book world.
var _stack_counter: int = 0 # Tracks the highest logical paper layer currently used by stickers on the visible spread.
var _sticker_ids: Dictionary = {} # Maps runtime Sticker instance IDs to stable persistent placement identifiers.
var _sticker_pages: Dictionary = {} # Maps runtime Sticker instance IDs to persistent absolute page indices.
var _sticker_stacks: Dictionary = {} # Maps runtime Sticker instance IDs to their current logical paper layer for persistence after movement.
var _sticker_paths: Dictionary = {} # Maps runtime Sticker instance IDs to source artwork paths used by the independent inspection modal.
var _manual_preview: StickerPlacementPreview # Stores the temporary floating newly won sticker used while the player chooses a page location.
var _manual_pending_index: int = -1 # Stores the unresolved pack index being placed manually in the current book visit.
var _manual_sticker_path: String = "" # Stores the artwork resource path of the newly won sticker currently being placed.
var _manual_sticker_size: Vector2 = Vector2.ONE # Stores the physical artwork dimensions used by the manual placement preview and final sticker.
var _manual_physical_size: Vector2 = Vector2.ONE # Stores the exact artwork-defined sheet bounds used for fast per-frame page-fit validation.
var _manual_world_xz: Vector2 = Vector2.ZERO # Stores the most recent valid page-space x/z target beneath the pointer.
var _manual_target_valid: bool = false # Stores whether the current manual pointer target keeps the entire artwork-defined sticker inside one usable page.
var _manual_target_page: int = -1 # Stores the absolute virtual page represented by the current valid manual placement target.
var _return_to_shop_remaining: float = -1.0 # Stores the short post-placement delay before returning to the still-open pack reveal in the shop.

func configure(controller: GameController, book_state: StickerBookState, catalog: StickerCatalog) -> void: # Binds shared models and reconstructs only the saved physical stickers belonging to the currently open spread.
	_controller = controller # Stores the coordinator used for world transitions, page creation, and pending-pack placement commits.
	_environment_resource = _environment_node.environment # Caches this scene's dedicated environment before world switching begins clearing inactive WorldEnvironment resources.
	_book_state = book_state # Stores the authoritative multi-page physical layout model used for movement, navigation, and new placement saves.
	_catalog = catalog # Stores the sticker catalogue used to load artwork and default physical sizes.
	_active_spread_index = _book_state.get_active_spread_index() # Restores the exact virtual page pair that was open in the previous session.
	_rebuild_active_spread() # Composes only the current left/right spread so hidden pages consume no runtime sticker nodes or physics picking.
	_status_label.text = "click_to_inspect  ·  drag_to_peel" # Shows the deliberate split between non-destructive inspection and realistic physical manipulation.
	_cancel_button.visible = false # Keeps manual-placement cancellation absent during ordinary book browsing.
	_refresh_page_navigation() # Updates page numbers and navigation availability for the restored book size.

func set_active(active: bool) -> void: # Enables or disables this complete gameplay world without destroying its persistent physical sticker nodes.
	_active = active # Stores whether book input should currently be interpreted.
	visible = active # Hides the entire book world while the separate shop world is active.
	_interface.visible = active # Hides or shows the book HUD explicitly because CanvasLayer visibility is independent from Node3D rendering visibility.
	_camera.current = active # Gives camera ownership exclusively to the active gameplay world.
	if active: # Restores the book-specific environment only while this world owns presentation.
		_environment_node.environment = _environment_resource # Activates the book lighting, background, and ambient settings without another WorldEnvironment competing.
	else: # Clears environment ownership while the shop world is active.
		_environment_node.environment = null # Prevents hidden book environment settings from affecting the separate shop presentation.
	if active and _manual_preview != null: # Refreshes a carried pack sticker immediately when returning to book placement mode.
		_update_manual_preview(get_viewport().get_mouse_position()) # Reprojects the current pointer into the page so the preview appears without requiring motion first.

func begin_manual_placement(sticker_path: String, pending_index: int) -> bool: # Enters book placement mode for one clicked physical sticker from the shop reveal.
	_clear_manual_preview() # Removes any stale temporary preview before composing the newly selected pending sticker.
	var texture_resource: Resource = ResourceLoader.load(sticker_path, "Texture2D") # Loads the selected won artwork through Godot's imported resource cache.
	if texture_resource is not Texture2D: # Rejects a missing or incompatible pack artwork resource before changing world state.
		push_error("manual sticker texture could not be loaded: %s" % sticker_path) # Reports the exact invalid pending resource for debugging.
		return false # Leaves the book in normal interaction mode when preview composition cannot succeed.
	_manual_pending_index = pending_index # Stores the exact current pending index represented by the clicked floating shop sticker.
	_manual_sticker_path = sticker_path # Stores the selected artwork path for controller validation at commit time.
	_manual_sticker_size = _catalog.get_default_size(sticker_path) # Uses the catalogue's aspect-preserving physical dimensions for preview, bounds testing, and persistence.
	_manual_preview = StickerPlacementPreview.new() # Creates the temporary floating front-face sticker composition.
	_manual_preview.name = "manual_placement_preview" # Gives the runtime helper a readable scene-tree name.
	$world.add_child(_manual_preview) # Parents the preview into the book world so its world transform matches page coordinates directly.
	_manual_preview.configure(_manual_sticker_size, texture_resource as Texture2D) # Builds the full realistic artwork-defined sheet and exact projected landing outline.
	_manual_physical_size = _manual_preview.get_physical_size() # Caches exact artwork bounds once so pointer movement never regenerates contour data.
	_cancel_button.visible = true # Shows the explicit escape route back to the shop while the pending sticker remains unresolved.
	_shop_button.visible = false # Hides the ordinary shop navigation button while this visit already originated from the pack reveal.
	_status_label.text = "move_to_place  ·  click_to_stick  ·  stickers_stay_upright" # Explains manual placement while making the canonical book orientation explicit.
	_update_manual_preview(get_viewport().get_mouse_position()) # Positions the newly created sticker immediately beneath the current pointer when possible.
	return true # Reports that the physical pending sticker successfully entered manual book placement mode.

func add_placement_record(placement: Dictionary, animate_landing: bool) -> void: # Adds one newly committed persistent physical sticker when it belongs to the currently visible spread.
	var page_index: int = maxi(int(placement.get("page", 0)), 0) # Retrieves the persistent absolute page assigned to the new sticker.
	if StickerBookLayout.get_spread_index_for_page(page_index) != _active_spread_index: # Detects a placement committed onto a different virtual spread.
		return # Leaves hidden-spread rendering deferred until the player turns to that spread.
	_spawn_placement_record(placement, animate_landing) # Reuses the same reconstruction path while optionally playing the requested bounce-and-slam arrival.

func show_spread(spread_index: int) -> void: # Opens one already-created virtual spread and reconstructs only the stickers physically attached to those two pages.
	if _book_state == null: # Rejects navigation before authoritative book persistence has been configured.
		return # Leaves the current scene composition untouched during incomplete startup.
	var clamped_spread: int = clampi(spread_index, 0, maxi(_book_state.get_spread_count() - 1, 0)) # Restricts navigation to spreads that already exist in persistent book state.
	if clamped_spread == _active_spread_index and _sticker_root.get_child_count() > 0: # Avoids rebuilding an already visible populated spread unnecessarily.
		_refresh_page_navigation() # Still refreshes controls in case page count changed while this spread remained active.
		return # Keeps current physical sticker nodes and active animations intact for a no-op navigation request.
	_active_spread_index = clamped_spread # Stores the newly selected virtual page pair for all placement and movement page mapping.
	_book_state.set_active_spread_index(_active_spread_index) # Persists navigation so the same spread reopens after restarting the game.
	_rebuild_active_spread() # Replaces old visible sticker nodes with the physical contents of the selected page pair.
	_refresh_page_navigation() # Updates absolute page numbers and previous/next button availability.
	_status_label.text = "pages_%d_%d" % [_active_spread_index * StickerBookLayout.PAGES_PER_SPREAD + 1, _active_spread_index * StickerBookLayout.PAGES_PER_SPREAD + 2] # Confirms which physical pages are now open using one-based player-facing numbering.

func show_auto_placements(placements: Array[Dictionary]) -> void: # Shows the newest auto-packed spread and plays landing impacts for newly committed stickers visible on that spread.
	if placements.is_empty(): # Rejects empty result batches without rebuilding the current visible book spread.
		return # Leaves existing physical page presentation untouched when no stickers were committed.
	var last_placement: Dictionary = placements[placements.size() - 1] # Uses the final packed sticker because automatic page expansion always progresses forward through spreads.
	var target_page: int = maxi(int(last_placement.get("page", 0)), 0) # Retrieves the absolute page containing the final packed result.
	var target_spread: int = StickerBookLayout.get_spread_index_for_page(target_page) # Resolves which virtual left/right pair should be shown after packing.
	_active_spread_index = target_spread # Opens the newest spread immediately when auto-stick created pages while packing the reveal.
	_book_state.set_active_spread_index(_active_spread_index) # Persists the newly shown result spread for future sessions.
	var animated_ids: Dictionary = {} # Stores committed placement identifiers that should be excluded from settled reconstruction and spawned with landing animation instead.
	for placement: Dictionary in placements: # Visits every newly committed auto-placement once.
		var placement_page: int = maxi(int(placement.get("page", 0)), 0) # Retrieves the virtual page used by this newly packed physical copy.
		if StickerBookLayout.get_spread_index_for_page(placement_page) == target_spread: # Keeps animation bookkeeping only for results visible on the final spread.
			animated_ids[str(placement.get("id", ""))] = true # Marks this new physical sticker for animated reconstruction.
	_rebuild_active_spread(animated_ids) # Recreates settled existing stickers on the target spread while leaving new results absent temporarily.
	for placement: Dictionary in placements: # Visits newly committed results again in their actual packing order for landing animation.
		var placement_page: int = maxi(int(placement.get("page", 0)), 0) # Retrieves the absolute page containing this packed copy.
		if StickerBookLayout.get_spread_index_for_page(placement_page) != target_spread: # Skips new stickers that landed on an earlier spread during this multi-sticker packing batch.
			continue # Leaves those physical copies to normal reconstruction when that spread is opened later.
		_spawn_placement_record(placement, true) # Creates the visible new sticker above its solved target and plays its bounce-and-slam arrival.
	_refresh_page_navigation() # Updates controls because auto-stick may have appended one or more new page pairs.
	_status_label.text = "auto_stick_packed_the_stickers_into_the_book" # Confirms that alpha-silhouette packing has been committed across the multi-page book.

func _rebuild_active_spread(excluded_ids: Dictionary = {}) -> void: # Recreates only the currently open virtual spread while optionally withholding selected new placements for landing animation.
	_active_sticker = null # Releases any stale peel ownership before old visible sticker nodes are removed.
	_pressed_sticker = null # Clears any uncommitted click-or-drag candidate before the visible spread is rebuilt.
	_active_placement_id = "" # Clears persistence metadata tied to the previous spread's runtime nodes.
	_sticker_ids.clear() # Removes runtime-to-persistence mappings that belong to sticker nodes about to leave the visible spread.
	_sticker_pages.clear() # Removes runtime page mappings for hidden-spread sticker nodes.
	_sticker_stacks.clear() # Removes runtime stack mappings before rebuilding current visible layering.
	_sticker_paths.clear() # Removes artwork-path mappings belonging to sticker nodes that are leaving the active spread.
	for child: Node in _sticker_root.get_children(): # Visits every currently composed physical sticker node from the old spread.
		child.queue_free() # Removes hidden-spread mesh, shader, and picking resources at the end of the current frame.
	_stack_counter = _book_state.get_max_stack_order_for_spread(_active_spread_index) # Restores layering only from stickers physically visible on the new spread.
	for placement: Dictionary in _book_state.get_placements_for_spread_copy(_active_spread_index): # Recreates every saved sticker attached to the selected left/right page pair.
		var placement_id: String = str(placement.get("id", "")) # Retrieves the stable physical identifier used for optional landing-animation exclusion.
		if excluded_ids.has(placement_id): # Detects a just-auto-packed result that should appear through its own bounce-and-slam instead of settled reconstruction.
			continue # Leaves the animated sticker absent until its dedicated spawn pass runs.
		_spawn_placement_record(placement, false) # Builds each ordinary visible sticker directly in its settled flat state.

func _refresh_page_navigation() -> void: # Synchronizes page-number text and editor-authored navigation button availability with persistent book size.
	if _book_state == null: # Rejects UI refresh before multi-page persistence is configured.
		return # Leaves editor defaults intact during startup.
	var left_page_number: int = _active_spread_index * StickerBookLayout.PAGES_PER_SPREAD + 1 # Converts the zero-based virtual left page into a one-based player-facing page number.
	var right_page_number: int = left_page_number + 1 # Calculates the one-based right page number paired with the visible left page.
	_page_label.text = "pages_%d_%d" % [left_page_number, right_page_number] # Shows the exact absolute page pair currently represented by the physical book meshes.
	_previous_spread_button.disabled = _active_spread_index <= 0 # Prevents navigation before the first persistent spread.
	_next_spread_button.disabled = _active_spread_index >= _book_state.get_spread_count() - 1 # Prevents navigation beyond the newest spread until placement pressure creates another pair.

func _change_spread(direction: int) -> void: # Turns one virtual spread backward or forward without allocating pages manually.
	if _active_sticker != null or _pressed_sticker != null: # Prevents a page turn from destroying a sticker currently owned by an active or not-yet-resolved pointer gesture.
		return # Requires the player to finish or release the current physical interaction before turning pages.
	var target_spread: int = _active_spread_index + (-1 if direction < 0 else 1) # Converts the navigation direction into exactly one neighboring spread step.
	if target_spread < 0 or target_spread >= _book_state.get_spread_count(): # Rejects attempts to navigate outside already-created virtual page pairs.
		return # Leaves the visible spread unchanged when no page pair exists in that direction.
	show_spread(target_spread) # Persists and reconstructs the requested existing spread.
	if _manual_preview != null: # Keeps a manually carried won sticker active while the player turns among existing spreads.
		_update_manual_preview(get_viewport().get_mouse_position()) # Reprojects the carried sticker onto the newly visible left/right pages immediately.

func _process(delta: float) -> void: # Advances only the short manual-placement world-transition delay owned by this controller.
	if _return_to_shop_remaining < 0.0: # Skips all timer work when no manual placement has just been committed.
		return # Leaves ordinary book and peel processing entirely to their own components.
	_return_to_shop_remaining -= delta # Advances the post-slam visibility delay toward the shop transition.
	if _return_to_shop_remaining <= 0.0: # Detects when the newly placed sticker has had enough time to visibly complete its landing.
		_return_to_shop_remaining = -1.0 # Clears the one-shot transition timer before calling back into the coordinator.
		_controller.show_shop() # Returns to the same shop reveal so the player can manually select another remaining won sticker.

func _input(event: InputEvent) -> void: # Owns book pointer behavior while separating simple inspection clicks from thresholded peel drags without signals.
	if not _active: # Ignores every pointer event while another destination owns presentation.
		return # Prevents hidden book collisions or controls from responding across navigation transitions.
	if _controller != null and _controller.is_gameplay_input_blocked(): # Detects pause, inspection, and other modal interface states that deliberately suspend physical interaction.
		return # Leaves all peel, placement, and page-turn state untouched while a modal surface owns input.
	if event is InputEventMouseButton: # Handles discrete book controls, manual placement clicks, and click-or-drag sticker gesture ownership.
		var mouse_button: InputEventMouseButton = event as InputEventMouseButton # Narrows the event for strongly typed button and screen-position access.
		var releasing_world_gesture: bool = mouse_button.button_index == MOUSE_BUTTON_LEFT and not mouse_button.pressed and (_active_sticker != null or _pressed_sticker != null) # Detects releases that must terminate a gesture even after the pointer crosses global UI.
		if _controller != null and _controller.is_pointer_over_game_ui(mouse_button.position) and not releasing_world_gesture: # Blocks new UI-owned presses while preserving release ownership for a gesture that started in the book.
			return # Prevents navigation clicks from interacting with physical stickers underneath the shell.
		if mouse_button.pressed and mouse_button.button_index == MOUSE_BUTTON_LEFT and _cancel_button.visible and _cancel_button.get_global_rect().has_point(mouse_button.position): # Detects explicit cancellation during manual pending-sticker placement.
			_cancel_manual_placement() # Returns the unresolved sticker to the shop reveal without changing persistence.
			get_viewport().set_input_as_handled() # Prevents the same click from also placing or selecting something beneath the button.
			return # Completes cancellation as the sole action for this pointer press.
		if mouse_button.pressed and mouse_button.button_index == MOUSE_BUTTON_LEFT and _previous_spread_button.visible and _previous_spread_button.get_global_rect().has_point(mouse_button.position): # Detects a request to turn backward one existing page spread.
			_change_spread(-1) # Rebuilds the visible book from the preceding virtual left/right page pair.
			get_viewport().set_input_as_handled() # Prevents the page-turn click from selecting a sticker underneath navigation.
			return # Completes backward page navigation as the sole action for this press.
		if mouse_button.pressed and mouse_button.button_index == MOUSE_BUTTON_LEFT and _next_spread_button.visible and _next_spread_button.get_global_rect().has_point(mouse_button.position): # Detects a request to turn forward one already-created page spread.
			_change_spread(1) # Rebuilds the visible book from the following virtual left/right page pair.
			get_viewport().set_input_as_handled() # Prevents the page-turn click from reaching physical page content below the HUD.
			return # Completes forward page navigation as the sole action for this press.
		if mouse_button.pressed and mouse_button.button_index == MOUSE_BUTTON_LEFT and _shop_button.visible and _shop_button.get_global_rect().has_point(mouse_button.position): # Detects ordinary navigation from book browsing into the separate shop world.
			_controller.show_shop() # Switches presentation without overlaying shop content on the book.
			get_viewport().set_input_as_handled() # Prevents the navigation click from selecting a sticker behind the button.
			return # Completes world navigation as the sole action for this pointer press.
		if _manual_preview != null: # Routes remaining primary-button behavior into new-sticker placement while a pack result is carried.
			if mouse_button.pressed and mouse_button.button_index == MOUSE_BUTTON_LEFT: # Treats a normal left press as the physical act of sticking the selected pack result down.
				_commit_manual_placement() # Converts the pending sticker into persistent book state only when the current upright target is valid.
				get_viewport().set_input_as_handled() # Prevents the placement click from selecting an existing sticker underneath it.
				return # Completes manual placement handling for this button event.
			return # Ignores releases and wheel input during manual placement because book stickers always retain canonical artwork rotation.
		if mouse_button.button_index == MOUSE_BUTTON_LEFT and mouse_button.pressed: # Captures a settled sticker as an inspection-or-peel candidate without deforming it yet.
			_begin_pointer_interaction(mouse_button.position) # Ray-picks the top physical sticker and stores the exact click point until intent is known.
		elif mouse_button.button_index == MOUSE_BUTTON_LEFT and not mouse_button.pressed: # Completes either a simple inspection click or an already activated peel drag.
			_end_pointer_interaction(mouse_button.position) # Resolves the gesture based on whether the drag threshold was crossed.
	elif event is InputEventMouseMotion: # Handles continuous pointer movement for either new-sticker placement or thresholded realistic peeling.
		var mouse_motion: InputEventMouseMotion = event as InputEventMouseMotion # Narrows the motion event for strongly typed screen coordinates.
		if _manual_preview != null: # Gives newly won placement mode exclusive pointer-motion ownership.
			_update_manual_preview(mouse_motion.position) # Moves the upright floating sticker and exact landing silhouette over the book pages.
			return # Prevents the same motion from affecting attached sticker interaction state.
		if _pressed_sticker != null and _active_sticker == null and mouse_motion.position.distance_to(_pressed_screen_position) >= PEEL_DRAG_THRESHOLD_PIXELS: # Detects deliberate drag intent only after enough screen-space movement to avoid accidental peels on clicks.
			_start_pressed_sticker_peel() # Converts the pending click candidate into a real physical peel beginning at the original exact material point.
		if _active_sticker != null: # Updates a sticker only after the gesture has crossed the peel threshold.
			var page_point: Variant = _screen_to_page(mouse_motion.position) # Projects current pointer motion onto the stable flat page plane.
			if page_point is Vector3: # Updates peel physics only when the camera ray reaches the page plane successfully.
				_active_sticker.update_drag(page_point as Vector3) # Sends the physical world target into the clicked-point-driven peel simulation.
				if _active_sticker.is_carried(): # Detects the irreversible full-peel carry state.
					_status_label.text = "fully_peeled  ·  outline_shows_release_landing" # Explains the exact projected landing guide while the sticker is detached.
				else: # Handles the still-attached portion of the realistic peel.
					_status_label.text = "peeling  ·  release_to_restick" # Explains that incomplete material stays peeled until release.

func _begin_pointer_interaction(screen_position: Vector2) -> void: # Selects one settled sticker but waits for click-versus-drag intent before restacking or deforming it.
	if _active_sticker != null or _pressed_sticker != null: # Prevents a second press from stealing gesture ownership.
		return # Keeps one deterministic sticker candidate until the matching release.
	var ray_origin: Vector3 = _camera.project_ray_origin(screen_position) # Converts the pointer into a world-space camera ray origin.
	var ray_direction: Vector3 = _camera.project_ray_normal(screen_position) # Converts the pointer into the matching normalized world-space ray direction.
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(ray_origin, ray_origin + ray_direction * PICK_DISTANCE, 1) # Creates a sticker-only query using collision layer one.
	query.collide_with_areas = true # Allows intersection with Sticker Area3D picking volumes.
	query.collide_with_bodies = false # Excludes unrelated book geometry from physical sticker selection.
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query) # Finds the nearest physical sticker beneath the flat presentation pointer.
	if hit.is_empty(): # Handles clicks that land on bare paper instead of a sticker.
		_status_label.text = "click_directly_on_a_sticker" # Gives compact feedback without starting any interaction state.
		return # Leaves book interaction idle after an empty page click.
	var collider: Object = hit.get("collider") as Object # Retrieves the selected physics object from the ray result.
	if collider is not Sticker: # Rejects any future layer-one area that is not a realistic sticker composition.
		return # Keeps inspection and peel logic isolated from unrelated interactables.
	var selected_sticker: Sticker = collider as Sticker # Narrows the selected area to the realistic sticker API.
	if not selected_sticker.can_begin_drag(): # Prevents clicks while a sticker is still returning or landing autonomously.
		_status_label.text = "that_sticker_is_still_landing" # Explains why the sticker cannot yet be inspected or peeled.
		return # Leaves its physical animation uninterrupted.
	var page_point: Variant = _screen_to_page(screen_position) # Finds the exact stable page-plane material point beneath the press.
	if page_point is not Vector3: # Rejects the unlikely case of a camera ray that cannot reach the page plane.
		return # Leaves gesture state empty when a reliable material grab point cannot be captured.
	_pressed_sticker = selected_sticker # Stores the settled sticker without changing its stack or physical deformation yet.
	_pressed_screen_position = screen_position # Stores the press coordinate used by the drag-intent threshold.
	_pressed_page_point = page_point as Vector3 # Stores the exact material point that will become the peel origin only if the gesture turns into a drag.
	_status_label.text = "release_to_inspect  ·  drag_to_peel" # Makes the two distinct interactions discoverable at the moment a sticker is pressed.

func _start_pressed_sticker_peel() -> void: # Converts the pending click candidate into the existing realistic peel only after deliberate drag movement.
	if _pressed_sticker == null or _active_sticker != null: # Rejects activation without a unique settled candidate.
		return # Leaves current gesture state unchanged when no peel can begin.
	_active_sticker = _pressed_sticker # Transfers gesture ownership from the click candidate into active physical manipulation.
	_pressed_sticker = null # Clears click ownership immediately so release is handled only by the active peel path.
	var runtime_id: int = _active_sticker.get_instance_id() # Retrieves the runtime key used to resolve persistence metadata.
	_active_placement_id = str(_sticker_ids.get(runtime_id, "")) # Resolves the stable persistent physical sticker identifier.
	_active_placement_page = int(_sticker_pages.get(runtime_id, StickerBookLayout.get_first_page_index_for_spread(_active_spread_index))) # Resolves the absolute virtual page containing the selected sticker.
	_stack_counter += 1 # Brings a genuinely manipulated sheet above every older paper layer only when peel intent is confirmed.
	_sticker_stacks[runtime_id] = _stack_counter # Stores the new logical layer for persistence when the gesture finishes.
	_active_sticker.set_stack_height(StickerBookLayout.get_stack_height(_stack_counter)) # Applies the tiny physical paper-height offset before deformation begins.
	if not _active_placement_id.is_empty(): # Persists restacking immediately so a mid-drag shutdown cannot restore this sticker beneath older layers.
		_book_state.update_placement(_active_placement_id, _active_placement_page, Vector2(_active_sticker.global_position.x, _active_sticker.global_position.z), _stack_counter) # Stores page, position, canonical orientation, and newest stack order.
	_active_sticker.begin_drag(_pressed_page_point) # Starts the curl from the exact original press point rather than the later threshold-crossing pointer position.
	_status_label.text = "peeling_from_the_exact_point_you_grabbed" # Confirms successful delayed physical gesture activation.

func _end_pointer_interaction(screen_position: Vector2) -> void: # Resolves a book gesture into inspection when it stayed a click or physical release when it became a drag.
	if _active_sticker != null: # Gives an already activated peel first ownership of the matching release.
		_finish_active_peel() # Starts resticking or landing and persists the canonical book placement.
		return # Completes the drag release without opening inspection.
	if _pressed_sticker == null: # Ignores releases that do not belong to any book sticker press.
		return # Leaves the book unchanged when no gesture owns the pointer.
	if screen_position.distance_to(_pressed_screen_position) >= PEEL_DRAG_THRESHOLD_PIXELS: # Handles unusual input streams where a large pointer jump arrives only with the release event.
		_start_pressed_sticker_peel() # Converts the candidate into a physical peel so a deliberate drag can never be misread as inspection.
		if _active_sticker != null: # Verifies that the delayed peel started successfully.
			var release_page_point: Variant = _screen_to_page(screen_position) # Projects the release target onto the page plane for one final physical deformation update.
			if release_page_point is Vector3: # Applies the release position only when stable page coordinates are available.
				_active_sticker.update_drag(release_page_point as Vector3) # Updates the physical sheet to the actual released pointer location before ending the drag.
			_finish_active_peel() # Starts the appropriate return or landing animation immediately after the recovered drag.
		return # Completes the recovered drag path without opening inspection.
	var runtime_id: int = _pressed_sticker.get_instance_id() # Retrieves the runtime key used to resolve the clicked sticker's source artwork.
	var sticker_path: String = str(_sticker_paths.get(runtime_id, "")) # Resolves the immutable source resource used by the independent 2D inspection presentation.
	_pressed_sticker = null # Releases click ownership before opening the modal so no physical gesture remains pending underneath it.
	if _controller != null and _controller.show_sticker_inspection(sticker_path): # Opens a non-destructive large flat presentation when the source artwork can be loaded.
		_status_label.text = "inspection_open  ·  book_rotation_unchanged" # Confirms that inspection transforms are temporary and separate from the page sticker.
	else: # Handles a missing source path or unexpected texture load failure.
		_status_label.text = "could_not_open_sticker_inspection" # Reports the failed inspection without changing the physical sticker.

func _finish_active_peel() -> void: # Releases an already activated sticker peel and persists only upright canonical page orientation.
	if _active_sticker == null: # Rejects calls without an active physical sticker gesture.
		return # Leaves the book unchanged when no peel owns the pointer.
	var moved: bool = _active_sticker.end_drag() # Starts either incomplete resticking or detached bounce-and-slam placement.
	var runtime_id: int = _active_sticker.get_instance_id() # Retrieves the runtime metadata key before releasing pointer ownership.
	var stack_order: int = int(_sticker_stacks.get(runtime_id, _stack_counter)) # Resolves the logical paper layer assigned when the actual peel began.
	var final_world_xz: Vector2 = Vector2(_active_sticker.global_position.x, _active_sticker.global_position.z) # Captures the release center reused by page mapping and persistence.
	var final_page: int = _active_placement_page # Preserves the original virtual page when the release center lies outside either usable page rectangle.
	if moved: # Allows a fully detached upright sticker to move between left and right pages of the current spread.
		var final_local_page: int = StickerBookLayout.get_local_page_index(final_world_xz) # Finds which visible page contains the detached sticker's released center.
		if final_local_page >= 0: # Accepts page reassignment only when the release center belongs to a usable visible page.
			final_page = StickerBookLayout.get_absolute_page_index(_active_spread_index, final_local_page) # Converts the visible page side into the correct persistent absolute page number.
	_sticker_pages[runtime_id] = final_page # Keeps runtime metadata synchronized if the player moved the sticker across the spine.
	if not _active_placement_id.is_empty(): # Updates persistence for moved and partial-peel releases while canonical orientation remains enforced by book state.
		_book_state.update_placement(_active_placement_id, final_page, final_world_xz, stack_order) # Stores the release page, x/z placement, canonical source orientation, and current paper layer.
	if moved: # Reports a complete peel committing to a new horizontal page position.
		_status_label.text = "released  ·  bounce_then_slam_flat" # Describes the autonomous landing now running.
	else: # Reports an incomplete peel that never detached from its original page position.
		_status_label.text = "released  ·  partial_peel_resticking" # Describes the autonomous curl relaxation after button release.
	_active_sticker = null # Releases pointer ownership immediately while the Sticker component finishes its autonomous animation.
	_active_placement_id = "" # Clears the persistent identifier associated with the completed gesture.
	_active_placement_page = StickerBookLayout.get_first_page_index_for_spread(_active_spread_index) # Restores harmless page metadata after the completed gesture.

func _update_manual_preview(screen_position: Vector2) -> void: # Projects the pointer onto the book and updates exact newly won sticker placement bounds and visuals.
	if _manual_preview == null: # Rejects calls after manual placement has been committed or cancelled.
		return # Leaves ordinary book interaction untouched.
	var page_point: Variant = _screen_to_page(screen_position) # Intersects the pointer ray with the flat book-page plane.
	if page_point is not Vector3: # Handles camera rays that cannot reach the page plane.
		_manual_target_valid = false # Prevents placement at an undefined physical target.
		_manual_preview.update_target(_manual_world_xz, 0.0, false, StickerBookLayout.PAGE_SURFACE_Y) # Hides both floating sheet and projected silhouette.
		return # Waits for the pointer to return to a projectable position.
	var world_point: Vector3 = page_point as Vector3 # Narrows the valid plane intersection for x/z page handling.
	_manual_world_xz = Vector2(world_point.x, world_point.z) # Stores the current physical page-space center beneath the pointer.
	_manual_target_valid = _manual_target_fits_page(_manual_world_xz) # Requires the complete upright sticker to stay within one usable page rectangle.
	var local_page_index: int = StickerBookLayout.get_local_page_index(_manual_world_xz) # Resolves which visible page is currently beneath the manual sticker center.
	_manual_target_page = StickerBookLayout.get_absolute_page_index(_active_spread_index, local_page_index) if _manual_target_valid else -1 # Maps a valid visible target onto its persistent absolute page number.
	var preview_stack_order: int = _book_state.get_max_stack_order_for_page(_manual_target_page) + 1 if _manual_target_valid else _stack_counter + 1 # Predicts the next paper layer on the exact target page without inheriting hidden-page stack values.
	var preview_height: float = StickerBookLayout.get_stack_height(preview_stack_order) # Converts the predicted target-page stack into the physical landing-preview height.
	_manual_preview.update_target(_manual_world_xz, 0.0, _manual_target_valid, preview_height) # Updates both the floating sticker and exact alpha-silhouette landing projection.
	if _manual_target_valid: # Gives immediate textual confirmation when the full physical sticker fits.
		_status_label.text = "click_to_stick  ·  original_rotation_locked" # Keeps the valid placement instruction concise while confirming canonical book orientation.
	else: # Explains why a pointer position near margins or the spine cannot be committed.
		_status_label.text = "move_the_whole_sticker_inside_one_page" # Makes the full-sheet page-boundary requirement explicit.

func _manual_target_fits_page(world_xz: Vector2) -> bool: # Tests whether the complete upright artwork rectangle fits inside one usable page before placement.
	var local_page_index: int = StickerBookLayout.get_local_page_index(world_xz) # Finds which visible page contains the preview center.
	if local_page_index < 0: # Rejects centers on the spine, margins, desk, or outside the book.
		return false # Prevents a physical sticker from being committed without a valid page.
	var page_bounds: Rect2 = StickerBookLayout.get_page_bounds(local_page_index) # Retrieves the safe x/z rectangle for the chosen visible page side.
	var half_size: Vector2 = _manual_physical_size * 0.5 # Uses the exact cached artwork-defined sheet bounds, for page-fit validation.
	return world_xz.x - half_size.x >= page_bounds.position.x and world_xz.x + half_size.x <= page_bounds.end.x and world_xz.y - half_size.y >= page_bounds.position.y and world_xz.y + half_size.y <= page_bounds.end.y # Requires the complete upright sticker sheet to remain inside one usable page.

func _commit_manual_placement() -> void: # Converts the currently previewed won sticker into authoritative persistent book state.
	if _manual_preview == null or not _manual_target_valid: # Rejects clicks while no pending sticker is carried or its complete sheet does not fit on a page.
		return # Leaves the pending pack untouched until the player chooses a valid physical target.
	var committed: bool = _controller.commit_manual_placement(_manual_pending_index, _manual_sticker_path, _manual_sticker_size, _manual_target_page, _manual_world_xz) # Lets the root coordinator validate current pending identity and persist the physical placement on the selected absolute page atomically.
	if not committed: # Handles a stale pending index or any unexpected authoritative-state mismatch safely.
		_status_label.text = "could_not_place_that_pending_sticker" # Reports that persistence rejected the physical commit.
		return # Keeps the preview active so the player does not silently lose a won sticker.
	_clear_manual_preview() # Removes the temporary floating sheet and projected guide because a real physical Sticker now owns the committed placement.
	_status_label.text = "stuck  ·  returning_to_pack" # Confirms the physical placement while the new sticker completes its bounce-and-slam.
	_return_to_shop_remaining = MANUAL_RETURN_DELAY # Keeps the book visible briefly before restoring the remaining pack reveal.

func cancel_manual_placement_for_navigation() -> void: # Exposes safe temporary-placement and post-placement transition cancellation to the top-level navigation coordinator.
	_return_to_shop_remaining = -1.0 # Cancels any delayed automatic shop return when the player has explicitly chosen another navigation destination.
	if _manual_preview == null: # Detects ordinary book browsing where no pack sticker is currently being carried.
		return # Leaves the physical book untouched when there is no temporary placement preview to clear.
	_clear_manual_preview() # Removes the temporary sticker and landing guide while leaving the authoritative pending pack copy unresolved.
	_status_label.text = "placement_cancelled" # Leaves compact local feedback when navigation later returns to the book.

func _cancel_manual_placement() -> void: # Abandons the current book placement visit without consuming or moving the pending physical sticker.
	_clear_manual_preview() # Removes the temporary floating sheet and exact page projection.
	_controller.show_shop() # Returns immediately to the unchanged shop reveal where the sticker remains pending and clickable.

func _clear_manual_preview() -> void: # Clears all runtime state associated with one temporary won-sticker placement visit.
	if _manual_preview != null: # Verifies that a temporary physical preview currently exists.
		_manual_preview.clear() # Hides its exact landing projection and queues the helper composition for deletion.
	_manual_preview = null # Releases the runtime reference immediately so normal sticker peeling can resume.
	_manual_pending_index = -1 # Clears the mutable pending-pack index after placement or cancellation.
	_manual_sticker_path = "" # Clears the selected artwork identity.
	_manual_sticker_size = Vector2.ONE # Restores a harmless default artwork size for future validity calculations.
	_manual_physical_size = Vector2.ONE # Restores harmless artwork bounds after the temporary placement composition is cleared.
	_manual_target_valid = false # Prevents any stale page target from being committed after the preview is gone.
	_manual_target_page = -1 # Clears the persistent virtual page associated with the discarded or committed preview.
	_cancel_button.visible = false # Hides manual-only cancellation during ordinary book browsing.
	_shop_button.visible = true # Restores ordinary navigation into the separate shop world.

func _screen_to_page(screen_position: Vector2) -> Variant: # Intersects a book-camera ray with the stable flat page plane for peel and placement coordinates.
	var ray_origin: Vector3 = _camera.project_ray_origin(screen_position) # Creates the world-space ray origin matching the current screen point.
	var ray_direction: Vector3 = _camera.project_ray_normal(screen_position) # Creates the matching normalized world-space ray direction.
	var page_plane: Plane = Plane(Vector3.UP, StickerBookLayout.PAGE_SURFACE_Y) # Defines the infinite horizontal interaction plane aligned with both book pages.
	return page_plane.intersects_ray(ray_origin, ray_direction) # Returns either the physical page-plane world point or null when no intersection exists.

func _spawn_placement_record(placement: Dictionary, animate_landing: bool) -> void: # Recreates one persistent physical placement from the currently visible spread as a fully interactive realistic Sticker node.
	var page_index: int = maxi(int(placement.get("page", 0)), 0) # Retrieves the absolute virtual page assigned to this persistent sticker copy.
	if StickerBookLayout.get_spread_index_for_page(page_index) != _active_spread_index: # Rejects hidden-spread placements before allocating textures, mesh, picking, or shader resources.
		return # Defers physical composition until the player opens the placement's virtual spread.
	var sticker_path: String = str(placement.get("path", "")) # Retrieves the imported artwork path that defines this physical sticker design.
	var texture_resource: Resource = ResourceLoader.load(sticker_path, "Texture2D") # Loads the artwork through Godot's resource-aware texture cache.
	if texture_resource is not Texture2D: # Rejects saved placements whose artwork is no longer available or compatible.
		push_error("saved sticker texture could not be loaded: %s" % sticker_path) # Reports the exact missing physical design for development diagnostics.
		return # Leaves the rest of the book usable instead of creating an invalid Sticker node.
	var sticker_size: Vector2 = Vector2(float(placement.get("size_x", 1.0)), float(placement.get("size_y", 1.0))) # Restores the exact original artwork physical dimensions.
	var stack_order: int = maxi(int(placement.get("stack", 0)), 0) # Restores the logical paper layer used by this physical sticker.
	var stack_height: float = StickerBookLayout.get_stack_height(stack_order) # Converts logical paper order into the exact flat world y position.
	var sticker: Sticker = Sticker.new() # Creates the high-level realistic peelable sticker composition.
	sticker.name = str(placement.get("id", sticker_path.get_file().get_basename())) # Uses the stable physical placement identifier as the runtime node name when available.
	_sticker_root.add_child(sticker) # Parents the physical sticker under the dedicated book composition node.
	sticker.global_position = Vector3(float(placement.get("x", 0.0)), stack_height, float(placement.get("z", 0.0))) # Restores its persistent page-space position and paper layer.
	sticker.rotation_degrees.y = 0.0 # Restores every attached book sticker at its canonical source artwork orientation before peel geometry is configured.
	sticker.configure(sticker_size, texture_resource as Texture2D) # Builds picking, peel mesh, reverse material, and landing outline.
	sticker.set_stack_height(stack_height) # Synchronizes the Sticker component's autonomous landing and return height with persistent stack order.
	var placement_id: String = str(placement.get("id", "")) # Retrieves the stable physical identifier used for future movement saves.
	var runtime_id: int = sticker.get_instance_id() # Retrieves the runtime node key used for fast metadata lookup during pointer interaction.
	_sticker_ids[runtime_id] = placement_id # Associates the interactive node with its authoritative persistent physical record.
	_sticker_pages[runtime_id] = page_index # Associates the interactive node with its absolute virtual page so movement can persist page changes correctly.
	_sticker_stacks[runtime_id] = stack_order # Associates the interactive node with its current logical paper layer.
	_sticker_paths[runtime_id] = sticker_path # Associates the interactive node with immutable source artwork used by click inspection.
	_stack_counter = maxi(_stack_counter, stack_order) # Ensures future grabs and new placements always rise above this restored sticker.
	if animate_landing: # Plays the requested physical arrival only for newly committed manual or auto-packed stickers.
		sticker.begin_new_sticker_landing(Vector2(sticker.global_position.x, sticker.global_position.z), stack_height) # Starts the little upward kick followed by the hard flat page slam.
