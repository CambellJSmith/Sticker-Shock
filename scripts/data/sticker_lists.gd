@tool
class_name StickerLists
extends Resource

@export_storage var packs: PackedStringArray = PackedStringArray() # Stores the controlled list of valid pack names available to sticker definitions.
@export_storage var artists: PackedStringArray = PackedStringArray() # Stores the controlled list of valid artist names available to sticker definitions.
@export_storage var rarities: PackedStringArray = PackedStringArray() # Stores the controlled list of valid rarity names available to sticker definitions.

func normalize() -> void: # Removes blank and duplicate entries while keeping each list stable for external-tool selection.
	packs = _normalized_copy(packs) # Normalizes pack names before persistence or runtime use.
	artists = _normalized_copy(artists) # Normalizes artist names before persistence or runtime use.
	rarities = _normalized_copy(rarities) # Normalizes rarity names before persistence or runtime use.

func _normalized_copy(source: PackedStringArray) -> PackedStringArray: # Produces one clean deterministic list without mutating caller-owned data during iteration.
	var result: PackedStringArray = PackedStringArray() # Stores the cleaned ordered values returned to the owning resource.
	var seen: Dictionary[String, bool] = {} # Tracks exact normalized strings so duplicates can be rejected in constant average time.
	for raw_value: String in source: # Examines every configured list entry once.
		var value: String = raw_value.strip_edges() # Removes accidental surrounding whitespace from user-entered list values.
		if value.is_empty() or seen.has(value): # Rejects blank values and exact duplicates.
			continue # Advances without modifying output for unusable entries.
		seen[value] = true # Marks the normalized value as already emitted.
		result.append(value) # Preserves the first occurrence in stable user-defined order.
	return result # Returns the compact cleaned list for persistence and dropdown population.
