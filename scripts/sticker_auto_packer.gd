class_name StickerAutoPacker
extends RefCounted

const GRID_CELL_SIZE: float = 0.10 # Defines the physical occupancy resolution used for alpha-silhouette packing.
const ALPHA_THRESHOLD: float = 0.08 # Matches the visible sticker alpha cutoff closely enough for physical placement prediction.
const MAX_FRONTIER_SAMPLES: int = 32 # Caps existing-cluster edge anchors tested for the canonical sticker orientation so dense pages remain responsive.
const MAX_BOUNDARY_SAMPLES: int = 16 # Caps candidate silhouette edge anchors while preserving broad contour coverage.
const FALLBACK_GRID_STRIDE: int = 2 # Defines the sparse page scan used only when frontier-based nesting cannot find a legal fit.

var _base_mask_cache: Dictionary = {} # Caches alpha-derived unrotated masks so texture readback never happens inside candidate searches.
var _canonical_mask_cache: Dictionary = {} # Caches canonical packed masks, bounds, boundaries, and contour samples for duplicate stickers.

func find_tight_placement(sticker_path: String, sticker_size: Vector2, existing_placements: Array[Dictionary], spread_index: int) -> Dictionary: # Finds a fast tight zero-overlap placement inside one active two-page spread.
	var best_result: Dictionary = {} # Stores the strongest legal placement found across both pages.
	var best_score: float = -INF # Starts below every valid contact score so the first legal candidate becomes the baseline.
	for local_page_index: int in range(StickerBookLayout.PAGES_PER_SPREAD): # Searches the visible left and right pages independently.
		var absolute_page_index: int = StickerBookLayout.get_absolute_page_index(spread_index, local_page_index) # Resolves the persistent page represented by this visible page side.
		var page_bounds: Rect2 = StickerBookLayout.get_page_bounds(local_page_index) # Retrieves the usable placement rectangle for this page.
		var page_dimensions: Vector2i = _get_page_grid_dimensions(page_bounds) # Converts the page rectangle into integer occupancy dimensions.
		var occupancy: PackedByteArray = _build_page_occupancy(existing_placements, absolute_page_index, page_bounds, page_dimensions) # Rasterizes this page into one compact contiguous byte grid.
		var occupancy_count: int = _count_occupied_cells(occupancy) # Counts occupied grid cells once so empty-page handling and cluster scoring stay cheap.
		if occupancy_count == 0: # Handles an unused page without generating a frontier or searching thousands of candidate contacts.
			var empty_result: Dictionary = _find_centered_empty_page_placement(sticker_path, sticker_size, page_bounds, page_dimensions, absolute_page_index) # Finds a centered canonical-orientation placement that physically fits the blank page.
			if not empty_result.is_empty() and best_result.is_empty(): # Keeps an empty-page solution as a fallback while still allowing a tighter occupied-page result to win later.
				empty_result["score"] = -1.0 # Gives blank-page placement lower priority than any genuine edge-contact placement.
				best_result = empty_result # Stores the centered empty-page fallback without returning prematurely.
				best_score = -1.0 # Records the fallback score used by later occupied-page candidates.
			continue # Skips frontier generation because there is no existing silhouette to nest against.
		var frontier: PackedInt32Array = _build_frontier(occupancy, page_dimensions) # Builds compact encoded empty cells immediately adjacent to existing sticker material.
		if frontier.is_empty(): # Handles a pathological fully occupied raster without doing any candidate work.
			continue # Leaves this page unavailable and advances to the opposite page.
		var occupancy_center: Vector2 = _calculate_occupancy_center(occupancy, page_dimensions, occupancy_count) # Calculates the cluster centroid once for compactness tie-breaking.
		var page_result: Dictionary = _search_page_frontier(sticker_path, sticker_size, page_bounds, page_dimensions, absolute_page_index, occupancy, frontier, occupancy_center) # Performs bounded contour nesting at the sticker's canonical source orientation.
		if page_result.is_empty(): # Detects a page where contour nesting did not expose a legal placement.
			continue # Leaves the sparse fallback for the final recovery pass after both pages are checked.
		var page_score: float = float(page_result.get("score", -INF)) # Retrieves the tight-contact score returned by the page search.
		if page_score > best_score: # Replaces the current result when this page packs the sticker more tightly.
			best_score = page_score # Stores the stronger score for the remaining page comparison.
			best_result = page_result # Stores the winning upright world placement.
	if not best_result.is_empty(): # Returns immediately when normal contour nesting or an empty-page fallback produced a legal placement.
		best_result.erase("score") # Removes internal solver metadata before handing the placement to persistent game state.
		return best_result # Supplies the strongest legal result found without running the fallback scan.
	return _find_fallback_placement(sticker_path, sticker_size, existing_placements, spread_index) # Performs a sparse bounded recovery scan before declaring the spread full.

func _search_page_frontier(sticker_path: String, sticker_size: Vector2, page_bounds: Rect2, page_dimensions: Vector2i, absolute_page_index: int, occupancy: PackedByteArray, frontier: PackedInt32Array, occupancy_center: Vector2) -> Dictionary: # Searches one occupied page only at the sticker's canonical source orientation.
	return _search_canonical_orientation(sticker_path, sticker_size, page_bounds, page_dimensions, absolute_page_index, occupancy, frontier, occupancy_center) # Searches only the source artwork orientation while preserving exact source-alpha nesting and contact scoring.

func _search_canonical_orientation(sticker_path: String, sticker_size: Vector2, page_bounds: Rect2, page_dimensions: Vector2i, absolute_page_index: int, occupancy: PackedByteArray, frontier: PackedInt32Array, occupancy_center: Vector2) -> Dictionary: # Searches the source artwork orientation against sampled page and sticker contour anchors.
	var mask_data: Dictionary = _get_canonical_mask(sticker_path, sticker_size) # Retrieves cached packed occupancy, bounds, and contour samples for the source orientation.
	var mask_cells: PackedInt32Array = mask_data.get("cells", PackedInt32Array()) # Retrieves interleaved local x/z occupancy coordinates.
	var boundary_samples: PackedInt32Array = mask_data.get("boundary_samples", PackedInt32Array()) # Retrieves a small distributed contour sample used for candidate generation and scoring.
	if mask_cells.is_empty() or boundary_samples.is_empty(): # Rejects malformed artwork masks without entering candidate loops.
		return {} # Reports that the canonical orientation cannot produce a physical placement.
	var min_x: int = int(mask_data.get("min_x", 0)) # Retrieves the cached leftmost local occupancy offset.
	var max_x: int = int(mask_data.get("max_x", 0)) # Retrieves the cached rightmost local occupancy offset.
	var min_z: int = int(mask_data.get("min_z", 0)) # Retrieves the cached topmost local occupancy offset.
	var max_z: int = int(mask_data.get("max_z", 0)) # Retrieves the cached bottommost local occupancy offset.
	var frontier_count: int = frontier.size() # Stores the encoded frontier-cell count for sampling calculations.
	var frontier_stride: int = maxi(1, ceili(float(frontier_count) / float(MAX_FRONTIER_SAMPLES))) # Limits dense page contours to a bounded representative subset.
	var tested_centers: PackedByteArray = PackedByteArray() # Allocates a compact deduplication grid for the canonical orientation.
	tested_centers.resize(page_dimensions.x * page_dimensions.y) # Gives every valid page center one byte of tested-state storage.
	var best_result: Dictionary = {} # Stores the strongest legal center found for the canonical orientation.
	var best_score: float = -INF # Starts below every possible contact score for the canonical orientation.
	for frontier_index: int in range(0, frontier_count, frontier_stride): # Visits a bounded subset of empty cells adjacent to the existing sticker cluster.
		var encoded_frontier_cell: int = frontier[frontier_index] # Retrieves one compact row-major page-cell index.
		var frontier_x: int = posmod(encoded_frontier_cell, page_dimensions.x) # Decodes the horizontal page-grid coordinate without allocating a Vector2i.
		var frontier_z: int = floori(float(encoded_frontier_cell) / float(page_dimensions.x)) # Decodes the vertical page-grid coordinate.
		for boundary_index: int in range(0, boundary_samples.size(), 2): # Aligns representative candidate contour points against the existing cluster frontier.
			var center_x: int = frontier_x - boundary_samples[boundary_index] # Calculates the page-grid sticker center required to place this contour sample on the frontier cell.
			var center_z: int = frontier_z - boundary_samples[boundary_index + 1] # Calculates the corresponding vertical sticker center.
			if center_x + min_x < 0 or center_x + max_x >= page_dimensions.x or center_z + min_z < 0 or center_z + max_z >= page_dimensions.y: # Rejects candidates whose cached silhouette bounds cross a page edge.
				continue # Avoids walking any mask cells for a candidate that cannot possibly fit.
			var center_index: int = center_z * page_dimensions.x + center_x # Encodes the valid candidate center into the deduplication grid.
			if tested_centers[center_index] != 0: # Detects an equivalent center already produced by another contour alignment.
				continue # Avoids repeating the same exact collision test.
			tested_centers[center_index] = 1 # Marks the center as evaluated for the canonical orientation.
			if not _fits(mask_cells, center_x, center_z, page_dimensions.x, occupancy): # Performs exact source-alpha overlap testing only after all cheap rejection stages pass.
				continue # Advances immediately when any physical sticker cell overlaps existing material.
			var contact_score: int = _calculate_contact_score(boundary_samples, center_x, center_z, page_dimensions, occupancy) # Estimates edge contact from the same distributed contour samples used for fast candidate generation.
			var candidate_distance: float = Vector2(float(center_x), float(center_z)).distance_to(occupancy_center) # Measures cluster spread for tie-breaking after contact strength.
			var score: float = float(contact_score) * 10000.0 - candidate_distance # Prioritizes physical edge contact overwhelmingly over small compactness differences.
			if score > best_score: # Replaces this orientation's result when the candidate nests more tightly.
				best_score = score # Stores the stronger orientation score.
				best_result = _make_result(page_bounds, Vector2i(center_x, center_z), absolute_page_index) # Converts the winning grid center back into persistent upright world placement coordinates.
				best_result["score"] = score # Stores internal score metadata for cross-angle and cross-page comparisons.
	return best_result # Returns the strongest legal contact candidate for the canonical source orientation.

func _build_page_occupancy(existing_placements: Array[Dictionary], absolute_page_index: int, page_bounds: Rect2, page_dimensions: Vector2i) -> PackedByteArray: # Rasterizes one virtual page into a contiguous byte occupancy grid.
	var occupancy: PackedByteArray = PackedByteArray() # Allocates compact page storage with one byte per grid cell.
	occupancy.resize(page_dimensions.x * page_dimensions.y) # Sizes the grid once so overlap checks become direct row-major indexing.
	for placement: Dictionary in existing_placements: # Visits each persisted physical sticker record once.
		if int(placement.get("page", 0)) != absolute_page_index: # Skips every sticker attached to another virtual page.
			continue # Avoids unnecessary mask retrieval and rasterization work.
		var world_xz: Vector2 = Vector2(float(placement.get("x", 0.0)), float(placement.get("z", 0.0))) # Restores the sticker center on the visible page coordinate system.
		var sticker_path: String = str(placement.get("path", "")) # Retrieves the artwork resource used to rebuild the exact silhouette.
		var sticker_size: Vector2 = Vector2(float(placement.get("size_x", 1.0)), float(placement.get("size_y", 1.0))) # Restores the physical dimensions used by this sticker copy.
		var mask_data: Dictionary = _get_canonical_mask(sticker_path, sticker_size) # Retrieves the cached upright silhouette because every persisted book sticker is canonical.
		var mask_cells: PackedInt32Array = mask_data.get("cells", PackedInt32Array()) # Retrieves interleaved local occupancy coordinates.
		var center_cell: Vector2i = _world_to_cell(page_bounds, world_xz) # Converts the persisted world center into page-grid coordinates.
		for cell_index: int in range(0, mask_cells.size(), 2): # Walks the cached silhouette using compact integer pairs.
			var page_x: int = center_cell.x + mask_cells[cell_index] # Converts one local silhouette x offset into page-grid coordinates.
			var page_z: int = center_cell.y + mask_cells[cell_index + 1] # Converts one local silhouette z offset into page-grid coordinates.
			if page_x < 0 or page_z < 0 or page_x >= page_dimensions.x or page_z >= page_dimensions.y: # Handles manually placed stickers that extend beyond conservative auto-pack bounds.
				continue # Clips only the out-of-grid raster cell while retaining valid physical material.
			occupancy[page_z * page_dimensions.x + page_x] = 1 # Marks the physical source-alpha material as occupied in contiguous page memory.
	return occupancy # Returns the complete compact page raster.

func _get_canonical_mask(sticker_path: String, sticker_size: Vector2) -> Dictionary: # Returns cached packed collision metadata for the sticker's immutable source orientation.
	var cache_key: String = "%s|%.4f|%.4f" % [sticker_path, sticker_size.x, sticker_size.y] # Builds a stable key covering artwork and physical size only because book yaw is forbidden.
	if _canonical_mask_cache.has(cache_key): # Reuses masks across duplicate stickers, occupancy reconstruction, and repeated capacity checks.
		var cached_mask: Dictionary = _canonical_mask_cache[cache_key] # Narrows the cached Variant to the expected mask dictionary.
		return cached_mask # Returns the cached structure without copying packed arrays.
	var base_cells: PackedInt32Array = _get_base_mask(sticker_path, sticker_size) # Retrieves the cached source-alpha occupancy cells in their source orientation.
	var canonical_set: Dictionary = {} # Deduplicates any source cells that quantize onto the same centered coarse-grid coordinate.
	var min_x: int = 2147483647 # Starts the cached silhouette bounds above any practical local x coordinate.
	var max_x: int = -2147483648 # Starts the cached silhouette bounds below any practical local x coordinate.
	var min_z: int = 2147483647 # Starts the cached silhouette bounds above any practical local z coordinate.
	var max_z: int = -2147483648 # Starts the cached silhouette bounds below any practical local z coordinate.
	for cell_index: int in range(0, base_cells.size(), 2): # Visits each canonical physical cell once without trigonometry or rotation allocation.
		var cell_x: int = base_cells[cell_index] # Retrieves the canonical local horizontal occupancy offset.
		var cell_z: int = base_cells[cell_index + 1] # Retrieves the paired canonical local vertical occupancy offset.
		var encoded_key: int = _encode_signed_cell(cell_x, cell_z) # Encodes the signed local coordinate into one compact construction key.
		if canonical_set.has(encoded_key): # Detects duplicate coordinates caused by coarse source centering.
			continue # Keeps one physical occupancy entry for each coarse cell.
		canonical_set[encoded_key] = Vector2i(cell_x, cell_z) # Stores the unique canonical cell for boundary extraction.
		min_x = mini(min_x, cell_x) # Expands the cached left silhouette bound.
		max_x = maxi(max_x, cell_x) # Expands the cached right silhouette bound.
		min_z = mini(min_z, cell_z) # Expands the cached top silhouette bound.
		max_z = maxi(max_z, cell_z) # Expands the cached bottom silhouette bound.
	var canonical_cells: PackedInt32Array = PackedInt32Array() # Stores unique canonical occupancy as interleaved integer x/z pairs.
	for canonical_value: Variant in canonical_set.values(): # Visits each unique canonical cell once after deduplication.
		var canonical_cell: Vector2i = canonical_value # Narrows the dictionary value back into its local grid coordinate.
		canonical_cells.append(canonical_cell.x) # Stores the local horizontal occupancy offset.
		canonical_cells.append(canonical_cell.y) # Stores the paired local vertical occupancy offset.
	if canonical_cells.is_empty(): # Handles malformed artwork defensively before constructing invalid extreme bounds.
		return {} # Reports an unusable silhouette to the caller without caching invalid metadata.
	var boundary_cells: PackedInt32Array = _extract_boundary(canonical_set) # Extracts the complete coarse silhouette edge for contour sampling.
	var boundary_samples: PackedInt32Array = _build_boundary_samples(boundary_cells) # Reduces the contour to distributed fixed-size samples used by the hot search loop.
	var result: Dictionary = {"cells": canonical_cells, "boundary": boundary_cells, "boundary_samples": boundary_samples, "min_x": min_x, "max_x": max_x, "min_z": min_z, "max_z": max_z} # Packages cached collision and early-rejection metadata.
	_canonical_mask_cache[cache_key] = result # Stores the immutable source-orientation result for future duplicate and occupancy operations.
	return result # Returns the generated canonical mask data.

func _get_base_mask(sticker_path: String, sticker_size: Vector2) -> PackedInt32Array: # Builds an unrotated packed occupancy mask directly from the supplied artwork alpha.
	var cache_key: String = "%s|%.4f|%.4f" % [sticker_path, sticker_size.x, sticker_size.y] # Builds a stable per-design-and-size source-mask cache key.
	if _base_mask_cache.has(cache_key): # Reuses the expensive texture-derived silhouette whenever possible.
		var cached_mask: PackedInt32Array = _base_mask_cache[cache_key] # Narrows the cached Variant to the expected packed occupancy type.
		return cached_mask # Returns cached packed occupancy without copying it.
	var artwork_cells_x: int = maxi(1, ceili(sticker_size.x / GRID_CELL_SIZE)) # Converts physical artwork width into coarse alpha-sampling columns.
	var artwork_cells_z: int = maxi(1, ceili(sticker_size.y / GRID_CELL_SIZE)) # Converts physical artwork height into coarse alpha-sampling rows.
	var source_set: Dictionary = {} # Stores coarse occupied cells from the source artwork alpha exactly as supplied.
	var texture_resource: Resource = ResourceLoader.load(sticker_path, "Texture2D") # Loads artwork through Godot's resource cache only while creating an uncached mask.
	if texture_resource is Texture2D: # Uses real artwork alpha whenever the imported resource is a readable texture.
		var sticker_texture: Texture2D = texture_resource as Texture2D # Narrows the validated resource to Texture2D.
		var source_image: Image = sticker_texture.get_image() # Reads source pixels once per unique design-and-size mask.
		if source_image != null and not source_image.is_empty(): # Verifies that CPU image data is available.
			var image_width: int = maxi(source_image.get_width(), 1) # Stores a safe source width for normalized alpha sampling.
			var image_height: int = maxi(source_image.get_height(), 1) # Stores a safe source height for normalized alpha sampling.
			for cell_z: int in range(artwork_cells_z): # Samples each coarse physical artwork row once.
				var sample_y: int = clampi(int((float(cell_z) + 0.5) / float(artwork_cells_z) * float(image_height)), 0, image_height - 1) # Maps the coarse row into source image pixels.
				for cell_x: int in range(artwork_cells_x): # Samples each coarse physical artwork column once.
					var sample_x: int = clampi(int((float(cell_x) + 0.5) / float(artwork_cells_x) * float(image_width)), 0, image_width - 1) # Maps the coarse column into source image pixels.
					if source_image.get_pixel(sample_x, sample_y).a > ALPHA_THRESHOLD: # Keeps only visible artwork material above the physical alpha cutoff.
						source_set[Vector2i(cell_x, cell_z)] = true # Marks this coarse artwork cell as physical sticker material.
	if source_set.is_empty(): # Provides a deterministic fallback when source alpha cannot be read.
		for fallback_z: int in range(artwork_cells_z): # Fills every coarse row of the artwork rectangle.
			for fallback_x: int in range(artwork_cells_x): # Fills every coarse column of the artwork rectangle.
				source_set[Vector2i(fallback_x, fallback_z)] = true # Treats the entire artwork rectangle as physical material.
	var source_center: Vector2 = Vector2(float(artwork_cells_x - 1), float(artwork_cells_z - 1)) * 0.5 # Calculates the artwork center before converting occupied cells into signed local offsets.
	var centered_cells: PackedInt32Array = PackedInt32Array() # Stores interleaved signed x/z occupancy coordinates centered around the sticker.
	for source_key: Variant in source_set.keys(): # Visits every source-alpha physical cell once.
		var source_cell: Vector2i = source_key # Narrows the dictionary key for centered coordinate conversion.
		centered_cells.append(roundi(float(source_cell.x) - source_center.x)) # Stores the signed local horizontal occupancy offset.
		centered_cells.append(roundi(float(source_cell.y) - source_center.y)) # Stores the paired signed local vertical occupancy offset.
	_base_mask_cache[cache_key] = centered_cells # Caches the texture-derived packed mask for every future placement operation.
	return centered_cells # Returns the complete unrotated source-alpha silhouette.

func _extract_boundary(cell_set: Dictionary) -> PackedInt32Array: # Extracts occupied cells touching at least one empty cardinal neighbor.
	var boundary: PackedInt32Array = PackedInt32Array() # Stores the complete silhouette edge as interleaved signed x/z pairs.
	var neighbors: Array[Vector2i] = [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.UP, Vector2i.DOWN] # Defines the four cardinal offsets sufficient for coarse edge detection.
	for cell_value: Variant in cell_set.values(): # Visits every occupied local silhouette cell once.
		var cell: Vector2i = cell_value # Narrows the stored local coordinate.
		for neighbor: Vector2i in neighbors: # Tests whether any cardinal direction leaves the occupied silhouette.
			if not cell_set.has(_encode_signed_cell(cell.x + neighbor.x, cell.y + neighbor.y)): # Detects an adjacent empty cell outside the sticker material.
				boundary.append(cell.x) # Stores the edge cell horizontal offset.
				boundary.append(cell.y) # Stores the paired edge cell vertical offset.
				break # Stops neighbor checks after the cell is known to belong to the boundary.
	return boundary # Returns the complete packed coarse contour.

func _build_boundary_samples(boundary_cells: PackedInt32Array) -> PackedInt32Array: # Reduces a potentially large contour to distributed radial support samples used by the hot candidate loop.
	var samples: PackedInt32Array = PackedInt32Array() # Stores selected contour points as interleaved x/z pairs.
	if boundary_cells.is_empty(): # Handles malformed or empty masks defensively.
		return samples # Returns an empty sample set so the caller rejects the orientation safely.
	var best_radius_by_bucket: PackedFloat32Array = PackedFloat32Array() # Stores the farthest contour radius currently selected for each angular bucket.
	best_radius_by_bucket.resize(MAX_BOUNDARY_SAMPLES) # Creates one radial support slot per requested contour direction.
	var best_x_by_bucket: PackedInt32Array = PackedInt32Array() # Stores the selected horizontal contour coordinate for each angular bucket.
	best_x_by_bucket.resize(MAX_BOUNDARY_SAMPLES) # Matches the configured directional bucket count.
	var best_z_by_bucket: PackedInt32Array = PackedInt32Array() # Stores the selected vertical contour coordinate for each angular bucket.
	best_z_by_bucket.resize(MAX_BOUNDARY_SAMPLES) # Matches the configured directional bucket count.
	var bucket_used: PackedByteArray = PackedByteArray() # Tracks which angular buckets received at least one contour cell.
	bucket_used.resize(MAX_BOUNDARY_SAMPLES) # Creates one compact used-state byte per bucket.
	for boundary_index: int in range(0, boundary_cells.size(), 2): # Visits each complete contour cell once during cache construction.
		var cell_x: int = boundary_cells[boundary_index] # Retrieves the signed local horizontal contour coordinate.
		var cell_z: int = boundary_cells[boundary_index + 1] # Retrieves the paired signed local vertical contour coordinate.
		var angle: float = atan2(float(cell_z), float(cell_x)) + PI # Converts the contour direction into a positive zero-to-two-pi range.
		var bucket_index: int = clampi(floori(angle / TAU * float(MAX_BOUNDARY_SAMPLES)), 0, MAX_BOUNDARY_SAMPLES - 1) # Maps the contour direction into one fixed angular bucket.
		var radius_squared: float = float(cell_x * cell_x + cell_z * cell_z) # Uses squared radius to avoid square roots while selecting the outer support point.
		if bucket_used[bucket_index] == 0 or radius_squared > best_radius_by_bucket[bucket_index]: # Keeps the outermost contour point in each direction.
			bucket_used[bucket_index] = 1 # Marks this angular direction as represented.
			best_radius_by_bucket[bucket_index] = radius_squared # Stores the stronger support radius.
			best_x_by_bucket[bucket_index] = cell_x # Stores the selected support x coordinate.
			best_z_by_bucket[bucket_index] = cell_z # Stores the selected support z coordinate.
	for bucket_index: int in range(MAX_BOUNDARY_SAMPLES): # Emits used directional supports in deterministic angular order.
		if bucket_used[bucket_index] == 0: # Skips directions where the coarse silhouette had no boundary sample.
			continue # Avoids adding artificial zero coordinates.
		samples.append(best_x_by_bucket[bucket_index]) # Stores the selected support horizontal offset.
		samples.append(best_z_by_bucket[bucket_index]) # Stores the paired support vertical offset.
	return samples # Returns the compact distributed contour used by placement searches.

func _build_frontier(occupancy: PackedByteArray, page_dimensions: Vector2i) -> PackedInt32Array: # Finds empty page cells directly adjacent to existing sticker material using one linear raster scan.
	var frontier: PackedInt32Array = PackedInt32Array() # Stores row-major encoded frontier cells without hash-set allocations.
	var width: int = page_dimensions.x # Stores the page-grid width for row-major indexing.
	var height: int = page_dimensions.y # Stores the page-grid height for bounded neighbor scans.
	for cell_z: int in range(height): # Scans each page-grid row once.
		for cell_x: int in range(width): # Scans each page-grid column once.
			var cell_index: int = cell_z * width + cell_x # Encodes the current page cell into contiguous occupancy memory.
			if occupancy[cell_index] != 0: # Rejects material already occupied by an existing sticker.
				continue # Frontier cells must be empty placement space.
			var touches_occupied: bool = false # Tracks whether any immediate neighbor belongs to the existing cluster.
			for offset_z: int in range(-1, 2): # Checks the three vertical neighbor rows around the empty cell.
				if touches_occupied: # Stops additional row work as soon as one occupied neighbor is found.
					break # Leaves the neighborhood loop early.
				var neighbor_z: int = cell_z + offset_z # Calculates the candidate neighbor row.
				if neighbor_z < 0 or neighbor_z >= height: # Rejects rows outside the usable page raster.
					continue # Keeps the frontier test inside page memory.
				for offset_x: int in range(-1, 2): # Checks the three horizontal neighbor columns around the empty cell.
					if offset_x == 0 and offset_z == 0: # Skips the empty cell itself.
						continue # Only surrounding cells can establish cluster contact.
					var neighbor_x: int = cell_x + offset_x # Calculates the candidate neighbor column.
					if neighbor_x < 0 or neighbor_x >= width: # Rejects columns outside the usable page raster.
						continue # Keeps occupancy indexing valid.
					if occupancy[neighbor_z * width + neighbor_x] != 0: # Detects existing sticker material beside the empty cell.
						touches_occupied = true # Marks this empty cell as part of the cluster frontier.
						break # Stops neighborhood checks after the first contact.
			if touches_occupied: # Emits only empty cells that directly touch existing material.
				frontier.append(cell_index) # Stores the compact row-major page cell index.
	return frontier # Returns the complete existing-cluster frontier.

func _fits(mask_cells: PackedInt32Array, center_x: int, center_z: int, page_width: int, occupancy: PackedByteArray) -> bool: # Performs exact overlap testing after cached bounds have already proved the silhouette is inside the page.
	for cell_index: int in range(0, mask_cells.size(), 2): # Walks each occupied source-alpha cell using packed integer pairs.
		var page_x: int = center_x + mask_cells[cell_index] # Converts the local silhouette x offset into a page-grid column.
		var page_z: int = center_z + mask_cells[cell_index + 1] # Converts the local silhouette z offset into a page-grid row.
		if occupancy[page_z * page_width + page_x] != 0: # Detects physical overlap with existing sticker material using direct contiguous memory lookup.
			return false # Stops immediately on the first overlapping cell.
	return true # Confirms that every physical silhouette cell occupies free page space.

func _calculate_contact_score(boundary_samples: PackedInt32Array, center_x: int, center_z: int, page_dimensions: Vector2i, occupancy: PackedByteArray) -> int: # Estimates edge adjacency using a bounded distributed contour sample rather than the complete silhouette boundary.
	var contact_score: int = 0 # Accumulates immediate neighboring occupied cells as the tight-packing objective.
	var width: int = page_dimensions.x # Stores page width for row-major indexing.
	var height: int = page_dimensions.y # Stores page height for neighbor bounds checks.
	for boundary_index: int in range(0, boundary_samples.size(), 2): # Visits each distributed contour support point once.
		var page_x: int = center_x + boundary_samples[boundary_index] # Converts the local contour x offset into page coordinates.
		var page_z: int = center_z + boundary_samples[boundary_index + 1] # Converts the local contour z offset into page coordinates.
		for offset_z: int in range(-1, 2): # Checks neighboring rows around the contour point.
			var neighbor_z: int = page_z + offset_z # Calculates one neighboring row.
			if neighbor_z < 0 or neighbor_z >= height: # Rejects neighbors outside the usable page raster.
				continue # Keeps direct occupancy indexing valid.
			for offset_x: int in range(-1, 2): # Checks neighboring columns around the contour point.
				if offset_x == 0 and offset_z == 0: # Skips the candidate sticker cell itself.
					continue # Only surrounding material counts as physical contact.
				var neighbor_x: int = page_x + offset_x # Calculates one neighboring column.
				if neighbor_x < 0 or neighbor_x >= width: # Rejects neighbors outside the usable page raster.
					continue # Keeps occupancy indexing valid.
				if occupancy[neighbor_z * width + neighbor_x] != 0: # Detects close contact with existing sticker material.
					contact_score += 1 # Rewards this candidate for sharing more perimeter with the current cluster.
	return contact_score # Returns the bounded contour-contact estimate used for ranking legal placements.

func _find_fallback_placement(sticker_path: String, sticker_size: Vector2, existing_placements: Array[Dictionary], spread_index: int) -> Dictionary: # Performs a sparse upright-only grid recovery scan when contour nesting cannot expose any legal fit.
	for local_page_index: int in range(StickerBookLayout.PAGES_PER_SPREAD): # Checks both active pages before declaring the spread full.
		var absolute_page_index: int = StickerBookLayout.get_absolute_page_index(spread_index, local_page_index) # Resolves the persistent page represented by this side.
		var page_bounds: Rect2 = StickerBookLayout.get_page_bounds(local_page_index) # Retrieves the usable physical page rectangle.
		var page_dimensions: Vector2i = _get_page_grid_dimensions(page_bounds) # Converts the page into occupancy-grid dimensions.
		var occupancy: PackedByteArray = _build_page_occupancy(existing_placements, absolute_page_index, page_bounds, page_dimensions) # Reconstructs compact page occupancy for exact overlap checks.
		var mask_data: Dictionary = _get_canonical_mask(sticker_path, sticker_size) # Retrieves the one canonical source-alpha silhouette without generating alternate rotations.
		var mask_cells: PackedInt32Array = mask_data.get("cells", PackedInt32Array()) # Retrieves the exact upright source-alpha occupancy pairs.
		var min_x: int = int(mask_data.get("min_x", 0)) # Retrieves the cached left local bound.
		var max_x: int = int(mask_data.get("max_x", 0)) # Retrieves the cached right local bound.
		var min_z: int = int(mask_data.get("min_z", 0)) # Retrieves the cached top local bound.
		var max_z: int = int(mask_data.get("max_z", 0)) # Retrieves the cached bottom local bound.
		var start_x: int = maxi(-min_x, 0) # Starts scanning at the first center whose left bound remains on the page.
		var end_x: int = mini(page_dimensions.x - 1 - max_x, page_dimensions.x - 1) # Ends scanning at the last center whose right bound remains on the page.
		var start_z: int = maxi(-min_z, 0) # Starts scanning at the first center whose top bound remains on the page.
		var end_z: int = mini(page_dimensions.y - 1 - max_z, page_dimensions.y - 1) # Ends scanning at the last center whose bottom bound remains on the page.
		if start_x > end_x or start_z > end_z: # Detects an upright sticker physically larger than this usable page rectangle.
			continue # Advances to the opposite page without scanning impossible centers.
		for cell_z: int in range(start_z, end_z + 1, FALLBACK_GRID_STRIDE): # Scans a sparse subset of legal page rows instead of every coarse cell.
			for cell_x: int in range(start_x, end_x + 1, FALLBACK_GRID_STRIDE): # Scans a sparse subset of legal page columns.
				if _fits(mask_cells, cell_x, cell_z, page_dimensions.x, occupancy): # Accepts the first exact zero-overlap upright silhouette fit found by recovery scanning.
					return _make_result(page_bounds, Vector2i(cell_x, cell_z), absolute_page_index) # Converts the legal recovery center into a canonical persistent placement.
	return {} # Reports that neither active page exposed a legal upright fit so the caller can append a fresh spread.

func _find_centered_empty_page_placement(sticker_path: String, sticker_size: Vector2, page_bounds: Rect2, page_dimensions: Vector2i, absolute_page_index: int) -> Dictionary: # Finds a centered legal canonical placement for a completely blank page with almost no search cost.
	var center_cell: Vector2i = Vector2i(page_dimensions.x >> 1, page_dimensions.y >> 1) # Starts the first sticker cluster at the visual center of the usable page.
	var mask_data: Dictionary = _get_canonical_mask(sticker_path, sticker_size) # Retrieves only the original artwork orientation used by every book sticker.
	var min_x: int = int(mask_data.get("min_x", 0)) # Retrieves the cached left local bound.
	var max_x: int = int(mask_data.get("max_x", 0)) # Retrieves the cached right local bound.
	var min_z: int = int(mask_data.get("min_z", 0)) # Retrieves the cached top local bound.
	var max_z: int = int(mask_data.get("max_z", 0)) # Retrieves the cached bottom local bound.
	if center_cell.x + min_x < 0 or center_cell.x + max_x >= page_dimensions.x or center_cell.y + min_z < 0 or center_cell.y + max_z >= page_dimensions.y: # Rejects a canonical sticker whose complete source-alpha silhouette crosses a page edge.
		return {} # Reports an oversized sticker because rotation is intentionally unavailable inside the book.
	return _make_result(page_bounds, center_cell, absolute_page_index) # Returns the centered canonical placement immediately.

func _calculate_occupancy_center(occupancy: PackedByteArray, page_dimensions: Vector2i, occupancy_count: int) -> Vector2: # Calculates the occupied-cell centroid used only as a compactness tie-breaker.
	if occupancy_count <= 0: # Handles an empty page defensively without dividing by zero.
		return Vector2(float(page_dimensions.x) * 0.5, float(page_dimensions.y) * 0.5) # Uses page center as the neutral fallback.
	var accumulated_x: float = 0.0 # Accumulates occupied horizontal grid coordinates.
	var accumulated_z: float = 0.0 # Accumulates occupied vertical grid coordinates.
	for cell_index: int in range(occupancy.size()): # Scans the compact page raster once.
		if occupancy[cell_index] == 0: # Skips empty page cells.
			continue # Only physical sticker material contributes to the cluster center.
		accumulated_x += float(posmod(cell_index, page_dimensions.x)) # Adds the occupied cell horizontal coordinate.
		accumulated_z += float(floori(float(cell_index) / float(page_dimensions.x))) # Adds the occupied cell vertical coordinate.
	return Vector2(accumulated_x / float(occupancy_count), accumulated_z / float(occupancy_count)) # Returns the mean occupied grid position.

func _count_occupied_cells(occupancy: PackedByteArray) -> int: # Counts physical occupied cells in one compact page raster.
	var count: int = 0 # Accumulates occupied bytes.
	for value: int in occupancy: # Walks the contiguous raster once.
		count += value # Adds zero for empty cells and one for occupied cells.
	return count # Returns the total physical occupancy-cell count.

func _encode_signed_cell(cell_x: int, cell_z: int) -> int: # Encodes a small signed local grid coordinate into one collision-free integer dictionary key for mask construction.
	return ((cell_x + 32768) << 16) | ((cell_z + 32768) & 0xFFFF) # Packs both biased signed sixteen-bit coordinates into one integer.

func _get_page_grid_dimensions(page_bounds: Rect2) -> Vector2i: # Converts a usable page rectangle into stable integer occupancy dimensions.
	return Vector2i(maxi(1, floori(page_bounds.size.x / GRID_CELL_SIZE)), maxi(1, floori(page_bounds.size.y / GRID_CELL_SIZE))) # Returns at least one coarse cell on each axis.

func _world_to_cell(page_bounds: Rect2, world_xz: Vector2) -> Vector2i: # Converts visible page world x/z coordinates into the nearest page-local occupancy center.
	var local_position: Vector2 = world_xz - page_bounds.position # Moves the world point into page-local coordinates beginning at the usable rectangle origin.
	return Vector2i(roundi(local_position.x / GRID_CELL_SIZE), roundi(local_position.y / GRID_CELL_SIZE)) # Snaps the physical center to the nearest packing cell.

func _cell_to_world(page_bounds: Rect2, page_cell: Vector2i) -> Vector2: # Converts a page-local occupancy center back into visible world x/z coordinates.
	return page_bounds.position + Vector2(float(page_cell.x) * GRID_CELL_SIZE, float(page_cell.y) * GRID_CELL_SIZE) # Restores the physical point represented by the coarse grid cell.

func _make_result(page_bounds: Rect2, center_cell: Vector2i, absolute_page_index: int) -> Dictionary: # Creates a compact upright persistent placement result from one winning grid candidate.
	var world_xz: Vector2 = _cell_to_world(page_bounds, center_cell) # Converts the occupancy center back into visible page x/z coordinates.
	return {"page": absolute_page_index, "x": world_xz.x, "z": world_xz.y, "yaw": 0.0} # Returns the absolute page, physical center, and canonical source-artwork orientation required by book state.
