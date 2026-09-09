class_name SpecialEditionSticker
extends Sticker

func configure(sticker_size: Vector2, sticker_texture: Texture2D) -> void: # Composes the standard physical sticker behavior while replacing only its front material response with the special gold edition.
	super.configure(sticker_size, sticker_texture) # Reuses the complete existing peel, collision, landing, and adhesive-side composition unchanged.
	var special_material: ShaderMaterial = _visual.material_override as ShaderMaterial # Reads the per-copy material created by the inherited StickerMesh configuration.
	if special_material != null: # Protects against an unexpected renderer configuration failure.
		special_material.set_shader_parameter("special_edition", true) # Enables the physically metallic shiny gold front treatment only for this special copy.
