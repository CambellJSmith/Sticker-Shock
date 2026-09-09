class_name UIFormat extends RefCounted # Shares compact player-facing time and sticker-name formatting.

static func duration(total_seconds: int) -> String: # Formats the real-world free-pack cooldown.
	var seconds: int = maxi(total_seconds, 0) # Clamps elapsed timers before splitting them.
	var hours: int = floori(float(seconds) / 3600.0) # Extracts whole hours without triggering Godot's implicit integer-division warning.
	var minutes: int = floori(float(seconds % 3600) / 60.0) # Extracts the remaining whole minutes explicitly as a floor operation.
	return "%02d:%02d:%02d" % [hours, minutes, seconds % 60] # Keeps the countdown width stable.

static func sticker_name(sticker_key: String) -> String: # Converts any exact sticker edition identity into a readable lowercase label.
	var artwork_path: String = StickerVariant.get_art_path(sticker_key) # Removes only the controlled per-copy edition suffix before formatting the authored filename.
	var base_name: String = artwork_path.get_file().get_basename().replace("_", " ").replace("-", " ").to_lower() # Preserves the authored design name while formatting separators.
	return "%s · %s" % [StickerVariant.get_edition_name(sticker_key), base_name] if StickerVariant.is_special(sticker_key) else base_name # Makes rainbow, silver, and gold pull results explicit without changing authored metadata.
