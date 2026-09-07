class_name StickerBookLayout
extends RefCounted

const PAGE_SURFACE_Y: float = 0.235 # Defines the world height used by every flat sticker attachment and pointer-plane calculation.
const STICKER_BASE_OFFSET: float = 0.012 # Keeps the first sticker layer visibly above the page surface without depth fighting.
const STACK_STEP: float = 0.0012 # Defines the tiny paper-thickness increment used to order overlapping stickers physically.
const PAGES_PER_SPREAD: int = 2 # Defines the fixed left/right page count visible in one open book spread.
const LEFT_PAGE_BOUNDS: Rect2 = Rect2(-5.11, -3.15, 4.86, 6.30) # Defines the usable x/z rectangle inside the visible left page while preserving margins and the spine gap.
const RIGHT_PAGE_BOUNDS: Rect2 = Rect2(0.25, -3.15, 4.86, 6.30) # Defines the usable x/z rectangle inside the visible right page while preserving margins and the spine gap.

static func get_page_bounds(local_page_index: int) -> Rect2: # Returns one visible left/right page rectangle in x/z coordinates for placement and packing.
	if local_page_index == 0: # Selects the visible left page when the first local page index is requested.
		return LEFT_PAGE_BOUNDS # Returns the left page's placement-safe x/z rectangle.
	return RIGHT_PAGE_BOUNDS # Returns the visible right page for every other validated local page index.

static func get_local_page_index(world_xz: Vector2) -> int: # Finds which visible left/right page contains one world-space x/z point.
	if LEFT_PAGE_BOUNDS.has_point(world_xz): # Tests the point against the visible left page's placement-safe area.
		return 0 # Identifies the left page within the active spread.
	if RIGHT_PAGE_BOUNDS.has_point(world_xz): # Tests the point against the visible right page's placement-safe area.
		return 1 # Identifies the right page within the active spread.
	return -1 # Reports that the point lies outside both usable visible page surfaces.

static func get_page_index(world_xz: Vector2) -> int: # Preserves the original helper name for code that only needs the visible left/right page side.
	return get_local_page_index(world_xz) # Returns the visible page side without assigning an absolute book page number.

static func get_absolute_page_index(spread_index: int, local_page_index: int) -> int: # Converts an open spread plus visible page side into a persistent absolute page number.
	return maxi(spread_index, 0) * PAGES_PER_SPREAD + clampi(local_page_index, 0, PAGES_PER_SPREAD - 1) # Returns a stable zero-based absolute book page index.

static func get_spread_index_for_page(page_index: int) -> int: # Converts a persistent absolute page number into its containing open-spread index.
	return floori(float(maxi(page_index, 0)) / float(PAGES_PER_SPREAD)) # Returns the zero-based spread containing the requested absolute page.

static func get_local_page_index_for_absolute_page(page_index: int) -> int: # Converts a persistent absolute page number into visible left/right page side.
	return posmod(maxi(page_index, 0), PAGES_PER_SPREAD) # Returns zero for left pages and one for right pages.

static func get_first_page_index_for_spread(spread_index: int) -> int: # Returns the absolute left-page number owned by one spread.
	return maxi(spread_index, 0) * PAGES_PER_SPREAD # Returns the first zero-based page index for the requested spread.

static func get_stack_height(stack_order: int) -> float: # Converts persistent logical stacking order into the physical world y attachment height.
	return PAGE_SURFACE_Y + STICKER_BASE_OFFSET + float(maxi(stack_order, 0)) * STACK_STEP # Returns a stable page-relative paper layer height.
