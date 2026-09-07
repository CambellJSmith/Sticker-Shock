class_name FlatPresentationCamera extends Camera3D # Fits physical content inside the actual unobstructed UI area.

const CONTENT_SIZE: Vector2 = Vector2(11.8, 7.7) # Reserves enough world space for the complete book cover and reveal row.
const CAMERA_HEIGHT: float = 12.0 # Keeps the camera perpendicular to the physical presentation plane.
const SHELL_LEFT: float = 160.0 # Matches the shared navigation rail width.
const SHELL_TOP: float = 64.0 # Matches the shared status-bar height.
const WORLD_BOTTOM: float = 84.0 # Matches the native world toolbar height.
const FRAME_MARGIN: float = 28.0 # Adds breathing room around the physical presentation.

var _last_viewport_size: Vector2 = Vector2.ZERO # Avoids recomputing framing when window geometry is unchanged.

func _ready() -> void: # Establishes a flat camera with a responsive physical-content frame.
	projection = Camera3D.PROJECTION_ORTHOGONAL # Preserves apparent sticker scale during physical depth effects.
	keep_aspect = Camera3D.KEEP_HEIGHT # Makes the vertical world scale explicit for fitting.
	rotation_degrees = Vector3(-90.0, 0.0, 0.0) # Looks directly down at the book and shop planes.
	near = 0.05 # Keeps nearby physical sheets within the camera frustum.
	far = 100.0 # Includes the complete physical scene composition.
	_update_framing() # Fits the initial viewport immediately.

func _process(_delta: float) -> void: # Responds to window resizing without per-frame scene reconstruction.
	_update_framing() # Returns immediately when the viewport size has not changed.

func _update_framing() -> void: # Fits both axes and centers the world inside its reserved screen rectangle.
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size # Reads the actual logical viewport size after stretch scaling.
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0 or viewport_size.is_equal_approx(_last_viewport_size): # Rejects invalid or unchanged geometry.
		return # Avoids redundant camera updates.
	_last_viewport_size = viewport_size # Caches the geometry used for this framing pass.
	var available: Vector2 = Vector2(maxf(viewport_size.x - SHELL_LEFT - FRAME_MARGIN * 2.0, 1.0), maxf(viewport_size.y - SHELL_TOP - WORLD_BOTTOM - FRAME_MARGIN * 2.0, 1.0)) # Measures the unobstructed physical content region.
	size = maxf(CONTENT_SIZE.y * viewport_size.y / available.y, CONTENT_SIZE.x * viewport_size.y / available.x) # Fits the whole book on both narrow and wide windows.
	var content_center: Vector2 = Vector2((SHELL_LEFT + viewport_size.x) * 0.5, (SHELL_TOP + viewport_size.y - WORLD_BOTTOM) * 0.5) # Finds the center of the usable screen area.
	var offset: Vector2 = (content_center - viewport_size * 0.5) * (size / viewport_size.y) # Converts the desired screen offset into world units.
	position = Vector3(-offset.x, CAMERA_HEIGHT, -offset.y) # Offsets the camera opposite the desired content shift.
