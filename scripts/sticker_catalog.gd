class_name StickerCatalog
extends RefCounted

const STICKER_ROOT: String = "res://assets/stickers" # Stores the project resource folder searched for pack-eligible sticker artwork.
const DEFAULT_LONG_EDGE: float = 2.10 # Defines the default physical artwork long edge used for newly won stickers.

var _sticker_paths: PackedStringArray = PackedStringArray() # Stores every discovered sticker resource path in deterministic alphabetical order.
var _size_cache: Dictionary = {} # Stores calculated aspect-preserving physical artwork sizes so texture dimensions are not repeatedly queried.

func rebuild() -> void: # Rebuilds the catalogue from project resources so newly added artwork automatically becomes pack eligible.
	_sticker_paths.clear() # Removes stale catalogue entries before scanning the current project resources.
	_size_cache.clear() # Removes cached dimensions because imported artwork may have changed since the previous catalogue build.
	_scan_resource_directory(STICKER_ROOT) # Recursively discovers sticker textures using ResourceLoader so imported files also work in exported builds.
	_sticker_paths.sort() # Stabilizes catalogue ordering because resource directory enumeration is not guaranteed to be deterministic.

func get_sticker_count() -> int: # Exposes the number of pack-eligible sticker artworks currently available.
	return _sticker_paths.size() # Returns the current catalogue entry count without exposing the mutable internal array.

func is_empty() -> bool: # Exposes whether packs can currently contain any stickers.
	return _sticker_paths.is_empty() # Returns true only when no compatible artwork was discovered.

func get_sticker_path(index: int) -> String: # Returns one catalogue resource path by validated index.
	if index < 0 or index >= _sticker_paths.size(): # Rejects invalid indices without allowing an array bounds error.
		return "" # Returns an empty path to represent an unavailable catalogue entry.
	return _sticker_paths[index] # Returns the requested immutable resource path.

func get_display_name(sticker_path: String) -> String: # Converts a resource path into the compact sticker identifier used by the shop interface.
	return sticker_path.get_file().get_basename() # Uses the source filename so display names remain predictable when new assets are dropped into the folder.

func get_default_size(sticker_path: String) -> Vector2: # Returns an aspect-preserving physical artwork size for rendering, manual placement, and automatic packing.
	if _size_cache.has(sticker_path): # Reuses the previously calculated dimensions when the same design appears more than once.
		var cached_size: Vector2 = _size_cache[sticker_path] # Narrows the cached Variant to the physical Vector2 size stored for this artwork.
		return cached_size # Returns the cached physical artwork dimensions without another texture query.
	var texture_resource: Resource = ResourceLoader.load(sticker_path, "Texture2D") # Loads the imported sticker texture through Godot's resource cache.
	if texture_resource is not Texture2D: # Detects missing or incompatible catalogue resources defensively.
		return Vector2(DEFAULT_LONG_EDGE, DEFAULT_LONG_EDGE) # Falls back to a square physical sticker so callers always receive usable dimensions.
	var sticker_texture: Texture2D = texture_resource as Texture2D # Narrows the validated resource for typed dimension access.
	var texture_width: float = maxf(float(sticker_texture.get_width()), 1.0) # Reads a safe positive imported pixel width.
	var texture_height: float = maxf(float(sticker_texture.get_height()), 1.0) # Reads a safe positive imported pixel height.
	var aspect_ratio: float = texture_width / texture_height # Calculates artwork width divided by height for physical aspect preservation.
	var sticker_size: Vector2 = Vector2(DEFAULT_LONG_EDGE, DEFAULT_LONG_EDGE) # Seeds a square fallback before selecting the long-axis branch.
	if aspect_ratio >= 1.0: # Handles landscape and square artwork with a fixed physical width.
		sticker_size = Vector2(DEFAULT_LONG_EDGE, DEFAULT_LONG_EDGE / aspect_ratio) # Preserves the imported artwork aspect ratio without stretching.
	else: # Handles portrait artwork with a fixed physical height.
		sticker_size = Vector2(DEFAULT_LONG_EDGE * aspect_ratio, DEFAULT_LONG_EDGE) # Preserves the imported artwork aspect ratio without stretching.
	_size_cache[sticker_path] = sticker_size # Caches the calculated physical size for future duplicate pack draws and placement checks.
	return sticker_size # Returns the final aspect-preserving artwork dimensions used directly as the sticker sheet size.

func create_random_pack(pack_size: int, random_number_generator: RandomNumberGenerator) -> PackedStringArray: # Creates a pack by drawing random catalogue entries with duplicates allowed.
	var pack: PackedStringArray = PackedStringArray() # Stores the generated sticker resource paths in reveal order.
	if pack_size <= 0 or _sticker_paths.is_empty(): # Rejects impossible pack requests without modifying any progression state.
		return pack # Returns an empty pack when no draw can be performed.
	for _pack_slot: int in range(pack_size): # Draws one independent sticker for every requested pack position.
		var random_index: int = random_number_generator.randi_range(0, _sticker_paths.size() - 1) # Selects a uniformly random catalogue entry for the current pack slot.
		pack.append(_sticker_paths[random_index]) # Adds the selected sticker while intentionally allowing duplicates like a physical sticker pack.
	return pack # Returns the complete ordered pack for inventory granting and visual reveal.

func _scan_resource_directory(directory_path: String) -> void: # Recursively discovers imported texture resources while retaining their original project filenames.
	var entries: PackedStringArray = ResourceLoader.list_directory(directory_path) # Lists resources through ResourceLoader so imported artwork remains addressable after export.
	for entry: String in entries: # Examines every file or child directory returned for the current resource folder.
		if entry.ends_with("/"): # Detects subdirectories using the trailing slash supplied by ResourceLoader.
			var child_directory_name: String = entry.left(entry.length() - 1) # Removes the directory marker before joining the recursive resource path.
			_scan_resource_directory(directory_path.path_join(child_directory_name)) # Recursively discovers stickers inside organizational subfolders.
			continue # Skips file-extension handling because the current entry is a directory.
		var extension: String = entry.get_extension().to_lower() # Normalizes the resource extension for case-independent supported-type matching.
		if not _is_supported_extension(extension): # Ignores project resources that are not accepted sticker image formats.
			continue # Advances immediately without attempting to load an unrelated resource.
		var sticker_path: String = directory_path.path_join(entry) # Builds the complete res resource path used by ResourceLoader and the sticker renderer.
		if ResourceLoader.exists(sticker_path, "Texture2D"): # Includes only entries that Godot can resolve as imported texture resources.
			_sticker_paths.append(sticker_path) # Adds the valid sticker artwork to the pack catalogue.

func _is_supported_extension(extension: String) -> bool: # Tests one normalized file extension against formats that Godot imports as sticker artwork.
	match extension: # Uses a fixed branch table instead of allocating or searching a collection during catalogue discovery.
		"png", "webp", "svg", "jpg", "jpeg": # Accepts common raster and vector formats that can resolve to Texture2D resources.
			return true # Marks the resource as eligible for validation and pack catalogue inclusion.
		_: # Handles every non-sticker resource extension found alongside artwork.
			return false # Rejects the unrelated resource without attempting to load it.
