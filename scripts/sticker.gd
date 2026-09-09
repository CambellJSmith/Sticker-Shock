class_name Sticker
extends Area3D

enum InteractionState { RESTING, PEELING, CARRIED, RETURNING, LANDING } # Defines the mutually exclusive physical interaction phases used by one sticker.

const RETURN_DURATION: float = 0.20 # Controls how quickly an incomplete peel relaxes only after the button is released.
const TURNOVER_DURATION: float = 0.22 # Controls how quickly a fully peeled sticker turns from adhesive-side-up to printed-face-up while carried.
const LANDING_LIFT_DURATION: float = 0.10 # Controls the short upward hop that begins when a detached sticker is released.
const LANDING_SLAM_DURATION: float = 0.16 # Controls the accelerated downward part of the release that slams the sticker flat onto the page.
const LANDING_BOUNCE_HEIGHT: float = 0.16 # Controls the extra airborne height added above the normal carried height before the slam.
const CARRY_HEIGHT: float = StickerMesh.PEEL_CURL_WIDTH * 2.0 / PI # Defines the maximum carried height produced when the peel has reached its full curl radius.

var _sticker_size: Vector2 = Vector2.ONE # Stores the complete artwork-defined physical dimensions used for interaction and full-peel calculations.
var _visual: StickerMesh # Stores the deformable rendered surface owned by this sticker.
var _contact_shadow: StickerContactShadow # Stores the lightweight resting silhouette that gives the flat sticker a small physical contact shadow.
var _collision_shape: CollisionShape3D # Stores the lightweight flat picking volume used while the visual mesh curls.
var _landing_preview: StickerLandingPreview # Stores the independent flat silhouette that marks the exact carried sticker landing transform.
var _state: int = InteractionState.RESTING # Stores the current physical interaction phase without overlapping boolean states.
var _grab_local: Vector2 = Vector2.ZERO # Stores the local material point selected when the drag started.
var _drag_start_world: Vector3 = Vector3.ZERO # Stores the page-plane pointer position where the current drag began.
var _drag_origin_transform: Transform3D = Transform3D.IDENTITY # Stores the sticker transform before the current peel starts.
var _current_local_drag: Vector2 = Vector2.ZERO # Stores the current local peel displacement while material remains attached.
var _rest_height: float = 0.0 # Stores the page-stack height where this sticker must finish every attachment animation.
var _carry_height: float = CARRY_HEIGHT # Stores the actual curl diameter present on the exact frame the sticker loses its final page contact.
var _carry_fold_axis_local: Vector2 = Vector2.RIGHT # Stores the in-plane axis used to turn the fully detached sheet back to its printed face.
var _turnover_elapsed: float = 0.0 # Stores elapsed turnover time while the detached sticker is being carried.
var _turnover_angle: float = 0.0 # Stores the current physical turnover angle for interruption-safe landing.
var _return_elapsed: float = 0.0 # Stores elapsed time for an incomplete peel returning to the page.
var _return_start_drag: Vector2 = Vector2.ZERO # Stores the peel deformation present at the moment an incomplete drag is released.
var _landing_elapsed: float = 0.0 # Stores elapsed time for the airborne release-and-slam animation.
var _landing_start_position: Vector3 = Vector3.ZERO # Stores the carried root position at the moment the button is released.
var _landing_target_position: Vector3 = Vector3.ZERO # Stores the exact flat attached position directly under the release point.
var _landing_peak_height: float = 0.0 # Stores the apex reached by the little upward release bounce.
var _landing_start_turnover_angle: float = 0.0 # Stores any remaining turnover angle so release can always finish printed-face-up.

func configure(sticker_size: Vector2, sticker_texture: Texture2D) -> void: # Composes the visible mesh and flat interaction volume for one sticker.
	_visual = StickerMesh.new() # Creates the dedicated GPU-deformed visual component.
	_visual.name = "visual" # Gives the visual component a clear editor/runtime tree name.
	add_child(_visual) # Parents the visual component to the interactive sticker root.
	_visual.configure(sticker_size, sticker_texture) # Builds the tessellated surface and binds the supplied artwork as the complete sticker shape.
	_sticker_size = _visual.get_physical_size() # Uses the artwork dimensions for picking and exact full-peel calculations.
	_contact_shadow = StickerContactShadow.new() # Creates the separate cheap contact-shadow component used only while the sticker is flat.
	_contact_shadow.name = "contact_shadow" # Gives the helper a clear runtime tree name for inspection and profiling.
	add_child(_contact_shadow) # Parents the contact shadow to the sticker root so it follows persistent placement and stack movement automatically.
	_contact_shadow.configure(_sticker_size, sticker_texture) # Builds the small softened artwork-alpha shadow beneath the resting sticker.
	_landing_preview = StickerLandingPreview.new() # Creates the dedicated landing-outline component without coupling preview rendering into the peel mesh.
	_landing_preview.name = "landing_preview" # Gives the landing helper a clear runtime tree name.
	add_child(_landing_preview) # Keeps the preview lifecycle owned by this sticker while its top-level transform remains independent.
	_landing_preview.configure(_visual.mesh, sticker_texture) # Reuses the source geometry and artwork alpha so the outline follows the supplied sticker silhouette exactly.
	_collision_shape = CollisionShape3D.new() # Creates the collision component used only for pointer ray picking.
	_collision_shape.name = "pick_shape" # Gives the picking component a clear editor/runtime tree name.
	var box: BoxShape3D = BoxShape3D.new() # Creates a thin rectangular interaction volume matching the sticker bounds.
	box.size = Vector3(_sticker_size.x, 0.04, _sticker_size.y) # Sizes the picking volume to the artwork bounds without following expensive peel deformation.
	_collision_shape.shape = box # Assigns the configured interaction shape to the collision node.
	_collision_shape.position.y = 0.01 # Centers the thin picking volume just above the page-facing mesh.
	add_child(_collision_shape) # Parents the picking component to the sticker root.
	collision_layer = 1 # Places stickers on the dedicated pointer-picking collision layer.
	collision_mask = 0 # Prevents sticker areas from performing unnecessary overlap checks against other physics objects.
	monitoring = false # Disables continuous overlap monitoring because pointer selection uses explicit ray queries instead.
	monitorable = true # Keeps the area available to explicit physics queries from the main controller.
	input_ray_pickable = true # Keeps the Area3D eligible for ray-based pointer selection.
	_rest_height = global_position.y # Captures the initial page-stack height after the sticker has been placed.

func can_begin_drag() -> bool: # Exposes whether this sticker is physically settled enough to accept a new grab.
	return _state == InteractionState.RESTING # Prevents a second grab from interrupting an autonomous return or slam animation.

func begin_drag(page_world_point: Vector3) -> void: # Captures the clicked material point and establishes a stable reference transform for the peel.
	if not can_begin_drag(): # Rejects grabs while the sticker is still autonomously attaching to the page.
		return # Leaves the current physical animation untouched until it is complete.
	_state = InteractionState.PEELING # Starts the attached peel phase for the new pointer gesture.
	_drag_start_world = page_world_point # Stores the pointer location on the page plane at grab time.
	_drag_origin_transform = global_transform # Stores the complete root transform before any peel-driven visual changes occur.
	var grab_point_local: Vector3 = _drag_origin_transform.affine_inverse() * page_world_point # Converts the clicked world point into undeformed sticker-local material space.
	_grab_local = Vector2(grab_point_local.x, grab_point_local.z) # Stores only the sticker-plane axes used by the curl shader.
	_current_local_drag = Vector2.ZERO # Starts the new peel from a completely flat material state.
	_turnover_elapsed = 0.0 # Clears any stale turnover timing from a previous completed gesture.
	_turnover_angle = 0.0 # Starts the attached peel without any whole-sheet rotation.
	_visual.clear_turnover() # Guarantees that a resting sticker starts every peel printed-face-up and unrotated.
	_landing_preview.hide_preview() # Keeps the landing marker hidden until the sticker has actually become a free carried sheet.
	_visual.set_peel(_grab_local, Vector2.ZERO) # Sends the exact click point to the shader before the cursor starts moving.
	_contact_shadow.set_peel(_grab_local, Vector2.ZERO) # Keeps the full contact shadow visible until actual peel displacement begins.

func update_drag(page_world_point: Vector3) -> void: # Converts pointer motion into attached curl deformation or irreversible detached carrying.
	if _state == InteractionState.CARRIED: # Keeps a fully detached sticker following the pointer without ever reattaching during the same button hold.
		_update_carry_position(page_world_point) # Moves the printed-face-up carried sheet so the grabbed material point stays under the cursor.
		return # Skips all original-position peel logic once complete detachment has occurred.
	if _state != InteractionState.PEELING: # Rejects pointer updates outside the two active drag phases.
		return # Leaves resting and autonomous attachment animations untouched.
	var world_delta: Vector3 = page_world_point - _drag_start_world # Measures pointer displacement over the physical page plane.
	var local_delta_3d: Vector3 = _drag_origin_transform.basis.inverse() * world_delta # Converts the pointer displacement into the sticker's original local orientation.
	var local_drag: Vector2 = Vector2(local_delta_3d.x, local_delta_3d.z) # Stores the current 2D material displacement used by the peel shader.
	var drag_distance: float = local_drag.length() # Measures how far the grabbed point has moved across the page plane.
	if drag_distance <= 0.0001: # Avoids unstable direction calculations when the pointer is effectively still at the grab point.
		_current_local_drag = Vector2.ZERO # Keeps the material exactly flat while no meaningful drag direction exists.
		_visual.set_peel(_grab_local, _current_local_drag) # Preserves the clicked material point while keeping the shader on its flat path.
		_contact_shadow.set_peel(_grab_local, _current_local_drag) # Keeps the complete contact shadow while no material has actually lifted.
		return # Waits for a meaningful drag before calculating the full-peel boundary.
	var peel_direction: Vector2 = local_drag / drag_distance # Defines the current direction in which the sticker is being peeled.
	var active_curl_width: float = minf(StickerMesh.PEEL_CURL_WIDTH, maxf(drag_distance * StickerMesh.PEEL_CURL_GROWTH, 0.002)) # Reproduces the shader's current bend width exactly so CPU contact logic and rendered geometry share one moving fold.
	if not _has_lost_all_page_contact(peel_direction, drag_distance, active_curl_width): # Keeps the sticker attached only while some visible artwork material remains on the unpeeled side of the fold.
		_current_local_drag = local_drag # Lets the shader use the complete pointer displacement during the attached peel.
		global_transform = _drag_origin_transform # Holds the physical root at its original attachment location while real sticker material still touches the page.
		_visual.set_peel(_grab_local, _current_local_drag) # Updates the GPU curl from the exact clicked point and current drag vector.
		_contact_shadow.set_peel(_grab_local, _current_local_drag) # Removes contact shadow only from material that has crossed onto the lifted side of the same fold.
		return # Waits only until the fold crosses the final visible material point, with no extra curl-clearance distance.
	_begin_carry(page_world_point, peel_direction, active_curl_width) # Detaches on the first frame with zero unpeeled material and immediately begins the free-sheet turnover.

func end_drag() -> bool: # Releases the pointer and starts either incomplete-peel return or detached bounce-and-slam attachment.
	if _state == InteractionState.PEELING: # Handles a sticker released before the fold cleared the complete sheet.
		_state = InteractionState.RETURNING # Starts autonomous reattachment only now that the mouse button has actually been released.
		_return_elapsed = 0.0 # Restarts the return timing from the exact release frame.
		_return_start_drag = _current_local_drag # Stores the current curl so it can relax continuously back to flat.
		return false # Reports that the sticker never detached and therefore did not change placement.
	if _state == InteractionState.CARRIED: # Handles a fully detached sticker released at its new pointer position.
		_landing_preview.hide_preview() # Removes the placement guide at button release because the landing target is now committed.
		_state = InteractionState.LANDING # Starts the requested upward hop followed by a hard flat slam onto the page.
		_landing_elapsed = 0.0 # Restarts landing timing from the exact button-release frame.
		_landing_start_position = global_position # Stores the current carried position so the bounce starts without any discontinuity.
		_landing_target_position = global_position # Copies the release position so horizontal placement never drifts during landing.
		_landing_target_position.y = _rest_height # Places the final root exactly back on its current paper-stack attachment height.
		_landing_peak_height = maxf(_landing_start_position.y, _rest_height + CARRY_HEIGHT) + LANDING_BOUNCE_HEIGHT # Raises the sticker a little above its normal carried height before the downward slam.
		_landing_start_turnover_angle = _turnover_angle # Preserves any unfinished flip so fast releases still land printed-face-up.
		return true # Reports that the fully detached sticker has committed to a new placement.
	return false # Rejects releases that do not belong to an active pointer drag.

func set_stack_height(world_y: float) -> void: # Places this sticker slightly above older stickers so overlap behaves like real layered paper.
	_rest_height = world_y # Stores the exact attachment height this sticker must return to after future carrying and landing.
	var current_position: Vector3 = global_position # Reads the current world position without disturbing horizontal placement.
	current_position.y = world_y # Replaces only the vertical stacking coordinate.
	global_position = current_position # Applies the requested physical layer height to the whole sticker.

func begin_new_sticker_landing(world_xz: Vector2, landing_height: float) -> void: # Starts a newly won sticker above its chosen page location and performs the same little bounce followed by a hard flat slam.
	_rest_height = landing_height # Stores the exact persistent paper-stack height this new physical copy will occupy after impact.
	_state = InteractionState.LANDING # Places the new sticker directly into the autonomous release-and-slam phase without requiring a peel gesture first.
	_contact_shadow.hide_shadow() # Keeps the synthetic contact shadow absent while the newly placed sticker is still visibly airborne.
	_landing_elapsed = 0.0 # Starts the complete landing animation from its first frame.
	_landing_target_position = Vector3(world_xz.x, landing_height, world_xz.y) # Stores the exact final flat x/z placement and physical stack height.
	_landing_start_position = Vector3(world_xz.x, landing_height + CARRY_HEIGHT * 0.72, world_xz.y) # Starts the won sticker visibly above the page as if the player has just let it go.
	global_position = _landing_start_position # Applies the airborne starting transform before the next process frame advances the bounce.
	_landing_peak_height = _landing_start_position.y + LANDING_BOUNCE_HEIGHT # Gives the new placement the same short upward kick before its hard downward attachment.
	_landing_start_turnover_angle = 0.0 # Keeps a newly won sticker printed-face-up throughout the placement because it was never peeled adhesive-side-up.
	_turnover_angle = 0.0 # Clears any whole-sheet turnover state before the autonomous landing begins.
	_visual.clear_peel() # Guarantees the new physical copy begins as a flat sheet rather than inheriting any shader deformation.
	_visual.clear_turnover() # Guarantees the printed face remains in its normal flat orientation during the bounce and slam.
	_landing_preview.hide_preview() # Removes any internal carried-sticker landing guide because manual placement already supplied its own preview.

func is_dragging() -> bool: # Exposes read-only gesture ownership to the main controller without exposing internal state fields.
	return _state == InteractionState.PEELING or _state == InteractionState.CARRIED # Returns whether the pointer is currently manipulating this sticker.

func is_settling() -> bool: # Exposes whether the sticker is still autonomously attaching after release.
	return _state == InteractionState.RETURNING or _state == InteractionState.LANDING # Returns whether the sticker is returning from a partial peel or performing the bounce-and-slam landing.

func is_carried() -> bool: # Exposes whether a complete peel has irreversibly detached this sticker during the current drag.
	return _state == InteractionState.CARRIED # Returns whether the sticker is following the pointer as a free printed-face-up sheet.

func _process(delta: float) -> void: # Advances only the lightweight turnover and attachment animations required by the current physical state.
	if _state == InteractionState.CARRIED: # Advances the adhesive-side-to-front turnover while the player continues holding the sticker.
		_process_turnover(delta) # Rotates the free sheet around the exact grabbed point until its printed face is upward.
	elif _state == InteractionState.RETURNING: # Advances an incomplete peel only after the player releases the mouse button.
		_process_return(delta) # Relaxes the curl back onto the original page position without whole-sheet relocation.
	elif _state == InteractionState.LANDING: # Advances the detached release bounce and accelerated flat slam.
		_process_landing(delta) # Moves the carried sticker upward briefly and then drives it hard down to its new attached position.

func _begin_carry(page_world_point: Vector3, peel_direction: Vector2, active_curl_width: float) -> void: # Converts the just-detached shader peel into a free sheet on the exact frame the final page contact disappears.
	_state = InteractionState.CARRIED # Locks the sticker into detached behaviour for the remainder of this button hold.
	_contact_shadow.hide_shadow() # Removes the final contact-shadow remnants exactly when no visible sticker material remains attached to the page.
	_carry_fold_axis_local = Vector2(-peel_direction.y, peel_direction.x).normalized() # Stores the exact fold axis around which the fully peeled reverse-facing sheet must turn over.
	_turnover_elapsed = 0.0 # Starts the physical turnover at the first detached frame.
	_turnover_angle = PI # Represents the newly detached sheet as a flat adhesive-side-up surface before it turns over.
	_carry_height = active_curl_width * 2.0 / PI # Matches the shader's actual curl diameter at detachment so edge grabs do not jump upward to the maximum curl height.
	_current_local_drag = Vector2.ZERO # Clears the attached shader displacement because the free sheet is now represented by its child transform.
	_visual.clear_peel() # Removes the curl only after the entire mesh has passed through it.
	_update_carry_position(page_world_point) # Moves the free sticker root so the originally grabbed material point remains exactly under the pointer.
	_visual.set_turnover(_grab_local, _carry_fold_axis_local, _turnover_angle) # Reconstructs the completed back-facing peel as a flat sheet with no visible positional jump.

func _update_carry_position(page_world_point: Vector3) -> void: # Keeps a fully detached sticker under the pointer without attraction to its original attachment point.
	var grab_offset_world: Vector3 = _drag_origin_transform.basis * Vector3(_grab_local.x, 0.0, _grab_local.y) # Converts the grabbed material-point offset into the sticker's preserved world orientation.
	var target_position: Vector3 = page_world_point - grab_offset_world # Places the sticker center so the same local material point remains directly beneath the pointer.
	target_position.y = _rest_height + _carry_height # Holds the detached sheet at the exact height produced by the curl on the frame the final material point leaves the page.
	global_position = target_position # Applies only cursor-following movement with no spring or tendency toward the original position.
	_landing_preview.show_at(global_basis, global_position, _rest_height) # Projects the exact final flat transform onto the page as a faint alpha-silhouette outline.

func _has_lost_all_page_contact(peel_direction: Vector2, drag_distance: float, active_curl_width: float) -> bool: # Detects the exact frame when no visible sticker material remains on the page-facing side of the moving fold.
	var grab_projection: float = _grab_local.dot(peel_direction) # Projects the grabbed material point onto the current peel direction exactly as the vertex shader does.
	var fold_projection: float = grab_projection + (drag_distance + active_curl_width) * 0.5 # Recreates the shader's moving fold position with no extra detachment threshold or safety margin.
	var maximum_material_projection: float = _visual.get_maximum_material_projection(peel_direction) # Finds the real source-alpha edge farthest ahead of the fold rather than using transparent mesh corners.
	return fold_projection > maximum_material_projection # Detaches on the first frame the fold has crossed the final visible material point, meaning literally nothing remains unpeeled.

func _process_turnover(delta: float) -> void: # Turns the fully peeled adhesive-side-up sheet back over while the grabbed material point remains fixed.
	_turnover_elapsed += delta # Advances turnover time independently of pointer motion so holding the mouse still still completes the flip.
	var linear_progress: float = clampf(_turnover_elapsed / TURNOVER_DURATION, 0.0, 1.0) # Normalizes turnover time into a stable zero-to-one range.
	var eased_progress: float = 1.0 - pow(1.0 - linear_progress, 3.0) # Uses a cubic ease-out so the turn begins decisively and settles naturally into the front-facing carry pose.
	_turnover_angle = lerpf(PI, 0.0, eased_progress) # Rotates from the completed adhesive-side-up peel pose to the normal printed-face-up pose.
	if linear_progress >= 1.0: # Finalizes the free-sheet orientation once the turnover is complete.
		_turnover_angle = 0.0 # Stores the exact front-facing orientation without accumulated interpolation error.
		_visual.clear_turnover() # Returns the child transform to identity for the cheapest possible long-duration carry state.
	else: # Preserves the pivoted transform only while the turnover remains visibly in progress.
		_visual.set_turnover(_grab_local, _carry_fold_axis_local, _turnover_angle) # Updates the physical flip around the exact material point held by the player.

func _process_return(delta: float) -> void: # Relaxes an incomplete peel back onto its unchanged original position after release.
	_return_elapsed += delta # Advances the reattachment time only after the mouse button has been released.
	var linear_progress: float = clampf(_return_elapsed / RETURN_DURATION, 0.0, 1.0) # Normalizes the short return animation into a stable zero-to-one range.
	var eased_progress: float = 1.0 - pow(1.0 - linear_progress, 3.0) # Applies cubic ease-out so the released paper initially snaps back then finishes gently.
	_current_local_drag = _return_start_drag.lerp(Vector2.ZERO, eased_progress) # Reduces the shader deformation continuously toward the original flat attached material state.
	_visual.set_peel(_grab_local, _current_local_drag) # Sends the current return pose to the GPU without rebuilding any mesh data.
	_contact_shadow.set_peel(_grab_local, _current_local_drag) # Expands the contact shadow back across the same material area as the curl relaxes onto the page.
	if linear_progress >= 1.0: # Finalizes the original attachment once all curl deformation has disappeared.
		_current_local_drag = Vector2.ZERO # Clears the completed partial-peel displacement for the next interaction.
		_visual.clear_peel() # Returns the shader exactly to its undeformed fast path.
		_visual.clear_turnover() # Guarantees the printed face is in its normal resting orientation.
		_landing_preview.hide_preview() # Guarantees an incomplete peel never leaves a stale landing marker behind.
		global_transform = _drag_origin_transform # Restores the exact transform present before the incomplete peel began.
		_rest_height = global_position.y # Preserves the current stack layer as the attachment height after the exact transform restoration.
		_contact_shadow.show_shadow() # Restores the complete small contact shadow after the sticker is fully flat on its original attachment.
		_state = InteractionState.RESTING # Makes the fully reattached sticker available for another click.

func _process_landing(delta: float) -> void: # Performs the requested little upward bounce followed by an accelerating slam flat onto the new page position.
	_landing_elapsed += delta # Advances the release animation from the button-up frame.
	var total_duration: float = LANDING_LIFT_DURATION + LANDING_SLAM_DURATION # Combines the two landing phases for turnover completion and final-state checks.
	var current_position: Vector3 = _landing_start_position # Starts from the exact horizontal release position on every frame.
	if _landing_elapsed < LANDING_LIFT_DURATION: # Handles the small upward bounce immediately after the player lets go.
		var lift_progress: float = clampf(_landing_elapsed / LANDING_LIFT_DURATION, 0.0, 1.0) # Normalizes only the upward phase.
		var lift_eased: float = 1.0 - pow(1.0 - lift_progress, 2.0) # Gives the upward hop a quick launch that slows naturally as it reaches the apex.
		current_position.y = lerpf(_landing_start_position.y, _landing_peak_height, lift_eased) # Raises the whole free sticker a short distance farther into the air.
	else: # Handles the hard downward attachment after the bounce reaches its apex.
		var slam_elapsed: float = _landing_elapsed - LANDING_LIFT_DURATION # Measures time since the downward slam phase began.
		var slam_progress: float = clampf(slam_elapsed / LANDING_SLAM_DURATION, 0.0, 1.0) # Normalizes only the downward phase.
		var slam_eased: float = pow(slam_progress, 3.0) # Accelerates strongly toward the page so the final contact reads as a decisive slam rather than a soft float.
		current_position.y = lerpf(_landing_peak_height, _landing_target_position.y, slam_eased) # Drives the sticker down to the exact paper-stack height while preserving release-position placement.
	global_position = current_position # Applies the current airborne or downward position without any attraction toward the sticker's old location.
	var turnover_progress: float = clampf(_landing_elapsed / total_duration, 0.0, 1.0) # Uses the complete release animation to finish any turnover that was interrupted by a fast mouse release.
	var turnover_eased: float = 1.0 - pow(1.0 - turnover_progress, 3.0) # Finishes orientation early enough that the printed face is visually flat before the final page impact.
	_turnover_angle = lerpf(_landing_start_turnover_angle, 0.0, turnover_eased) # Rotates any remaining adhesive-side exposure toward the printed-face-up landing orientation.
	if _turnover_angle > 0.0001: # Keeps the grabbed-point pivot transform only while a visible amount of turnover remains.
		_visual.set_turnover(_grab_local, _carry_fold_axis_local, _turnover_angle) # Completes the physical turn while the sticker is airborne.
	else: # Removes unnecessary transform work once the sticker is effectively front-facing.
		_visual.clear_turnover() # Keeps the printed face flat relative to the root for the remainder of the slam.
	if _landing_elapsed >= total_duration: # Finalizes the new attachment exactly at the end of the downward impact.
		global_position = _landing_target_position # Snaps only tiny floating-point residue to the exact new flat page position.
		_turnover_angle = 0.0 # Clears the completed turnover angle for the next interaction.
		_visual.clear_turnover() # Leaves the printed face perfectly flat on the page after impact.
		_visual.clear_peel() # Guarantees no previous curl state remains after a complete detach-and-place cycle.
		_landing_preview.hide_preview() # Keeps the placement guide disabled once the physical sticker has occupied the predicted landing transform.
		_contact_shadow.show_shadow() # Restores the small contact shadow only after the sticker has completed its physical slam onto the page.
		_state = InteractionState.RESTING # Makes the newly placed sticker immediately available for another realistic peel.
