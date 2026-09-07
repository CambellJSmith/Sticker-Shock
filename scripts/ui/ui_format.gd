class_name UIFormat extends RefCounted # Shares compact player-facing time and name formatting.

static func duration(total_seconds: int) -> String: # Formats the real-world free-pack cooldown.
	var seconds: int = maxi(total_seconds, 0) # Clamps elapsed timers before splitting them.
	var hours: int = seconds / 3600 # Extracts whole hours.
	var minutes: int = (seconds % 3600) / 60 # Extracts the remaining whole minutes.
	return "%02d:%02d:%02d" % [hours, minutes, seconds % 60] # Keeps the countdown width stable.

static func sticker_name(path: String) -> String: # Converts artwork filenames into readable lowercase labels.
	return path.get_file().get_basename().replace("_", " ").replace("-", " ").to_lower() # Preserves the resource identity while formatting its display name.
