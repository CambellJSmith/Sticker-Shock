class_name StickerContactShadow
extends MeshInstance3D

const CONTACT_SHADOW_SHADER: Shader = preload("res://shaders/sticker_contact_shadow.gdshader") # Reuses one compiled shadow shader across every visible sticker instance.
const SHADOW_SCALE: float = 1.035 # Expands the alpha silhouette slightly so a thin shadow remains visible around the sticker edge.
const SHADOW_OFFSET: Vector2 = Vector2(0.022, 0.030) # Offsets the shadow by a tiny amount so the sticker reads as physical paper rather than a flat decal.
const SHADOW_HEIGHT_OFFSET: float = -0.00055 # Places the shadow beneath its sticker while keeping it above the previous paper stack layer.
const SHADOW_OPACITY: float = 0.16 # Keeps the resting contact shadow deliberately subtle against the pale book page.
const SHADOW_BLUR_RADIUS_TEXELS: float = 1.75 # Softens the authored alpha silhouette by only a few source pixels.

var _material: ShaderMaterial # Stores this copy's texture-bound shadow material without duplicating shader code.

func configure(sticker_size: Vector2, sticker_texture: Texture2D) -> void: # Builds one lightweight four-vertex contact shadow from the sticker artwork alpha.
	mesh = _build_shadow_mesh(sticker_size) # Creates only two triangles instead of duplicating the peel mesh's dense tessellation.
	position = Vector3(SHADOW_OFFSET.x, SHADOW_HEIGHT_OFFSET, SHADOW_OFFSET.y) # Places the shadow just beneath and slightly offset from the sticker surface.
	_material = ShaderMaterial.new() # Creates the per-copy parameter resource needed for this sticker's artwork texture.
	_material.shader = CONTACT_SHADOW_SHADER # Binds the shared compatibility-safe unshaded contact-shadow shader.
	_material.render_priority = -1 # Draws the transparent shadow before the sticker material so the sticker remains visually on top.
	_material.set_shader_parameter("sticker_texture", sticker_texture) # Supplies the same authored alpha used by rendering, peeling, and packing.
	_material.set_shader_parameter("shadow_opacity", SHADOW_OPACITY) # Applies the restrained contact-shadow darkness.
	_material.set_shader_parameter("blur_radius_texels", SHADOW_BLUR_RADIUS_TEXELS) # Applies the compact texture-space softness around the silhouette.
	material_override = _material # Applies the shadow material to the complete two-triangle helper mesh.
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF # Prevents the synthetic contact shadow from casting another real shadow.
	gi_mode = GeometryInstance3D.GI_MODE_DISABLED # Keeps the helper out of global-illumination contribution work.
	visible = true # Shows the contact shadow immediately for reconstructed resting stickers.

func show_shadow() -> void: # Restores the contact shadow when the physical sticker has fully returned to the page.
	visible = true # Enables the cheap helper draw only while the sticker is resting flat.

func hide_shadow() -> void: # Removes the contact shadow while the sticker is peeling, carried, returning, or airborne.
	visible = false # Leaves raised-state depth entirely to the existing real-time directional-light shadow.

func _build_shadow_mesh(sticker_size: Vector2) -> ArrayMesh: # Builds a minimal flat rectangle slightly larger than the sticker artwork bounds.
	var safe_size: Vector2 = Vector2(maxf(sticker_size.x, 0.001), maxf(sticker_size.y, 0.001)) * SHADOW_SCALE # Normalizes malformed dimensions and applies the subtle contact-shadow spread.
	var half_size: Vector2 = safe_size * 0.5 # Converts the complete shadow bounds into centered half extents.
	var vertices: PackedVector3Array = PackedVector3Array([Vector3(-half_size.x, 0.0, -half_size.y), Vector3(half_size.x, 0.0, -half_size.y), Vector3(half_size.x, 0.0, half_size.y), Vector3(-half_size.x, 0.0, half_size.y)]) # Defines four flat XZ-plane corners around the sticker center.
	var uvs: PackedVector2Array = PackedVector2Array([Vector2(0.0, 0.0), Vector2(1.0, 0.0), Vector2(1.0, 1.0), Vector2(0.0, 1.0)]) # Maps the full authored sticker texture across the expanded shadow rectangle.
	var indices: PackedInt32Array = PackedInt32Array([0, 1, 2, 0, 2, 3]) # Builds exactly two triangles for the complete contact-shadow surface.
	var arrays: Array = [] # Creates the fixed mesh-array container required by ArrayMesh.
	arrays.resize(Mesh.ARRAY_MAX) # Sizes the container to Godot's complete mesh-array layout.
	arrays[Mesh.ARRAY_VERTEX] = vertices # Supplies the four contact-shadow vertex positions.
	arrays[Mesh.ARRAY_TEX_UV] = uvs # Supplies the source artwork coordinates used by the blur shader.
	arrays[Mesh.ARRAY_INDEX] = indices # Supplies the two indexed triangles without unnecessary duplicate vertices.
	var shadow_mesh: ArrayMesh = ArrayMesh.new() # Creates the compact runtime mesh resource for this sticker copy.
	shadow_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays) # Commits the four-vertex shadow surface to the renderer.
	return shadow_mesh # Returns the completed lightweight contact-shadow geometry.
