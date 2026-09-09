class_name SpecialEditionSticker
extends Sticker

var _edition: int = StickerVariant.EDITION_GOLD # Stores the exact premium finish this physical sticker should use, defaulting legacy construction to gold.

func set_edition(edition: int) -> void: # Selects the premium finish before the inherited physical sticker is configured.
	_edition = edition # Retains rainbow, silver, or gold identity for material setup.

func configure(sticker_size: Vector2, sticker_texture: Texture2D) -> void: # Composes standard sticker physics while applying the selected premium front finish.
	super.configure(sticker_size, sticker_texture) # Reuses the complete peel, collision, landing, adhesive-side, and geometry composition unchanged.
	var special_material: ShaderMaterial = _visual.material_override as ShaderMaterial # Reads the per-copy material created by the inherited StickerMesh configuration.
	if special_material != null: # Protects against an unexpected renderer configuration failure.
		special_material.set_shader_parameter("edition", _edition) # Applies rainbow, silver, or gold only to the printed front while preserving the shared physical shader.
