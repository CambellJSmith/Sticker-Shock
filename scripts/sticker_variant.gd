class_name StickerVariant
extends RefCounted

const SPECIAL_SUFFIX: String = "|special" # Reserves a compact suffix used only for per-copy special-edition identity.
const SPECIAL_PULL_CHANCE: float = 0.01 # Defines the independent chance that any normal pack pull becomes its special edition.

static func make_key(sticker_path: String, special: bool = false) -> String: # Builds the persistent identity for one design and edition without duplicating authored resources.
	return sticker_path + SPECIAL_SUFFIX if special else sticker_path # Keeps all existing normal paths unchanged and gives special copies a deterministic identity.

static func get_art_path(sticker_key: String) -> String: # Resolves the authored artwork path from a normal or special copy identity.
	return sticker_key.trim_suffix(SPECIAL_SUFFIX) if is_special(sticker_key) else sticker_key # Removes only the controlled edition suffix before any resource load.

static func is_special(sticker_key: String) -> bool: # Reports whether one copy identity represents the special edition.
	return sticker_key.ends_with(SPECIAL_SUFFIX) # Uses the reserved suffix so specialness survives saves and physical placement records.
