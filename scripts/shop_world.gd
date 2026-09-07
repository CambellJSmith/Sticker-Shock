class_name ShopWorld
extends Node3D

const PICK_DISTANCE: float = 100.0 # Defines the maximum camera ray length used when clicking physical floating pack results.
const REVEAL_COLLISION_MASK: int = 2 # Selects only dedicated shop reveal Area3D objects during physical sticker picking.

@onready var _camera: Camera3D = $world/camera as Camera3D # References the dedicated camera for the separate shop world.
@onready var _environment_node: WorldEnvironment = $world/environment as WorldEnvironment # References the shop-specific lighting environment so inactive worlds cannot compete for shared environment ownership.
@onready var _interface: CanvasLayer = $interface as CanvasLayer # References the shop HUD layer so world switching hides its controls as well as its 3D geometry.
@onready var _reveal_root: Node3D = $world/reveals as Node3D # References the composition node that owns all currently floating won stickers.
@onready var _currency_label: Label = $interface/top_left/panel/content/currency as Label # References the current spendable in-game currency display.
@onready var _cooldown_label: Label = $interface/top_left/panel/content/cooldown as Label # References the real-world free-pack eligibility countdown.
@onready var _status_label: Label = $interface/top_left/panel/content/status as Label # References contextual pack and placement guidance.
@onready var _buy_button: Button = $interface/bottom_bar/panel/content/buy_pack as Button # References the normal in-game-currency pack purchase control.
@onready var _free_button: Button = $interface/bottom_bar/panel/content/free_pack as Button # References the six-real-world-hour free-pack claim control.
@onready var _auto_button: Button = $interface/bottom_bar/panel/content/auto_stick as Button # References the automatic alpha-silhouette tight-packing control.
@onready var _book_button: Button = $interface/bottom_bar/panel/content/book as Button # References navigation back to the persistent sticker book.

var _controller: GameController # Stores the root coordinator that owns transactions, persistent state, packing, and world switching.
var _environment_resource: Environment # Stores the shop environment resource while this world is inactive and its WorldEnvironment is deliberately cleared.
var _economy: StickerEconomy # Stores persistent currency, collection ownership, pack price, and free-pack cooldown.
var _catalog: StickerCatalog # Stores automatically discovered sticker artwork and default physical dimensions.
var _book_state: StickerBookState # Stores the current unresolved physical pack and every attached sticker placement.
var _active: bool = false # Stores whether this separate shop world currently owns camera and pointer input.
var _refresh_accumulator: float = 0.0 # Throttles text-only real-world cooldown refresh work while preserving a smooth readable countdown.
var _reveal_nodes: Array[PackRevealSticker] = [] # Stores the five or fewer currently pending physical floating sticker objects in reveal order.

func configure(controller: GameController, economy: StickerEconomy, catalog: StickerCatalog, book_state: StickerBookState) -> void: # Binds shared models and initializes the separate physical shop presentation.
	_controller = controller # Stores the coordinator used for transactions and movement into the book world.
	_environment_resource = _environment_node.environment # Caches this scene's dedicated environment before inactive-world clearing begins.
	_economy = economy # Stores the authoritative in-game-currency and free-pack progression model.
	_catalog = catalog # Stores automatically discovered sticker artwork and dimensions.
	_book_state = book_state # Stores the authoritative pending physical pack used for reveal rebuilding and transaction blocking.
	_refresh_labels() # Populates currency, countdown, button states, and collection context immediately.
	show_pending(false) # Reconstructs any same-session pending reveal without replaying its launch animation.

func set_active(active: bool) -> void: # Enables or disables the complete separate shop world while preserving an opened pack in memory.
	_active = active # Stores whether shop input should currently be interpreted.
	visible = active # Hides all shop geometry and interface while the player is inside the book world.
	_interface.visible = active # Hides or shows the shop HUD explicitly because CanvasLayer visibility is independent from Node3D rendering visibility.
	_camera.current = active # Gives camera ownership exclusively to whichever gameplay world is active.
	if active: # Restores the shop-specific environment only while the player is physically in the shop.
		_environment_node.environment = _environment_resource # Activates the shop lighting, background, and ambient settings without interference from the hidden book world.
	else: # Clears environment ownership while the book world is active.
		_environment_node.environment = null # Prevents hidden shop environment settings from affecting the separate book presentation.
	if active: # Refreshes dynamic progression whenever the player enters the shop.
		_refresh_labels() # Updates currency, cooldown, and pack availability from authoritative persistent models.
		show_pending(false) # Rebuilds only unresolved physical stickers after any manual book placement changed pending indices.

func show_pending(animate_throw: bool) -> void: # Rebuilds the physical pack reveal from the authoritative unresolved pending sticker list.
	_clear_reveal() # Removes stale reveal nodes whose pending indices may have changed after manual placement.
	var pending_paths: PackedStringArray = _book_state.get_pending_copy() # Takes one stable reveal-order snapshot of every physical sticker still waiting for placement.
	if pending_paths.is_empty(): # Handles the normal shop state before a pack is opened or after all five stickers are placed.
		_status_label.text = "buy_or_claim_a_pack_to_reveal_5_stickers" # Shows the primary shop action when no physical reveal exists.
		_refresh_labels() # Re-enables pack acquisition controls after the previous pending pack has been fully resolved.
		return # Leaves the display table empty until another pack transaction succeeds.
	var target_positions: Array[Vector3] = [Vector3(-4.0, 0.62, -0.70), Vector3(-2.0, 0.66, 0.22), Vector3(0.0, 0.64, -0.12), Vector3(2.0, 0.67, 0.28), Vector3(4.0, 0.63, -0.68)] # Defines five flat-view fan-out destinations with only a small hidden depth offset for soft shadows.
	for pending_index: int in range(pending_paths.size()): # Composes one clickable floating physical sticker for every unresolved pack slot.
		var sticker_path: String = pending_paths[pending_index] # Retrieves the exact won design represented by the current unresolved physical copy.
		var texture_resource: Resource = ResourceLoader.load(sticker_path, "Texture2D") # Loads the imported artwork through Godot's resource cache.
		if texture_resource is not Texture2D: # Skips only invalid artwork instead of breaking the complete reveal.
			push_error("shop reveal texture could not be loaded: %s" % sticker_path) # Reports the exact invalid pack resource for debugging.
			continue # Advances to the next won sticker copy.
		var reveal_sticker: PackRevealSticker = PackRevealSticker.new() # Creates one clickable face-on pack result that retains hidden depth only for shadow rendering.
		reveal_sticker.name = "reveal_%d_%s" % [pending_index, sticker_path.get_file().get_basename()] # Gives the runtime node a readable reveal-order name.
		_reveal_root.add_child(reveal_sticker) # Parents the physical result under the dedicated shop reveal composition.
		var target_position: Vector3 = target_positions[pending_index % target_positions.size()] # Selects the configured fan-out slot while remaining safe if pack size changes later.
		reveal_sticker.configure(pending_index, sticker_path, _catalog.get_default_size(sticker_path), texture_resource as Texture2D, target_position) # Builds the artwork-defined sheet, picking volume, flat screen-space toss arc, and in-plane idle rotation.
		if not animate_throw: # Handles returning from the book to an already opened pack.
			reveal_sticker.settle_immediately() # Restores unresolved stickers directly to floating inspection rather than theatrically opening the same pack again.
		_reveal_nodes.append(reveal_sticker) # Caches the physical reveal node for explicit lifecycle cleanup without scene-tree searching.
	_status_label.text = "click_a_sticker_to_place_it_manually  ·  or_use_auto_stick" # Explains both placement routes while the five results float in the flat shop presentation.
	_refresh_labels() # Disables buying another pack until this physical reveal has been completely dealt with.

func _process(delta: float) -> void: # Advances only throttled progression text refresh work while this shop world is active.
	if not _active: # Skips UI refresh work while the book world owns the player.
		return # Leaves hidden shop presentation dormant except for individual reveal-node animation state.
	_refresh_accumulator += delta # Accumulates time toward the next real-world cooldown display update.
	if _refresh_accumulator < 0.25: # Limits small text and disabled-state recalculation to four times per second.
		return # Avoids unnecessary per-frame string formatting.
	_refresh_accumulator = 0.0 # Restarts the lightweight refresh interval.
	_refresh_labels() # Updates currency, free-pack time, and action availability from authoritative models.

func _input(event: InputEvent) -> void: # Owns shop-world UI and physical floating-sticker clicks directly without signals.
	if not _active: # Ignores every input event while another destination owns presentation.
		return # Prevents hidden shop controls and reveal collisions from responding.
	if _controller != null and _controller.is_gameplay_input_blocked(): # Detects pause and other modal interface states that deliberately suspend physical interaction.
		return # Leaves pack reveal and shop controls untouched while a modal surface owns input.
	if event is not InputEventMouseButton: # Uses only discrete mouse-button events for shop transactions and reveal selection.
		return # Leaves pointer motion entirely to visual hover behavior and floating sticker animation.
	var mouse_button: InputEventMouseButton = event as InputEventMouseButton # Narrows the event for strongly typed button and screen-position access.
	if _controller != null and _controller.is_pointer_over_game_ui(mouse_button.position): # Detects clicks owned by the persistent navigation rail or top status bar.
		return # Prevents global navigation clicks from purchasing packs or selecting reveal stickers underneath the shell.
	if not mouse_button.pressed or mouse_button.button_index != MOUSE_BUTTON_LEFT: # Responds only to primary-button press events.
		return # Ignores releases and secondary buttons.
	if _buy_button.get_global_rect().has_point(mouse_button.position): # Detects a normal pack purchase control click before physical world picking.
		_controller.purchase_pack(false) # Requests one authoritative in-game-currency transaction and physical five-sticker reveal.
		get_viewport().set_input_as_handled() # Prevents the UI click from selecting a floating sticker behind the button.
		return # Completes the purchase click as the sole action.
	if _free_button.get_global_rect().has_point(mouse_button.position): # Detects the six-hour free-pack claim control.
		_controller.purchase_pack(true) # Requests one authoritative free transaction and starts the next real-world cooldown on success.
		get_viewport().set_input_as_handled() # Prevents the UI click from reaching world picking.
		return # Completes the free claim click.
	if _auto_button.get_global_rect().has_point(mouse_button.position): # Detects automatic physical placement for every currently unresolved won sticker.
		_controller.auto_stick_pending(true) # Runs tight alpha-silhouette packing, commits all solvable pending stickers, and switches to the book to show the result.
		get_viewport().set_input_as_handled() # Prevents the action click from also selecting a floating reveal object.
		return # Completes automatic placement as the sole action.
	if _book_button.visible and _book_button.get_global_rect().has_point(mouse_button.position): # Detects legacy local navigation only when that world-specific control is intentionally shown.
		_controller.show_book() # Switches cameras and visible world composition without destroying the opened pack state.
		get_viewport().set_input_as_handled() # Prevents the navigation click from ray-picking a reveal behind the UI.
		return # Completes world navigation.
	_pick_reveal_sticker(mouse_button.position) # Attempts to select one physical floating won sticker for manual book placement when no UI action was clicked.

func _pick_reveal_sticker(screen_position: Vector2) -> void: # Ray-picks one rotating physical won sticker and sends that exact pending copy into manual book placement mode.
	if not _book_state.has_pending_stickers(): # Rejects stale world clicks after the last pending sticker has already been committed.
		return # Leaves the empty shop display unchanged.
	var ray_origin: Vector3 = _camera.project_ray_origin(screen_position) # Converts the pointer into a world-space camera ray origin inside the separate shop space.
	var ray_direction: Vector3 = _camera.project_ray_normal(screen_position) # Converts the pointer into the matching normalized world-space ray direction.
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(ray_origin, ray_origin + ray_direction * PICK_DISTANCE, REVEAL_COLLISION_MASK) # Creates a reveal-only physics query that cannot hit book stickers in the distant book world.
	query.collide_with_areas = true # Allows direct intersection with PackRevealSticker Area3D picking volumes.
	query.collide_with_bodies = false # Excludes decorative shop geometry from reveal selection.
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query) # Performs one nearest physical result query under the pointer.
	if hit.is_empty(): # Handles clicks that do not land on a floating won sticker.
		return # Leaves the reveal untouched without noisy status changes.
	var collider: Object = hit.get("collider") as Object # Retrieves the selected shop physics object.
	if collider is not PackRevealSticker: # Rejects any future layer-two area that is not a pack result composition.
		return # Keeps manual placement routing isolated from unrelated shop objects.
	var reveal_sticker: PackRevealSticker = collider as PackRevealSticker # Narrows the selected physical object to the reveal API.
	var pending_index: int = reveal_sticker.get_pending_index() # Retrieves the exact current unresolved pack index represented by this floating copy.
	var sticker_path: String = reveal_sticker.get_sticker_path() # Retrieves the design path for authoritative pending-state validation.
	_controller.begin_manual_placement(pending_index, sticker_path) # Switches to the book carrying this exact physical won sticker for player-chosen placement.

func _refresh_labels() -> void: # Synchronizes all shop text and action enabled states with authoritative persistent progression.
	if _economy == null or _catalog == null or _book_state == null: # Protects editor scene previews before runtime model configuration.
		return # Leaves placeholder scene text untouched until the coordinator binds real models.
	_currency_label.text = "currency  %d" % _economy.get_currency() # Displays the current spendable in-game currency balance.
	var seconds_remaining: int = _economy.get_free_pack_seconds_remaining() # Reads the real-world free-pack wait once for consistent display and button state.
	if seconds_remaining <= 0 and not _catalog.is_empty(): # Handles an immediately claimable free pack.
		_cooldown_label.text = "free_pack  ready" # Shows explicit real-world eligibility.
	else: # Handles an active six-hour wait or missing catalogue content.
		_cooldown_label.text = "next_free_pack  %s" % _format_duration(seconds_remaining) # Shows the remaining UTC-system-clock cooldown in fixed-width hours, minutes, and seconds.
	var has_pending: bool = _book_state.has_pending_stickers() # Reads whether an opened physical pack must be placed before another pack can be acquired.
	_buy_button.text = "buy_pack  %d" % _economy.get_pack_price() # Shows the exact in-game-currency price directly on the normal purchase control.
	_buy_button.disabled = has_pending or not _economy.can_buy_pack(_catalog) # Blocks purchases during an unresolved physical reveal, insufficient funds, or an empty sticker catalogue.
	_free_button.text = "free_pack" # Keeps the free action label compact while detailed time remains in the status panel.
	_free_button.disabled = has_pending or not _economy.can_claim_free_pack(_catalog) # Blocks early claims and prevents multiple unresolved physical packs from overlapping.
	_auto_button.disabled = not has_pending # Enables automatic tight packing only while at least one won sticker remains physically unresolved.
	if has_pending: # Shows how many physical pack results still need to enter the book.
		_auto_button.text = "auto_stick_%d" % _book_state.get_pending_count() # Communicates exactly how many unresolved stickers the solver will place.
	else: # Restores the generic action text when no pack is waiting.
		_auto_button.text = "auto_stick" # Keeps the disabled control stable between packs.

func _clear_reveal() -> void: # Frees every currently composed floating pack result before rebuilding authoritative pending indices.
	for reveal_sticker: PackRevealSticker in _reveal_nodes: # Visits only cached physical reveal nodes owned by this shop composition.
		if is_instance_valid(reveal_sticker): # Verifies the node has not already been removed externally.
			reveal_sticker.queue_free() # Schedules the obsolete physical result for safe end-of-frame deletion.
	_reveal_nodes.clear() # Removes stale runtime references immediately before new reveal objects are composed.

func _format_duration(total_seconds: int) -> String: # Formats a nonnegative real-world wait into fixed-width hours, minutes, and seconds.
	var safe_seconds: int = maxi(total_seconds, 0) # Prevents negative formatting if eligibility passes between model reads.
	var hours: int = safe_seconds / 3600 # Calculates complete remaining hours with integer arithmetic.
	var minutes: int = (safe_seconds % 3600) / 60 # Calculates complete remaining minutes after removing whole hours.
	var seconds: int = safe_seconds % 60 # Calculates remaining seconds after removing whole minutes.
	return "%02d:%02d:%02d" % [hours, minutes, seconds] # Returns a stable countdown string that does not visually jitter as digits change.
