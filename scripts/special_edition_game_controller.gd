class_name SpecialEditionGameController
extends GameController

func _init() -> void: # Replaces only the economy and sticker silhouette solver with edition-aware implementations before normal game initialization begins.
	_economy = GuaranteedSpecialStickerEconomy.new() # Preserves the existing economy interface while adding the one-time guaranteed special pull milestone.
	_auto_packer = SpecialEditionAutoPacker.new() # Preserves the complete existing controller flow while ensuring special copy keys never reach ResourceLoader during packing.

func show_sticker_inspection(sticker_key: String) -> bool: # Opens a normal or special book sticker while preserving its per-copy edition material in the isolated inspector.
	if _game_ui == null or sticker_key.is_empty(): # Rejects inspection before the persistent interface exists or when no sticker identity was resolved.
		return false # Leaves the physical book unchanged when no modal can be constructed.
	var artwork_path: String = StickerVariant.get_art_path(sticker_key) # Resolves the real PNG shared by normal and special editions.
	if not _game_ui.show_sticker_inspection(artwork_path): # Uses the established modal setup and texture-loading path first.
		return false # Leaves the current destination unchanged when the artwork cannot be inspected.
	if StickerVariant.is_special(sticker_key): # Rebuilds only special copies with the edition-aware material after the common inspector has initialized its state.
		var texture: Texture2D = load(artwork_path) as Texture2D # Reuses Godot's imported texture cache for the already validated artwork.
		if texture != null: # Protects against the resource disappearing between modal setup and the edition-specific rebuild.
			var inspection_mesh: StickerMesh = _game_ui._inspection._sticker_mesh # Retrieves the inspector-owned temporary mesh without touching the persistent book copy.
			inspection_mesh.configure(_catalog.get_default_size(artwork_path), texture, true) # Applies the same special-edition shader path used by shop reveals and placement previews.
			inspection_mesh.clear_peel() # Keeps the isolated inspection copy flat at startup.
			inspection_mesh.clear_turnover() # Keeps the isolated inspection copy front-facing until the player rotates it.
	return true # Confirms that the requested edition is now visible in the inspection modal.
