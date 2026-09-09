class_name StickerVariant
extends RefCounted

const SPECIAL_PULL_CHANCE: float = 0.01 # Defines the independent chance that any normal pack pull becomes its special edition.

static func make(sticker_path: String, special: bool = false) -> Dictionary: # Builds one lightweight per-copy sticker value used across economy, reveal, collection, and placement.
	return {"path": sticker_path, "special": special} # Stores only the authored design identity and whether this exact copy is a special edition.

static func get_path(record: Dictionary) -> String: # Reads the authored sticker resource identity from a variant record.
	return str(record.get("path", "")) # Converts defensive Variant input into the strongly used path representation.

static func is_special(record: Dictionary) -> bool: # Reads whether one per-copy sticker record is its special edition.
	return bool(record.get("special", false)) # Defaults legacy or malformed records to the normal edition.

static func ownership_key(sticker_path: String, special: bool) -> String: # Builds the persistent inventory key for one design and edition without changing authored sticker resources.
	return "%s|special" % sticker_path if special else sticker_path # Keeps every legacy normal ownership key intact while storing specials separately.

static func path_from_ownership_key(key: String) -> String: # Resolves the authored path from either a legacy normal key or a special-edition key.
	return key.trim_suffix("|special") if key.ends_with("|special") else key # Removes only the controlled special suffix.

static func ownership_key_is_special(key: String) -> bool: # Reports whether a persistent ownership key represents the special edition.
	return key.ends_with("|special") # Uses the reserved suffix introduced by this variant format.
