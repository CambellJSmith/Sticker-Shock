class_name StickerLandingPreview
extends MeshInstance3D

const LANDING_OUTLINE_SHADER: Shader = preload("res://shaders/landing_outline.gdshader") # Reuses one compiled outline shader across every sticker landing preview.
const PAGE_CLEARANCE: float = 0.00035 # Keeps the projected outline microscopically above its final stack height to prevent depth fighting.

var _material: ShaderMaterial # Stores the lightweight per-sticker outline parameters while sharing the compiled shader code.

func configure(source_mesh: Mesh, sticker_texture: Texture2D) -> void: # Configures a flat top-level preview from the sticker mesh and supplied artwork silhouette.
	mesh = source_mesh # Reuses the already-built flat grid instead of allocating duplicate landing geometry.
	_material = ShaderMaterial.new() # Creates a unique material parameter set for this sticker's artwork dimensions.
	_material.shader = LANDING_OUTLINE_SHADER # Binds the shared unlit procedural-silhouette contour shader to the landing preview.
	_material.set_shader_parameter("sticker_texture", sticker_texture) # Supplies the artwork alpha used as the complete final sticker silhouette.
	var imported_texture_size: Vector2i = sticker_texture.get_size() # Reads the imported artwork dimensions once so the shader never needs textureSize lookups per fragment.
	var texture_size: Vector2 = Vector2(float(imported_texture_size.x), float(imported_texture_size.y)) # Converts integer texture dimensions explicitly for strongly typed floating-point UV calculations.
	var safe_texture_size: Vector2 = Vector2(maxf(texture_size.x, 1.0), maxf(texture_size.y, 1.0)) # Protects texel calculations from invalid zero-sized resources without branching in the shader.
	var texel_size: Vector2 = Vector2(1.0 / safe_texture_size.x, 1.0 / safe_texture_size.y) # Calculates one normalized UV texel explicitly without relying on vector-by-vector division semantics.
	_material.set_shader_parameter("texel_size", texel_size) # Supplies one artwork texel in normalized UV coordinates for stable outline thickness.
	material_override = _material # Applies the contour material across the complete shared sticker mesh.
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF # Prevents the helper projection from creating any physical shadow of its own.
	top_level = true # Keeps the preview in world space so the carried sticker can move vertically without lifting the projected target off the page.
	visible = false # Keeps the preview absent until the sticker has fully detached and entered the carried state.

func show_at(sticker_world_basis: Basis, carried_world_position: Vector3, landing_height: float) -> void: # Places the outline at the exact transform the sticker root will occupy after release and landing.
	var landing_origin: Vector3 = Vector3(carried_world_position.x, landing_height + PAGE_CLEARANCE, carried_world_position.z) # Copies the carried horizontal position while placing the guide at the final flat stack height.
	global_transform = Transform3D(sticker_world_basis, landing_origin) # Copies the sticker's world rotation and scale so the projected artwork silhouette matches the final placement exactly.
	visible = true # Shows the guide only after its complete landing transform has been calculated.

func hide_preview() -> void: # Removes the landing guide whenever the sticker is attached, partially peeled, or has committed to a landing.
	visible = false # Disables rendering without freeing or rebuilding the reusable preview component.
