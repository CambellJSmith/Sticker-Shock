class_name StickerCatalog
extends RefCounted

const STICKER_DEFINITION_ROOT: String = "res://data/stickers" # Stores the project resource folder searched for pack-eligible sticker definition resources.
const DEFAULT_LONG_EDGE: float = 2.10 # Defines the default physical artwork long edge used for newly won stickers.

var _sticker_paths: Array[String] = [] # Stores every discovered sticker art resource path in deterministic numerical-ID order.
var _definitions_by_art_path: Dictionary[String, StickerDefinition] = {} # Maps the renderer-compatible artwork path to its complete sticker metadata resource.
var _sticker_paths_by_pack: Dictionary = {} # Groups renderer-compatible artwork paths by pack name for pack-specific draws.
var _seen_ids: Dictionary[int, bool] = {} # Tracks numerical sticker identifiers so malformed duplicate definitions cannot enter the catalogue.
var _size_cache: Dictionary = {} # Stores calculated aspect-preserving physical artwork sizes so texture dimensions are not repeatedly queried.

func rebuild() -> void: # Rebuilds the catalogue from typed sticker resources created by the external sticker authoring tool.
	_sticker_paths.clear() # Removes stale catalogue entries before scanning the current project resources.
	_definitions_by_art_path.clear() # Removes stale metadata lookups before registering the current definitions.
	_sticker_paths_by_pack.clear() # Removes stale pack membership before rebuilding pack-specific pools.
	_seen_ids.clear() # Removes previous identifier validation state before rescanning definitions.
	_size_cache.clear() # Removes cached dimensions because imported artwork may have changed since the previous catalogue build.
	_scan_definition_directory(STICKER_DEFINITION_ROOT) # Recursively discovers StickerDefinition resources through ResourceLoader for editor and exported builds.
	_sticker_paths.sort_custom(_sort_art_paths_by_id) # Stabilizes catalogue ordering by the numerical IDs stored inside each sticker resource.
	for pack_name: Variant in _sticker_paths_by_pack.keys(): # Visits every generated pack pool once after definition discovery is complete.
		var pack_paths: Array[String] = _sticker_paths_by_pack[pack_name] # Retrieves the stored pack collection for deterministic sorting.
		pack_paths.sort_custom(_sort_art_paths_by_id) # Keeps each pack ordered by sticker ID before random selection or future UI use.

func get_sticker_count() -> int: # Exposes the number of pack-eligible sticker definitions currently available.
	return _sticker_paths.size() # Returns the current catalogue entry count without exposing the mutable internal array.

func is_empty() -> bool: # Exposes whether packs can currently contain any stickers.
	return _sticker_paths.is_empty() # Returns true only when no valid sticker definitions were discovered.

func get_sticker_path(index: int) -> String: # Returns one renderer-compatible sticker artwork path by validated catalogue index.
	if index < 0 or index >= _sticker_paths.size(): # Rejects invalid indices without allowing an array bounds error.
		return "" # Returns an empty path to represent an unavailable catalogue entry.
	return _sticker_paths[index] # Returns the artwork path expected by the existing physical sticker renderer and persistence systems.

func get_definition(sticker_path: String) -> StickerDefinition: # Returns the complete metadata object associated with one renderer-compatible artwork path.
	if not _definitions_by_art_path.has(sticker_path): # Rejects paths that are not represented by a valid generated sticker resource.
		return null # Returns no metadata object for unknown artwork.
	return _definitions_by_art_path[sticker_path] # Returns the immutable catalogue-owned definition resource reference.

func get_sticker_id(sticker_path: String) -> int: # Returns the numerical ID stored in one sticker definition.
	var definition: StickerDefinition = get_definition(sticker_path) # Resolves the metadata resource through the existing artwork identity.
	return definition.id if definition != null else 0 # Returns the stored ID or a safe invalid identifier for unknown artwork.

func get_display_name(sticker_path: String) -> String: # Returns the authored player-facing sticker name while retaining a filename fallback for defensive compatibility.
	var definition: StickerDefinition = get_definition(sticker_path) # Resolves the metadata resource through the existing artwork identity.
	return definition.sticker_name if definition != null else sticker_path.get_file().get_basename() # Uses authored metadata whenever a valid generated sticker exists.

func get_description(sticker_path: String) -> String: # Returns the authored descriptive text for one sticker.
	var definition: StickerDefinition = get_definition(sticker_path) # Resolves the complete sticker data object.
	return definition.description if definition != null else "" # Returns empty text when no definition is available.

func get_pack_name(sticker_path: String) -> String: # Returns the controlled pack assignment for one sticker.
	var definition: StickerDefinition = get_definition(sticker_path) # Resolves the complete sticker data object.
	return definition.pack if definition != null else "" # Returns no pack for unknown artwork.

func get_artist_name(sticker_path: String) -> String: # Returns the controlled artist assignment for one sticker.
	var definition: StickerDefinition = get_definition(sticker_path) # Resolves the complete sticker data object.
	return definition.artist if definition != null else "" # Returns no artist for unknown artwork.

func get_rarity_name(sticker_path: String) -> String: # Returns the controlled rarity assignment for one sticker.
	var definition: StickerDefinition = get_definition(sticker_path) # Resolves the complete sticker data object.
	return definition.rarity if definition != null else "" # Returns no rarity for unknown artwork.

func get_pack_names() -> PackedStringArray: # Returns every pack currently represented by at least one valid sticker definition.
	var result: PackedStringArray = PackedStringArray() # Stores a caller-owned stable list of pack names.
	for pack_name: Variant in _sticker_paths_by_pack.keys(): # Visits each unique pack group discovered from sticker definitions.
		result.append(str(pack_name)) # Copies the pack name without exposing the mutable lookup dictionary.
	result.sort() # Stabilizes pack ordering for future menus and authoring-aware runtime features.
	return result # Returns the complete generated pack list represented by sticker content.

func get_default_size(sticker_path: String) -> Vector2: # Returns an aspect-preserving physical artwork size for rendering, manual placement, and automatic packing.
	if _size_cache.has(sticker_path): # Reuses the previously calculated dimensions when the same design appears more than once.
		var cached_size: Vector2 = _size_cache[sticker_path] # Narrows the cached Variant to the physical Vector2 size stored for this artwork.
		return cached_size # Returns the cached physical artwork dimensions without another texture query.
	var texture_resource: Resource = ResourceLoader.load(sticker_path, "Texture2D") # Loads the imported PNG through Godot's resource cache.
	if texture_resource is not Texture2D: # Detects missing or incompatible catalogue artwork defensively.
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

func create_random_pack(pack_size: int, random_number_generator: RandomNumberGenerator, pack_name: String = "") -> PackedStringArray: # Creates a pack from all stickers or one authored pack group with duplicates allowed.
	var result: PackedStringArray = PackedStringArray() # Stores the generated sticker artwork paths in reveal order.
	if pack_size <= 0: # Rejects impossible pack sizes before resolving any catalogue collection.
		return result # Returns an empty pack when no draw can be performed.
	var source_paths: Array[String] = _sticker_paths # Uses the complete catalogue when no specific pack was requested.
	if not pack_name.is_empty(): # Selects a controlled pack group when the caller provides one.
		if not _sticker_paths_by_pack.has(pack_name): # Rejects pack names that have no valid sticker definitions.
			return result # Returns no draw for an unavailable authored pack.
		source_paths = _sticker_paths_by_pack[pack_name] # Uses only stickers assigned to the requested pack.
	if source_paths.is_empty(): # Rejects empty global or pack-specific pools safely.
		return result # Returns an empty pack without touching progression state.
	for _pack_slot: int in range(pack_size): # Draws one independent sticker for every requested pack position.
		var random_index: int = random_number_generator.randi_range(0, source_paths.size() - 1) # Selects a uniformly random catalogue entry for the current pack slot.
		result.append(source_paths[random_index]) # Adds the selected artwork path while intentionally allowing duplicates like a physical sticker pack.
	return result # Returns the complete ordered pack for inventory granting and visual reveal.

func _scan_definition_directory(directory_path: String) -> void: # Recursively discovers generated StickerDefinition resources while ignoring unrelated data files.
	var entries: PackedStringArray = ResourceLoader.list_directory(directory_path) # Lists native resources through ResourceLoader so definitions remain addressable after export.
	for entry: String in entries: # Examines every file or child directory returned for the current resource folder.
		if entry.ends_with("/"): # Detects subdirectories using the trailing slash supplied by ResourceLoader.
			var child_directory_name: String = entry.left(entry.length() - 1) # Removes the directory marker before joining the recursive resource path.
			_scan_definition_directory(directory_path.path_join(child_directory_name)) # Recursively discovers generated definitions inside organizational subfolders.
			continue # Skips extension handling because the current entry is a directory.
		var extension: String = entry.get_extension().to_lower() # Normalizes the native resource extension for supported-type matching.
		if extension != "tres" and extension != "res": # Ignores files that cannot contain native StickerDefinition resources.
			continue # Advances without attempting to load unrelated data.
		var definition_path: String = directory_path.path_join(entry) # Builds the complete native Godot resource path for loading.
		var loaded_resource: Resource = ResourceLoader.load(definition_path) # Loads the generated data object through Godot's normal resource cache.
		if loaded_resource is not StickerDefinition: # Rejects native resources that use another data class.
			continue # Advances without polluting the sticker catalogue.
		_register_definition(loaded_resource as StickerDefinition, definition_path) # Validates and registers the generated sticker object.

func _register_definition(definition: StickerDefinition, definition_path: String) -> void: # Registers one validated generated sticker while preserving renderer compatibility through its PNG path.
	if not definition.is_valid(): # Rejects incomplete resources before any catalogue state is changed.
		push_warning("invalid sticker definition ignored: %s" % definition_path) # Reports malformed generated or manually edited resources for development diagnostics.
		return # Leaves the catalogue unchanged for incomplete data.
	if _seen_ids.has(definition.id): # Rejects duplicate numerical IDs even if external files were manually copied or edited.
		push_warning("duplicate sticker id ignored: %d" % definition.id) # Reports the conflicting identifier without allowing ambiguous game data.
		return # Keeps the first valid definition as the authoritative sticker for that ID.
	var art_path: String = definition.art.resource_path # Reads the imported PNG resource path expected by all existing physical sticker systems.
	if art_path.is_empty() or not ResourceLoader.exists(art_path, "Texture2D"): # Rejects definitions whose PNG dependency cannot be loaded by Godot.
		push_warning("sticker art could not be loaded: %s" % definition_path) # Reports the broken content object for quick authoring diagnosis.
		return # Prevents invalid artwork paths from reaching renderer or persistence code.
	if _definitions_by_art_path.has(art_path): # Rejects two definition resources pointing at the exact same PNG identity.
		push_warning("duplicate sticker art ignored: %s" % art_path) # Reports ambiguous artwork reuse because existing saves key ownership by art path.
		return # Keeps the first valid resource bound to the renderer-compatible identity.
	_seen_ids[definition.id] = true # Reserves the numerical ID before adding the sticker to any public catalogue collection.
	_definitions_by_art_path[art_path] = definition # Stores the complete metadata object behind the existing artwork identity.
	_sticker_paths.append(art_path) # Adds the renderer-compatible PNG path to the global pack pool.
	var pack_paths: Array[String] = [] # Creates a typed pack pool when this is the first sticker assigned to its pack.
	if _sticker_paths_by_pack.has(definition.pack): # Reuses the existing authored pack pool when earlier definitions share the same pack.
		pack_paths = _sticker_paths_by_pack[definition.pack] # Retrieves the existing typed collection for mutation.
	pack_paths.append(art_path) # Adds this sticker to its controlled authored pack group.
	_sticker_paths_by_pack[definition.pack] = pack_paths # Stores the updated typed pack collection back into the lookup.

func _sort_art_paths_by_id(left_path: String, right_path: String) -> bool: # Orders renderer-compatible artwork identities by their StickerDefinition numerical IDs.
	var left_definition: StickerDefinition = get_definition(left_path) # Resolves the left comparison object's authored metadata.
	var right_definition: StickerDefinition = get_definition(right_path) # Resolves the right comparison object's authored metadata.
	if left_definition == null: # Keeps unknown defensive fallback paths after every valid generated definition.
		return false # Reports that the invalid left entry should not precede a valid right entry.
	if right_definition == null: # Keeps a valid left definition before an unknown defensive fallback path.
		return true # Reports that the valid generated sticker precedes the invalid entry.
	return left_definition.id < right_definition.id # Uses the explicit numerical sticker identity as the deterministic catalogue order.
