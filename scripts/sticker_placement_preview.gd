class_name StickerPlacementPreview
extends Node3D

const PREVIEW_HEIGHT: float = 0.42 # Holds a newly won sticker visibly above the page while the player chooses where to stick it manually.

var _visual: StickerMesh # Stores the full realistic artwork-defined front-face preview that follows the pointer over the book.
var _landing_preview: StickerLandingPreview # Stores the faint exact alpha-silhouette projection showing where the upright manual sticker will land.
var _valid: bool = false # Stores whether the current pointer position lies on a usable page and can be committed.

func configure(sticker_size: Vector2, sticker_texture: Texture2D, sticker_key: String = "") -> void: # Builds the floating physical sticker and applies the exact saved edition finish.
	_visual = StickerMesh.new() # Creates the same artwork-defined material surface used by normal interactive stickers.
	_visual.name = "visual" # Gives the preview renderer a readable runtime tree name.
	add_child(_visual) # Parents the renderer under the movable placement-preview composition.
	_visual.configure(sticker_size, sticker_texture, false) # Builds the printed front, reverse, and physical sheet geometry without using the legacy boolean special path.
	StickerVariant.apply_material(_visual, sticker_key) # Applies normal, rainbow, silver, or gold from the exact collection copy identity.
	_landing_preview = StickerLandingPreview.new() # Creates the exact projected alpha-outline component used for landing prediction.
	_landing_preview.name = "landing_preview" # Gives the projected helper a readable runtime tree name.
	add_child(_landing_preview) # Keeps lifecycle ownership with the placement preview while the outline itself remains top-level in world space.
	_landing_preview.configure(_visual.mesh, sticker_texture) # Reuses the exact mesh and source alpha so projection and final sticker match perfectly.
	visible = false # Keeps the preview hidden until the pointer enters a usable page placement area.

func get_physical_size() -> Vector2: # Exposes the complete artwork-defined sticker bounds used by manual page-fit validation.
	return _visual.get_physical_size() if _visual != null else Vector2.ONE # Returns the composed sticker sheet dimensions without regenerating its alpha contour.

func update_target(world_xz: Vector2, _yaw_degrees: float, valid: bool, landing_height: float) -> void: # Moves the upright floating preview and its page outline to the exact manual placement target.
	_valid = valid # Stores whether a left click can currently commit the pending sticker.
	visible = valid # Hides the physical sticker completely when the pointer leaves both usable page surfaces.
	if not valid: # Handles invalid spine, margin, or off-book pointer positions.
		_landing_preview.hide_preview() # Removes the projected target so no invalid landing location is implied.
		return # Leaves the last valid transform harmlessly cached until the pointer returns to a page.
	global_position = Vector3(world_xz.x, landing_height + PREVIEW_HEIGHT, world_xz.y) # Holds the new sticker visibly above the exact x/z position chosen by the pointer.
	global_rotation = Vector3.ZERO # Locks the preview to the original artwork orientation that every book placement must retain.
	_landing_preview.show_at(global_basis, global_position, landing_height) # Projects the final flat alpha silhouette directly beneath the upright floating sticker.

func is_valid() -> bool: # Reports whether the current preview target can be committed to the physical book.
	return _valid # Returns the page-validity state calculated by the book controller.

func clear() -> void: # Removes every manual placement helper before returning to the collection or converting the preview into a real sticker.
	if _landing_preview != null: # Verifies that the projected outline was composed successfully before hiding it.
		_landing_preview.hide_preview() # Removes the exact target silhouette immediately.
	queue_free() # Frees the temporary floating renderer at the end of the current frame.
