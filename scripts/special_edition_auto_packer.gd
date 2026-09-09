class_name SpecialEditionAutoPacker
extends StickerAutoPacker

func find_tight_placement(sticker_key: String, sticker_size: Vector2, existing_placements: Array[Dictionary], spread_index: int) -> Dictionary: # Reuses the existing exact alpha-silhouette solver after removing only per-copy edition markers from its texture inputs.
	var artwork_path: String = StickerVariant.get_art_path(sticker_key) # Resolves the actual PNG used to derive the candidate sticker silhouette.
	var normalized_placements: Array[Dictionary] = [] # Builds a lightweight placement view containing real artwork paths while leaving authoritative persistence untouched.
	normalized_placements.resize(existing_placements.size()) # Allocates the exact required result capacity once before the compact normalization pass.
	for index: int in range(existing_placements.size()): # Visits each currently relevant placement exactly once.
		var normalized_placement: Dictionary = existing_placements[index].duplicate(false) # Copies only the small top-level placement dictionary because its values are primitive save fields.
		normalized_placement["path"] = StickerVariant.get_art_path(str(normalized_placement.get("path", ""))) # Replaces a possible special key with the shared authored artwork path used for alpha extraction.
		normalized_placements[index] = normalized_placement # Stores the normalized collision-only view without changing saved normal/special identity.
	return super.find_tight_placement(artwork_path, sticker_size, normalized_placements, spread_index) # Runs the established cached solver with identical geometry for normal and special editions of the same design.
