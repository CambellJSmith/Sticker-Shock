class_name StickerInspection # Owns an isolated freely rotatable physical artwork preview.
extends Control # Keeps inspection input and presentation separate from the saved book.

const MIN_ZOOM: float = 0.45 # Defines the smallest inspection magnification allowed while keeping the sticker readable.
const MAX_ZOOM: float = 4.0 # Defines the largest inspection magnification allowed for close surface examination.
const ZOOM_STEP: float = 1.16 # Defines one multiplicative mouse-wheel or button zoom increment.
const CAMERA_PADDING: float = 1.22 # Adds breathing room around the sticker's complete 3D rotation envelope.
const ROLL_RADIANS_PER_PIXEL: float = 0.010 # Converts explicit right-drag movement into screen-axis roll.
const ROTATION_NONE: int = 0 # Identifies the idle inspection pointer state.
const ROTATION_ARCBALL: int = 1 # Identifies free virtual-trackball rotation using the primary mouse button.
const ROTATION_ROLL: int = 2 # Identifies explicit roll rotation using the secondary mouse button.

@onready var _stage: Control = $stage as Control # References the clipped inspection canvas that owns all temporary 3D presentation input.
@onready var _viewport_container: SubViewportContainer = $stage/viewport_container as SubViewportContainer # References the editor-authored container that displays the isolated inspection world.
@onready var _sub_viewport: SubViewport = $stage/viewport_container/sub_viewport as SubViewport # References the isolated 3D viewport used only for sticker inspection.
@onready var _sticker_root: Node3D = $stage/viewport_container/sub_viewport/sticker_root as Node3D # References the temporary pivot that receives free inspection rotation.
@onready var _sticker_mesh: StickerMesh = $stage/viewport_container/sub_viewport/sticker_root/sticker_mesh as StickerMesh # References the same artwork-defined sticker mesh system used by the physical book.
@onready var _camera: Camera3D = $stage/viewport_container/sub_viewport/camera as Camera3D # References the orthographic inspection camera that keeps the presentation visually flat while allowing true 3D rotation.
@onready var _title: Label = $top_bar/content/title as Label # References the selected sticker name displayed above the inspection stage.
@onready var _zoom_label: Label = $bottom_bar/zoom_label as Label # References the compact current zoom readout.
@onready var _zoom_out_button: Button = $bottom_bar/zoom_out as Button # References the editor-authored control that decreases inspection zoom.
@onready var _reset_button: Button = $bottom_bar/reset as Button # References the editor-authored control that restores canonical orientation and zoom.
@onready var _zoom_in_button: Button = $bottom_bar/zoom_in as Button # References the editor-authored control that increases inspection zoom.
@onready var _close_button: Button = $top_bar/content/close as Button # References the editor-authored control that closes the modal inspection surface.

var _sticker_size: Vector2 = Vector2.ONE # Stores the source artwork's physical dimensions without changing book placement state.
var _zoom: float = 1.0 # Stores the current temporary inspection magnification.
var _base_camera_size: float = 4.0 # Stores the orthographic size required to contain the sticker through every possible 3D orientation.
var _rotation_mode: int = ROTATION_NONE # Stores which temporary inspection rotation gesture currently owns pointer motion.
var _orientation: Quaternion = Quaternion.IDENTITY # Stores the complete temporary pitch-yaw-roll orientation without Euler-angle limitations.
var _last_arcball_vector: Vector3 = Vector3.BACK # Stores the previous virtual-trackball direction in world space for incremental shortest-arc rotation.

func open_inspection(sticker_texture: Texture2D, display_name: String, sticker_size: Vector2) -> void: # Opens a fully rotatable isolated 3D copy without modifying the sticker stored in the book.
	_sticker_size = Vector2(maxf(sticker_size.x, 0.001), maxf(sticker_size.y, 0.001)) # Normalizes source dimensions before procedural mesh construction and camera fitting.
	_title.text = display_name # Shows the selected sticker identity independently from persistence data.
	_zoom = 1.0 # Starts each inspection at the canonical magnification.
	_rotation_mode = ROTATION_NONE # Clears any interrupted pointer gesture left by a previous inspection session.
	_orientation = Quaternion.IDENTITY # Starts the temporary inspection copy at its original artwork orientation.
	_sticker_mesh.configure(_sticker_size, sticker_texture) # Builds the exact artwork-defined front-and-adhesive-back 3D sheet used for inspection.
	_sticker_mesh.clear_peel() # Ensures the inspection copy starts completely flat rather than inheriting any conceptual peel deformation.
	_sticker_mesh.clear_turnover() # Ensures the mesh-local turnover transform is reset before the inspection pivot controls orientation.
	_apply_orientation() # Applies the canonical temporary quaternion to the isolated sticker pivot.
	_sub_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS # Renders the isolated physical preview only while its modal is open.
	visible = true # Gives the inspection modal full presentation and input ownership above the unchanged book.
	_update_camera_fit() # Fits the full possible rotation envelope inside the current inspection stage.
	_refresh_zoom_label() # Synchronizes the toolbar readout with the reset zoom.
	_close_button.grab_focus.call_deferred() # Provides deterministic keyboard/controller focus without using signals.

func close_inspection() -> void: # Closes the modal without writing temporary orientation or zoom into the book save.
	_rotation_mode = ROTATION_NONE # Releases any active virtual-trackball or roll gesture before hiding the modal.
	_sub_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED # Stops hidden inspection rendering and shader work.
	visible = false # Returns presentation and input ownership to the unchanged underlying book.

func is_open() -> bool: # Reports whether the inspection modal currently owns the player input surface.
	return visible # Uses modal visibility as the single authoritative inspection-open state.

func configure_actions() -> void: # Binds native toolbar controls without intercepting their pointer events.
	(_close_button as GameButton).bind_action(close_and_restore_focus) # Closes through the owning shell to restore the selected card.
	(_zoom_out_button as GameButton).bind_action(_change_zoom.bind(false)) # Uses native activation for zooming out.
	(_zoom_in_button as GameButton).bind_action(_change_zoom.bind(true)) # Uses native activation for zooming in.
	(_reset_button as GameButton).bind_action(_reset_transform) # Restores the original artwork orientation and fit.

func close_and_restore_focus() -> void: # Routes toolbar close through the modal owner.
	(get_parent() as GameUI).close_inspection() # Restores the exact collection card or book action that opened this modal.

func _change_zoom(zoom_in: bool) -> void: # Applies one toolbar zoom step through the clamped camera path.
	_set_zoom(_zoom * ZOOM_STEP if zoom_in else _zoom / ZOOM_STEP) # Preserves consistent wheel and toolbar zoom increments.

func handle_input(event: InputEvent) -> bool: # Handles only inspection gestures while native buttons retain normal GUI input.
	if not visible: # Rejects input when the modal is closed.
		return false # Leaves the current destination in control.
	if event is InputEventKey and event.is_pressed() and not event.is_echo(): # Handles only deliberate inspection shortcuts.
		match (event as InputEventKey).keycode: # Keeps text-entry and native button keys outside this handler.
			KEY_R: # Recognizes the reset-view shortcut.
				_reset_transform() # Restores the initial orientation and zoom.
				return true # Consumes only the reset shortcut.
			KEY_Q: # Recognizes keyboard roll to the left.
				_apply_roll(-0.12) # Rotates about the current camera-facing axis.
				return true # Consumes the handled roll shortcut.
			KEY_E: # Recognizes keyboard roll to the right.
				_apply_roll(0.12) # Rotates about the current camera-facing axis.
				return true # Consumes the handled roll shortcut.
	if event is InputEventMouseButton: # Routes only stage-owned mouse gestures.
		var mouse: InputEventMouseButton = event as InputEventMouseButton # Narrows the pointer event.
		var over_stage: bool = _stage.get_global_rect().has_point(mouse.position) # Keeps toolbar input outside the physical gesture surface.
		if over_stage and mouse.pressed and mouse.button_index == MOUSE_BUTTON_WHEEL_UP: # Handles wheel zoom inside the artwork stage.
			_set_zoom(_zoom * ZOOM_STEP) # Increases the clamped orthographic zoom.
			return true # Consumes this stage-owned wheel event.
		if over_stage and mouse.pressed and mouse.button_index == MOUSE_BUTTON_WHEEL_DOWN: # Handles wheel zoom away from the artwork.
			_set_zoom(_zoom / ZOOM_STEP) # Decreases the clamped orthographic zoom.
			return true # Consumes this stage-owned wheel event.
		if mouse.button_index == MOUSE_BUTTON_LEFT or mouse.button_index == MOUSE_BUTTON_RIGHT: # Restricts rotation to the supported drag buttons.
			if mouse.pressed and over_stage: # Begins rotation only inside the inspection stage.
				_rotation_mode = ROTATION_ARCBALL if mouse.button_index == MOUSE_BUTTON_LEFT else ROTATION_ROLL # Selects unrestricted trackball or deliberate roll interaction.
				_last_arcball_vector = _map_to_arcball_world(mouse.position) # Anchors rotation at the actual pointer position.
				return true # Reserves this press for the inspection gesture.
			if not mouse.pressed and _rotation_mode != ROTATION_NONE: # Completes an existing drag even outside the stage.
				_rotation_mode = ROTATION_NONE # Releases the gesture without touching saved book orientation.
				return true # Prevents the same release from activating a toolbar button.
	if event is InputEventMouseMotion and _rotation_mode != ROTATION_NONE: # Updates only an active inspection drag.
		var motion: InputEventMouseMotion = event as InputEventMouseMotion # Reads the current pointer movement.
		if _rotation_mode == ROTATION_ARCBALL: # Applies unrestricted rotation across all axes.
			var current: Vector3 = _map_to_arcball_world(motion.position) # Maps the pointer onto the virtual trackball.
			_orientation = (Quaternion(_last_arcball_vector, current) * _orientation).normalized() # Accumulates a stable quaternion without Euler locking.
			_last_arcball_vector = current # Advances the drag anchor for the next movement.
			_apply_orientation() # Updates only the temporary inspection mesh.
		else: # Handles deliberate camera-facing roll.
			_apply_roll(-motion.relative.x * ROLL_RADIANS_PER_PIXEL) # Applies roll proportional to pointer movement.
		return true # Consumes the active stage gesture.
	return false # Allows native buttons, focus, and hover feedback to process normally.


func _set_zoom(new_zoom: float) -> void: # Applies bounded orthographic magnification without resizing source artwork or book geometry.
	_zoom = clampf(new_zoom, MIN_ZOOM, MAX_ZOOM) # Keeps close inspection useful without permitting unstable or unusable camera sizes.
	_apply_camera_zoom() # Converts the magnification into the isolated orthographic camera's view size.
	_refresh_zoom_label() # Keeps the compact zoom readout synchronized with wheel and button adjustments.

func _reset_transform() -> void: # Restores the inspection-only transform to the sticker's canonical source presentation.
	_zoom = 1.0 # Restores default one-times inspection magnification.
	_orientation = Quaternion.IDENTITY # Removes every temporary pitch, yaw, and roll component at once.
	_rotation_mode = ROTATION_NONE # Releases any gesture that may have been in progress before reset.
	_apply_orientation() # Writes the canonical quaternion to the isolated sticker pivot.
	_apply_camera_zoom() # Restores the canonical orthographic framing without changing sticker dimensions.
	_refresh_zoom_label() # Updates the toolbar readout after the reset.

func _apply_orientation() -> void: # Applies the current normalized inspection quaternion to the isolated 3D sticker pivot.
	_sticker_root.transform = Transform3D(Basis(_orientation), Vector3.ZERO) # Replaces only temporary inspection rotation while keeping the sticker centered in its private world.

func _apply_roll(angle: float) -> void: # Applies unrestricted rotation around the camera-facing axis for deliberate roll control.
	var camera_axis: Vector3 = (_camera.global_transform.basis * Vector3.BACK).normalized() # Converts the camera's local backward axis into the world-space axis pointing from sticker toward viewer.
	var delta_rotation: Quaternion = Quaternion(camera_axis, angle) # Builds one normalized axis-angle roll quaternion around the current screen normal.
	_orientation = (delta_rotation * _orientation).normalized() # Applies the roll in world space while preserving all existing pitch and yaw components.
	_apply_orientation() # Writes the resulting complete three-axis orientation to the temporary sticker pivot.

func _map_to_arcball_world(global_pointer: Vector2) -> Vector3: # Maps a screen pointer onto a virtual sphere and converts that sphere direction into inspection-world coordinates.
	var stage_rect: Rect2 = _stage.get_global_rect() # Reads the actual responsive stage rectangle used by the modal on the current window size.
	var center: Vector2 = stage_rect.position + stage_rect.size * 0.5 # Finds the center of the virtual rotation sphere in global screen coordinates.
	var radius: float = maxf(minf(stage_rect.size.x, stage_rect.size.y) * 0.5, 1.0) # Uses the shorter stage dimension so the virtual trackball remains circular rather than stretched.
	var sphere_x: float = (global_pointer.x - center.x) / radius # Converts horizontal pointer offset into normalized virtual-sphere coordinates.
	var sphere_y: float = (center.y - global_pointer.y) / radius # Converts vertical pointer offset into normalized sphere coordinates with positive Y upward.
	var radial_squared: float = sphere_x * sphere_x + sphere_y * sphere_y # Measures whether the pointer lies inside or outside the projected unit sphere.
	var sphere_z: float = 0.0 # Seeds the depth component used by the virtual sphere surface.
	if radial_squared <= 1.0: # Handles pointer positions inside the sphere's projected circular boundary.
		sphere_z = sqrt(maxf(1.0 - radial_squared, 0.0)) # Lifts the point onto the front hemisphere so drag direction produces natural pitch, yaw, and roll composition.
	else: # Handles pointer positions outside the projected sphere without creating invalid square roots.
		var inverse_radius: float = 1.0 / sqrt(radial_squared) # Calculates the scale needed to clamp the pointer to the sphere's equator.
		sphere_x *= inverse_radius # Clamps horizontal sphere position to the unit circle.
		sphere_y *= inverse_radius # Clamps vertical sphere position to the unit circle.
	var camera_space_vector: Vector3 = Vector3(sphere_x, sphere_y, sphere_z).normalized() # Builds a normalized sphere direction where positive Z points back toward the viewer.
	return (_camera.global_transform.basis * camera_space_vector).normalized() # Converts the camera-relative sphere direction into world space for stable shortest-arc quaternion composition.

func _refresh_zoom_label() -> void: # Formats the current zoom as a compact multiplier for the inspection toolbar.
	_zoom_out_button.disabled = _zoom <= MIN_ZOOM # Communicates the lower zoom limit through native disabled state.
	_zoom_in_button.disabled = _zoom >= MAX_ZOOM # Communicates the upper zoom limit through native disabled state.
	_zoom_label.text = "%.2fx" % _zoom # Shows precise magnification feedback without cluttering the inspection canvas.

func _update_camera_fit() -> void: # Fits the complete sticker rotation envelope inside the responsive orthographic inspection viewport.
	if not is_node_ready(): # Protects construction frames before the editor-authored viewport and camera exist.
		return # Defers fitting until the scene tree has completed ready initialization.
	var physical_size: Vector2 = _sticker_mesh.get_physical_size() # Uses the exact artwork-defined bounds so inspection framing contains every legal sharp corner.
	var rotation_diameter: float = maxf(physical_size.length(), 0.001) * CAMERA_PADDING # Uses the sheet diagonal because no rotated projection can exceed that complete envelope.
	var stage_height: float = maxf(_stage.size.y, 1.0) # Protects responsive framing calculations from zero-height resize frames.
	var stage_aspect: float = maxf(_stage.size.x / stage_height, 0.001) # Calculates the visible orthographic width-to-height ratio of the inspection stage.
	_base_camera_size = maxf(rotation_diameter, rotation_diameter / stage_aspect) # Ensures the same diagonal envelope fits both the vertical and horizontal camera dimensions.
	_apply_camera_zoom() # Applies current magnification after every fit or window-size recalculation.

func _apply_camera_zoom() -> void: # Converts the current inspection magnification into an orthographic camera size.
	_camera.size = _base_camera_size / maxf(_zoom, 0.001) # Shrinks orthographic world coverage as zoom increases while leaving the physical sticker mesh unchanged.

func _notification(what: int) -> void: # Responds to responsive Control resize notifications without signal connections.
	if what == NOTIFICATION_RESIZED and visible: # Recalculates only when an open modal actually changes usable screen dimensions.
		_update_camera_fit() # Refits the complete 3D rotation envelope while preserving temporary orientation and zoom.
