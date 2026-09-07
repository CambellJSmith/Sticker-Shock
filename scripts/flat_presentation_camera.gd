class_name FlatPresentationCamera
extends Camera3D

const VERTICAL_WORLD_SIZE: float = 9.2 # Defines the fixed vertical world span used by every flat gameplay presentation.
const CAMERA_HEIGHT: float = 12.0 # Keeps the orthographic camera safely above every peel, throw, and landing animation.
const SHELL_LEFT_PIXELS: float = 176.0 # Reserves the persistent navigation rail so the flat world is centered in the usable gameplay area.
const SHELL_TOP_PIXELS: float = 64.0 # Reserves the persistent top status bar so the flat world does not sit underneath it.
const WORLD_BOTTOM_PIXELS: float = 86.0 # Reserves contextual controls near the bottom of the book and shop screens.

var _last_viewport_size: Vector2 = Vector2.ZERO # Caches the last viewport dimensions so resize framing work runs only when dimensions actually change.

func _ready() -> void: # Configures this camera as a perfectly perpendicular flat presentation camera.
	projection = Camera3D.PROJECTION_ORTHOGONAL # Removes perspective scaling so lifted objects retain the same apparent dimensions on screen.
	keep_aspect = Camera3D.KEEP_HEIGHT # Locks the vertical world span while wider displays reveal proportionally more horizontal workspace.
	size = VERTICAL_WORLD_SIZE # Sets the stable flat-view scale shared by the book and shop.
	rotation_degrees = Vector3(-90.0, 0.0, 0.0) # Points the camera straight down at the horizontal presentation surface with no perspective angle.
	near = 0.05 # Keeps close peel geometry visible while preserving useful depth precision.
	far = 100.0 # Keeps every presentation element inside the camera clipping range.
	_update_framing(true) # Centers the world inside the persistent game shell before the first rendered gameplay frame.

func _process(_delta: float) -> void: # Keeps the flat composition centered when the game window changes size.
	_update_framing(false) # Recalculates only after a viewport-size change rather than performing framing arithmetic every frame.

func _update_framing(force_update: bool) -> void: # Maps the screen-space game-shell safe area into an orthographic world-space camera offset.
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size # Reads the actual drawable viewport dimensions after project stretch behavior is applied.
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0: # Rejects transient invalid dimensions during startup or platform resize transitions.
		return # Preserves the previous valid camera transform until usable dimensions return.
	if not force_update and viewport_size.is_equal_approx(_last_viewport_size): # Detects frames where the screen dimensions are unchanged.
		return # Avoids redundant camera writes during ordinary gameplay.
	_last_viewport_size = viewport_size # Stores the new dimensions before computing the corresponding safe-area center.
	var content_left: float = minf(SHELL_LEFT_PIXELS, viewport_size.x * 0.35) # Keeps the navigation reservation sane on unusually narrow windows.
	var content_top: float = minf(SHELL_TOP_PIXELS, viewport_size.y * 0.25) # Keeps the top-bar reservation sane on unusually short windows.
	var content_bottom: float = minf(WORLD_BOTTOM_PIXELS, viewport_size.y * 0.28) # Keeps contextual-control clearance sane on unusually short windows.
	var content_right: float = viewport_size.x # Uses the full right edge because the global shell has no permanent right-side rail.
	var content_lower: float = maxf(content_top + 1.0, viewport_size.y - content_bottom) # Guarantees a positive usable vertical presentation region.
	var content_center_pixels: Vector2 = Vector2((content_left + content_right) * 0.5, (content_top + content_lower) * 0.5) # Finds the exact center of the visible world area not covered by persistent UI.
	var viewport_center_pixels: Vector2 = viewport_size * 0.5 # Finds the full-window center used as the orthographic projection origin before shell compensation.
	var pixel_offset: Vector2 = content_center_pixels - viewport_center_pixels # Measures how far the usable world center is displaced by the navigation shell.
	var aspect_ratio: float = viewport_size.x / viewport_size.y # Converts the locked vertical span into the current horizontal orthographic span.
	var horizontal_world_size: float = VERTICAL_WORLD_SIZE * aspect_ratio # Calculates visible world width under KEEP_HEIGHT orthographic projection.
	var world_offset_x: float = pixel_offset.x / viewport_size.x * horizontal_world_size # Converts horizontal shell displacement from screen pixels into page-space world units.
	var world_offset_z: float = pixel_offset.y / viewport_size.y * VERTICAL_WORLD_SIZE # Converts downward screen displacement into the matching positive world-z offset.
	position = Vector3(world_offset_x, CAMERA_HEIGHT, world_offset_z) # Applies a resize-safe top-down camera position centered on the actual gameplay canvas.
