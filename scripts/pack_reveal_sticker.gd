class_name PackRevealSticker
extends Area3D

const THROW_DURATION: float = 0.95 # Defines how long one won sticker takes to travel from the opened pack into its flat reveal position.
const THROW_HEIGHT: float = 0.85 # Defines hidden depth lift used for a moving shadow while the sticker remains face-on to the player.
const THROW_SCREEN_LIFT: float = 0.42 # Adds a visible upward screen-space arc in the top-down presentation during the initial throw.
const THROW_STAGGER: float = 0.11 # Delays adjacent pack slots so the five won stickers arrive as a readable sequence instead of one simultaneous pop.
const IDLE_ROTATION_SPEED: float = 0.24 # Defines the slow in-plane rotation used after the throw settles.
const IDLE_FLOAT_HEIGHT: float = 0.08 # Adds a tiny depth bob that changes the shadow without changing apparent sticker size under orthographic projection.

var _pending_index: int = -1 # Stores the reveal-order index represented by this shop sticker.
var _sticker_path: String = "" # Stores the base artwork resource path represented by this physical reveal copy.
var _visual: StickerMesh # Stores the realistic artwork-defined sticker mesh shared with the book simulation.
var _collision_shape: CollisionShape3D # Stores the lightweight picking volume that follows the flat sticker presentation.
var _target_position: Vector3 = Vector3.ZERO # Stores the final floating local-space position for this reveal slot.
var _start_position: Vector3 = Vector3.ZERO # Stores the initial local-space launch point near the opened pack.
var _elapsed: float = 0.0 # Stores reveal-animation time including the per-slot stagger delay.
var _base_yaw: float = 0.0 # Stores the settled in-plane orientation used as the idle rotation origin.
var _phase: float = 0.0 # Stores a deterministic per-slot phase offset for independent shadow-height motion.

func configure(pending_index: int, sticker_key: String, sticker_size: Vector2, sticker_texture: Texture2D, target_position: Vector3) -> void: # Builds one reveal result and applies this exact copy's saved finish.
	_pending_index = pending_index # Associates this reveal object with its deterministic result-order index.
	_sticker_path = StickerVariant.get_art_path(sticker_key) # Stores the authored artwork path independently from the edition key.
	_target_position = target_position # Stores the intended final display position in the shop presentation plane.
	_start_position = Vector3(target_position.x * 0.18, 0.18, target_position.z + 1.65) # Starts all five stickers near the pack and lower on screen before they fan upward into view.
	position = _start_position # Places the sticker at its launch point before the first animation frame.
	_base_yaw = deg_to_rad(float((pending_index * 37) % 360)) # Gives each pack slot a deterministic distinct in-plane settled orientation without runtime randomness.
	_phase = float(pending_index) * 1.37 # Gives each sticker an independent subtle depth-bob phase while remaining deterministic.
	_elapsed = -float(pending_index) * THROW_STAGGER # Applies the reveal-order delay directly to animation time without timers or signals.
	_visual = StickerMesh.new() # Creates the same physical sticker surface used by attached book stickers.
	_visual.name = "visual" # Gives the runtime component a readable tree name.
	add_child(_visual) # Parents the visual under the reveal root so translation and in-plane rotation affect rendering together.
	_visual.configure(sticker_size, sticker_texture, false) # Builds the realistic sheet without using the old boolean gold path.
	StickerVariant.apply_material(_visual, sticker_key) # Applies normal, rainbow, silver, or gold from the exact pulled copy identity.
	_collision_shape = CollisionShape3D.new() # Creates a simple physical picking volume for shop ray queries.
	_collision_shape.name = "pick_shape" # Gives the interaction component a readable runtime name.
	var box_shape: BoxShape3D = BoxShape3D.new() # Creates a thin box matching the complete artwork bounds.
	var physical_size: Vector2 = _visual.get_physical_size() # Retrieves the final artwork-defined sheet dimensions.
	box_shape.size = Vector3(physical_size.x, 0.08, physical_size.y) # Sizes the picking volume to the complete sticker while keeping it physically thin.
	_collision_shape.shape = box_shape # Assigns the configured picking shape to the collision component.
	_collision_shape.position.y = 0.02 # Centers the thin box just above the visible sheet for reliable top-down picking.
	add_child(_collision_shape) # Parents the picking shape under the same animated and rotating root.
	collision_layer = 2 # Places shop reveal stickers on a dedicated collision layer separate from book stickers.
	collision_mask = 0 # Disables unnecessary overlap monitoring against every other world object.
	monitoring = false # Prevents continuous overlap work because interaction uses explicit pointer ray queries.
	monitorable = true # Keeps the area available to direct physics-space ray intersection.
	input_ray_pickable = true # Keeps the reveal object eligible for pointer selection.

func settle_immediately() -> void: # Places a revealed sticker directly into its flat inspection state without replaying the throw.
	_elapsed = THROW_DURATION # Advances the one-time reveal clock to the first settled idle frame.
	visible = true # Ensures the sticker is immediately visible.
	position = _target_position # Restores the exact floating reveal-slot position without another launch arc.
	rotation = Vector3(0.0, _base_yaw, 0.0) # Keeps the printed face perfectly parallel to the screen while preserving its in-plane orientation.

func get_pending_index() -> int: # Returns the reveal-order index represented by this object.
	return _pending_index # Exposes the stable result-order index without allowing external mutation.

func get_sticker_path() -> String: # Returns the base artwork path represented by this reveal object.
	return _sticker_path # Exposes the design identifier for debugging.

func _process(delta: float) -> void: # Advances the initial flat-view throw and continuous in-plane rotation without perspective tilting.
	_elapsed += delta # Advances animation time regardless of whether the current slot is still waiting for its stagger delay.
	if _elapsed < 0.0: # Keeps later pack slots hidden near the pack until their reveal-order delay has elapsed.
		visible = false # Prevents unrevealed stickers from appearing before their toss begins.
		return # Waits for this slot's stagger delay without performing unnecessary transforms.
	visible = true # Shows the sticker as soon as its toss begins.
	if _elapsed < THROW_DURATION: # Advances the one-time fan-out throw while the sticker has not reached its display position.
		var linear_progress: float = clampf(_elapsed / THROW_DURATION, 0.0, 1.0) # Normalizes the throw time into a stable zero-to-one range.
		var eased_progress: float = 1.0 - pow(1.0 - linear_progress, 3.0) # Uses cubic ease-out so the sticker launches decisively then settles gently.
		var current_position: Vector3 = _start_position.lerp(_target_position, eased_progress) # Moves the sticker across the flat shop presentation toward its assigned reveal slot.
		current_position.z -= sin(linear_progress * PI) * THROW_SCREEN_LIFT # Adds a readable upward screen-space arc while the camera remains perfectly top-down.
		current_position.y += sin(linear_progress * PI) * THROW_HEIGHT # Lifts the hidden depth coordinate only to animate the real sticker shadow beneath the flat view.
		position = current_position # Applies the complete current throw position.
		rotation = Vector3(0.0, _base_yaw + linear_progress * PI * 1.35, 0.0) # Spins only around the face normal so the sticker never presents an angled 3D card view.
		return # Leaves continuous idle rotation until the one-time throw has fully settled.
	var idle_time: float = _elapsed - THROW_DURATION # Measures time spent floating after the throw animation completed.
	position = _target_position + Vector3(0.0, sin(idle_time * 1.15 + _phase) * IDLE_FLOAT_HEIGHT, 0.0) # Changes only hidden depth for a subtle moving shadow without screen-space perspective motion.
	rotation = Vector3(0.0, _base_yaw + idle_time * IDLE_ROTATION_SPEED, 0.0) # Rotates slowly in the screen plane while keeping the printed face fully visible at all times.
