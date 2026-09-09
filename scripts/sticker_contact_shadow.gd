class_name StickerContactShadow
extends MeshInstance3D

const CONTACT_SHADOW_SHADER: Shader = preload("res://shaders/sticker_contact_shadow.gdshader") # Reuses one compiled shadow shader across every visible sticker instance.
const SHADOW_SCALE: float = 1.035 # Expands the alpha silhouette slightly so a thin shadow remains visible around the sticker edge.
const SHADOW_OFFSET: Vector2 = Vector2(0.022, 0.030) # Offsets the shadow by a tiny amount so the sticker reads as physical paper rather than a flat decal.
const SHADOW_HEIGHT_OFFSET: float = -0.00055 # Places the shadow beneath its sticker while keeping it above the previous paper stack layer.
const SHADOW_OPACITY: float = 0.16 # Keeps the resting contact shadow deliberately subtle against the pale book page.
const SHADOW_BLUR_RADIUS_TEXELS: float = 1.75 # Softens the authored alpha silhouette by only a few source pixels.

static var _shared_unit_mesh: ArrayMesh # Shares one four-vertex unit quad across every contact-shadow instance on every visible spread.

var _material: ShaderMaterial # Stores this copy's texture-bound shadow material without duplicating shader code.

func configure(sticker_size: Vector2, sticker_texture: Texture2D) -> void: # Configures one lightweight shared-geometry contact shadow from the sticker artwork alpha.
	var safe_size: Vector2 = Vector2(maxf(sticker_size.x, 0.001), maxf(sticker_size.y, 0.001)) # Normalizes malformed dimensions before applying the shared unit geometry.
	mesh = _get_shared_unit_mesh() # Reuses the same two-triangle mesh resource for every sticker contact shadow.
	scale = Vector3(safe_size.x * SHADOW_SCALE, 1.0, safe_size.y * SHADOW_SCALE) # Sizes only this node transform to the sticker bounds plus the subtle shadow spread.
	position = Vector3(SHADOW_OFFSET.x, SHADOW_HEIGHT_OFFSET, SHADOW_OFFSET.y) # Places the shadow just beneath and slightly offset from the sticker surface.
	_material = ShaderMaterial.new() # Creates the per-copy parameter resource needed for this sticker's artwork texture.
	_material.shader = CONTACT_SHADOW_SHADER # Binds the shared compatibility-safe unshaded contact-shadow shader.
	_material.render_priority = -1 # Draws the transparent shadow before the sticker material so the sticker remains visually on top.
	_material.set_shader_parameter("sticker_texture", sticker_texture) # Supplies the same authored alpha used by rendering, peeling, and packing.
	_material.set_shader_parameter("sticker_size", safe_size) # Supplies original physical dimensions so the shader can evaluate the exact peel fold in sticker-local space.
	var texture_width: float = maxf(float(sticker_texture.get_width()), 1.0) # Reads source width once so the fragment shader never queries texture dimensions.
	var texture_height: float = maxf(float(sticker_texture.get_height()), 1.0) # Reads source height once so blur spacing stays correct for non-square artwork.
	_material.set_shader_parameter("sticker_texel_size", Vector2(1.0 / texture_width, 1.0 / texture_height)) # Supplies normalized source-pixel size as a constant per-copy uniform.
	_material.set_shader_parameter("shadow_opacity", SHADOW_OPACITY) # Applies the restrained contact-shadow darkness.
	_material.set_shader_parameter("blur_radius_texels", SHADOW_BLUR_RADIUS_TEXELS) # Applies the compact texture-space softness around the silhouette.
	material_override = _material # Applies the shadow material to the complete two-triangle helper mesh.
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF # Prevents the synthetic contact shadow from casting another real shadow.
	gi_mode = GeometryInstance3D.GI_MODE_DISABLED # Keeps the helper out of global-illumination contribution work.
	show_shadow() # Starts reconstructed resting stickers with their complete contact shadow visible.

func set_peel(grab_local: Vector2, drag_local: Vector2) -> void: # Clips the contact shadow to exactly the material still resting on the page during an active peel.
	var drag_distance: float = drag_local.length() # Measures the same local pointer displacement used by the physical peel shader.
	if drag_distance <= 0.0001: # Treats a grabbed but unmoved sticker as fully attached.
		show_shadow() # Preserves the complete resting contact shadow until a meaningful peel actually begins.
		return # Avoids unstable peel-direction normalization at effectively zero drag.
	var peel_direction: Vector2 = drag_local / drag_distance # Recreates the normalized physical peel direction once on the CPU for all shadow fragments.
	var active_curl_width: float = minf(StickerMesh.PEEL_CURL_WIDTH, maxf(drag_distance * StickerMesh.PEEL_CURL_GROWTH, 0.002)) # Mirrors the physical shader's changing curl width exactly.
	var fold_projection: float = grab_local.dot(peel_direction) + (drag_distance + active_curl_width) * 0.5 # Recreates the moving boundary separating lifted material from material still touching the page.
	_material.set_shader_parameter("peel_direction", peel_direction) # Supplies the normalized fold direction without repeating normalization in every fragment.
	_material.set_shader_parameter("fold_projection", fold_projection) # Supplies the exact physical fold position used to remove shadow from the peeled side.
	_material.set_shader_parameter("peel_active", true) # Enables fold-aware alpha clipping while any meaningful peel displacement exists.
	visible = true # Keeps the surviving attached-area contact shadow rendered throughout the peel.

func show_shadow() -> void: # Restores the complete contact shadow when the physical sticker is fully attached to the page.
	_material.set_shader_parameter("peel_active", false) # Disables fold clipping so the entire authored silhouette contributes again.
	visible = true # Enables the cheap helper draw for the fully attached sticker.

func hide_shadow() -> void: # Removes the contact shadow once no sticker material remains attached to the page.
	visible = false # Leaves fully detached and airborne depth entirely to the existing real-time directional-light shadow.

func _get_shared_unit_mesh() -> ArrayMesh: # Returns the single immutable unit quad used by every contact-shadow instance.
	if _shared_unit_mesh == null: # Detects the first contact shadow created in this process.
		_shared_unit_mesh = _build_unit_mesh() # Builds the two-triangle geometry once and retains it for every later sticker.
	return _shared_unit_mesh # Returns the shared geometry without any per-sticker mesh allocation.

func _build_unit_mesh() -> ArrayMesh: # Builds one centered unit rectangle that instance transforms scale to each sticker size.
	var vertices: PackedVector3Array = PackedVector3Array([Vector3(-0.5, 0.0, -0.5), Vector3(0.5, 0.0, -0.5), Vector3(0.5, 0.0, 0.5), Vector3(-0.5, 0.0, 0.5)]) # Defines four flat XZ-plane unit corners around the sticker center.
	var uvs: PackedVector2Array = PackedVector2Array([Vector2(0.0, 0.0), Vector2(1.0, 0.0), Vector2(1.0, 1.0), Vector2(0.0, 1.0)]) # Maps the full authored sticker texture across the unit rectangle.
	var indices: PackedInt32Array = PackedInt32Array([0, 1, 2, 0, 2, 3]) # Builds exactly two triangles for the complete contact-shadow surface.
	var arrays: Array = [] # Creates the fixed mesh-array container required by ArrayMesh.
	arrays.resize(Mesh.ARRAY_MAX) # Sizes the container to Godot's complete mesh-array layout.
	arrays[Mesh.ARRAY_VERTEX] = vertices # Supplies the four shared contact-shadow vertex positions.
	arrays[Mesh.ARRAY_TEX_UV] = uvs # Supplies the source artwork coordinates used by the blur shader.
	arrays[Mesh.ARRAY_INDEX] = indices # Supplies the two indexed triangles without unnecessary duplicate vertices.
	var shadow_mesh: ArrayMesh = ArrayMesh.new() # Creates the single runtime mesh resource shared by every sticker contact shadow.
	shadow_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays) # Commits the four-vertex unit surface to the renderer once.
	return shadow_mesh # Returns the completed immutable shared contact-shadow geometry.
