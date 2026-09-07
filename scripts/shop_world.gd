class_name ShopWorld extends Node3D # Owns physical pack reveals while its HUD owns native UI actions.

const PICK_DISTANCE: float = 100.0 # Bounds physical sticker selection rays.
const REVEAL_COLLISION_MASK: int = 2 # Restricts shop picking to pack-result stickers.

@onready var _camera: Camera3D = $world/camera as Camera3D # Projects the flat physical reveal into the usable screen area.
@onready var _environment_node: WorldEnvironment = $world/environment as WorldEnvironment # Owns shop-specific lighting and background.
@onready var _interface: CanvasLayer = $interface as CanvasLayer # Controls the composed shop HUD's visibility.
@onready var _hud: ShopHUD = $interface/shop_hud as ShopHUD # Delegates purchase presentation and result actions to native controls.
@onready var _reveal_root: Node3D = $world/reveals as Node3D # Owns physical reveal sheets for the current unresolved pack.

var _controller: GameController # Delegates economy mutations and world transitions.
var _environment_resource: Environment # Preserves the shop environment while its world is inactive.
var _catalog: StickerCatalog # Supplies original artwork and physical dimensions.
var _book_state: StickerBookState # Supplies persisted unresolved copies.
var _active: bool = false # Guards physical input during inactive destinations.
var _reveal_nodes: Array[PackRevealSticker] = [] # Tracks the current physical result sheets.

func configure(controller: GameController, economy: StickerEconomy, catalog: StickerCatalog, book_state: StickerBookState) -> void: # Binds authoritative models and the independent HUD.
	_controller = controller # Retains transaction and navigation ownership.
	_environment_resource = _environment_node.environment # Preserves the environment for later activation.
	_catalog = catalog # Retains the imported artwork catalogue.
	_book_state = book_state # Retains pending-copy persistence.
	_hud.configure(controller, economy, catalog, book_state) # Binds native offer and placement actions.
	show_pending(false) # Initializes the current pack presentation.

func set_active(active: bool) -> void: # Transfers camera, rendering, and input ownership between worlds.
	_active = active # Updates the physical picking guard.
	visible = active # Shows or hides the physical counter and sticker sheets.
	_interface.visible = active # Shows only the active world's screen-space HUD.
	_camera.current = active # Transfers orthographic camera ownership.
	_environment_node.environment = _environment_resource if active else null # Avoids competing world environments.
	process_mode = Node.PROCESS_MODE_INHERIT if active else Node.PROCESS_MODE_DISABLED # Stops hidden reveal animation and HUD polling.
	if active: # Rebuilds the small pending-pack presentation on actual shop entry.
		show_pending(false) # Reflects copies consumed by manual placement in the book.

func show_pending(animate_throw: bool) -> void: # Rebuilds the changed pack's physical sheets and accessible choice buttons.
	_clear_reveal() # Retires physical sheets belonging to the previous pending state.
	var paths: PackedStringArray = _book_state.get_pending_copy() # Reads the exact remaining saved copies.
	var global_targets: Array[Vector3] = [] # Aligns native result labels with the physical reveal anchors.
	for index: int in range(paths.size()): # Creates a separate sheet for each exact pending copy.
		var path: String = paths[index] # Reads this copy's stable artwork identity.
		var texture: Texture2D = load(path) as Texture2D # Reuses the imported artwork texture.
		if texture == null: # Handles missing imported artwork without a broken mesh.
			global_targets.append(global_position + Vector3(float(index - 2) * 2.15, 0.6, 0.0)) # Keeps the HUD's result-index mapping intact.
			continue # Leaves unavailable artwork recoverable through normal transaction guards.
		var target: Vector3 = Vector3((float(index) - float(paths.size() - 1) * 0.5) * 2.15, 0.65, 0.0) # Centers the unresolved copies in one readable row.
		var reveal: PackRevealSticker = PackRevealSticker.new() # Creates the existing shader-based physical sheet.
		reveal.name = "reveal_%d" % index # Gives each copy a stable local debug identity.
		_reveal_root.add_child(reveal) # Attaches the sheet before its material and collision setup.
		reveal.configure(index, path, _catalog.get_default_size(path), texture, target) # Preserves the original physical dimensions and reveal animation.
		if not animate_throw: # Avoids replaying the reward throw after returning from manual placement.
			reveal.settle_immediately() # Displays the remaining copies in their settled reveal positions.
		_reveal_nodes.append(reveal) # Retains the sheet for cleanup when pending state changes.
		global_targets.append(_reveal_root.to_global(target)) # Supplies the matching absolute anchor to the HUD.
	_hud.show_choices(paths, global_targets, _camera) # Presents either offers or the exact unresolved result actions.

func get_ui() -> ShopHUD: # Exposes the composed HUD for scoped keyboard navigation.
	return _hud # Keeps presentation ownership inside the shop component.

func _unhandled_input(event: InputEvent) -> void: # Picks physical stickers only after native controls have processed input.
	if not _active or _controller.is_gameplay_input_blocked(): # Rejects interaction beneath inactive destinations and modals.
		return # Leaves the active UI surface in control.
	if event is not InputEventMouseButton: # Limits physical picking to pointer button events.
		return # Leaves native navigation and text input untouched.
	var mouse: InputEventMouseButton = event as InputEventMouseButton # Narrows the physical pointer event.
	if not mouse.pressed or mouse.button_index != MOUSE_BUTTON_LEFT: # Selects physical sheets on a left press only.
		return # Ignores releases and unrelated mouse buttons.
	if _controller.is_pointer_over_game_ui(mouse.position) or _hud.owns_pointer(mouse.position): # Reserves native interface regions from 3D picking.
		return # Prevents UI click-through and duplicate pack-result activation.
	_pick_reveal_sticker(mouse.position) # Resolves direct artwork selection through the physics ray.

func _pick_reveal_sticker(position: Vector2) -> void: # Routes a clicked physical sheet to its exact pending copy.
	if not _book_state.has_pending_stickers(): # Avoids physics queries when no physical reward is waiting.
		return # Leaves the purchase UI as the only shop action.
	var origin: Vector3 = _camera.project_ray_origin(position) # Starts the pick ray in the active orthographic camera.
	var direction: Vector3 = _camera.project_ray_normal(position) # Obtains its world-space direction.
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(origin, origin + direction * PICK_DISTANCE, REVEAL_COLLISION_MASK) # Limits the ray to physical pack-result collision layers.
	query.collide_with_areas = true # Enables the existing reveal Area3D sheets.
	query.collide_with_bodies = false # Excludes the counter and other physical bodies.
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query) # Performs one bounded physics lookup per artwork selection.
	var reveal: PackRevealSticker = hit.get("collider") as PackRevealSticker # Resolves the selected physical result safely.
	if reveal != null: # Rejects empty space and unrelated collision results.
		_controller.begin_manual_placement(reveal.get_pending_index(), reveal.get_sticker_path()) # Transfers the exact saved copy into manual book placement.

func _clear_reveal() -> void: # Releases physical sheets after their pending state changes.
	for reveal: PackRevealSticker in _reveal_nodes: # Visits only the current small pack-result set.
		if is_instance_valid(reveal): # Handles a sheet already removed during a transition safely.
			_reveal_root.remove_child(reveal) # Removes stale collision and rendering ownership immediately.
			reveal.queue_free() # Releases the old physical sheet after event dispatch.
	_reveal_nodes.clear() # Clears expired references before creating another reveal.
