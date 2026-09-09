class_name CollectionBrowser extends MarginContainer # Owns cached collection cards, search, filtering, and collection-first placement.

const CARD_SCENE: PackedScene = preload("res://scenes/ui/collection_item.tscn") # Reuses an editor-authored native button card.

@onready var _grid: GridContainer = %grid as GridContainer # Arranges cards within the scrollable content area.
@onready var _scroll: ScrollContainer = %scroll as ScrollContainer # Preserves scroll position and follows keyboard focus.
@onready var _search: LineEdit = %search as LineEdit # Supplies native editable search text.
@onready var _empty: Control = %empty_state as Control # Explains filters with no matching results.
@onready var _summary: Label = %summary as Label # Shows the current result count and available interaction.
@onready var _completion: Label = %completion as Label # Shows unique collection completion.
@onready var _progress: ProgressBar = %progress as ProgressBar # Visualizes progress across the whole catalogue.

var _economy: StickerEconomy # Reads lifetime ownership without modifying progression.
var _catalog: StickerCatalog # Supplies discovered resource paths.
var _place: Callable = Callable() # Starts book placement for one available collected edition copy.
var _available_count: Callable = Callable() # Reports how many copies of an exact edition remain available to place.
var _cards: Array[CollectionItem] = [] # Keeps instantiated normal and owned-special cards across route changes.
var _card_keys: Dictionary[String, bool] = {} # Prevents duplicate card construction when a special edition is discovered later.
var _filters: Array[GameButton] = [] # Holds the native ownership-tab controls.
var _filter_index: int = 0 # Remembers the selected ownership view.
var _query: String = "" # Caches the last applied normalized query.
var _refresh_elapsed: float = 0.0 # Throttles signal-free text and size checks while visible.

func configure(economy: StickerEconomy, catalog: StickerCatalog, place: Callable, available_count: Callable) -> void: # Binds model dependencies and collection placement actions.
	_economy = economy # Retains the authoritative edition-aware ownership model.
	_catalog = catalog # Retains the discovered design catalogue.
	_place = place # Retains the controller-owned placement entry point.
	_available_count = available_count # Retains the controller-owned availability calculation.
	_filters = [%all_filter as GameButton, %owned_filter as GameButton, %missing_filter as GameButton] # Establishes the filter order.
	for index: int in range(_filters.size()): # Binds each tab once without signals.
		_filters[index].bind_action(_set_filter.bind(index)) # Routes native activation to its ownership filter.
	(%clear_filter as GameButton).bind_action(_clear_filters) # Gives empty results a recovery action.

func refresh() -> void: # Updates normal cards and dynamically adds newly discovered special-edition cards.
	for index: int in range(_catalog.get_sticker_count()): # Visits every authored design once to guarantee its normal collection entry exists.
		var artwork_path: String = _catalog.get_sticker_path(index) # Reads the stable authored artwork identity.
		_ensure_card(artwork_path) # Keeps one normal card visible even before that design is discovered.
		var special_key: String = StickerVariant.make_key(artwork_path, true) # Builds the separate collection identity for this design's special edition.
		if _economy.get_owned_count(special_key) > 0: # Adds a special card only after the player has actually pulled at least one special copy.
			_ensure_card(special_key) # Makes the rare edition appear separately without doubling undiscovered catalogue clutter.
	for card: CollectionItem in _cards: # Updates only small ownership fields after pack or book changes.
		var sticker_key: String = card.get_sticker_key() # Reads the exact normal or special identity once.
		card.refresh_count(_economy.get_owned_count(sticker_key), int(_available_count.call(sticker_key))) # Reflects lifetime ownership and copies of this exact edition not yet in the book.
	_completion.text = "%d / %d discovered" % [_economy.get_unique_owned_count(), _catalog.get_sticker_count()] # Keeps base collection completion independent from optional special editions.
	_progress.max_value = maxi(_catalog.get_sticker_count(), 1) # Handles an empty catalogue safely.
	_progress.value = _economy.get_unique_owned_count() # Updates collection completion by authored designs rather than editions.
	_apply_filter() # Restores the user's current query and tab.

func _ensure_card(sticker_key: String) -> void: # Builds one normal or special collection card exactly once.
	if _card_keys.has(sticker_key): # Rejects cards already constructed in this browser session.
		return # Reuses the cached card and imported texture.
	var artwork_path: String = StickerVariant.get_art_path(sticker_key) # Resolves the actual resource shared by both editions.
	var texture: Texture2D = load(artwork_path) as Texture2D # Reuses Godot's imported texture cache.
	if texture == null: # Handles a missing or invalid imported resource safely.
		return # Skips unavailable artwork while keeping the browser usable.
	var card: CollectionItem = CARD_SCENE.instantiate() as CollectionItem # Instantiates the reusable editor-authored card scene.
	_grid.add_child(card) # Adds the card to the native layout before configuration.
	card.configure(sticker_key, texture, _place) # Binds the exact edition identity to collection-first placement.
	_cards.append(card) # Retains the card for future ownership refreshes.
	_card_keys[sticker_key] = true # Records successful construction so later refreshes remain allocation-free.

func focus_search() -> void: # Establishes a useful focus target on entry.
	_search.grab_focus() # Makes collection search immediately available from the keyboard.

func _process(delta: float) -> void: # Watches text and available width only while the browser is visible.
	if not is_visible_in_tree() or _economy == null: # Avoids hidden-page polling and premature model reads.
		return # Leaves inactive collection content untouched.
	_refresh_elapsed += delta # Accumulates the lightweight polling interval.
	if _refresh_elapsed < 0.1: # Limits search and layout checks during normal rendering.
		return # Defers redundant work until the next short interval.
	_refresh_elapsed = 0.0 # Starts the next observation interval.
	var query: String = _search.text.strip_edges().to_lower() # Normalizes native LineEdit content.
	if query != _query: # Refilters only when the user changes the query.
		_query = query # Stores the query used by the cached cards.
		_apply_filter() # Applies search without recreating any nodes.
	var columns: int = maxi(1, int((_scroll.size.x - 16.0) / 168.0)) # Reserves scrollbar width when fitting cards.
	if _grid.columns != columns: # Avoids unnecessary container layout invalidations.
		_grid.columns = columns # Adapts the grid to the actual content width.

func _set_filter(index: int) -> void: # Selects one ownership tab and updates visible results.
	_filter_index = index # Remembers the tab across page visits.
	_apply_filter() # Applies the tab to the current search query.

func _clear_filters() -> void: # Recovers from an empty search result.
	_search.text = "" # Clears native editable search text.
	_query = "" # Clears the cached query immediately.
	_set_filter(0) # Restores the complete catalogue.
	_search.grab_focus() # Returns focus to a useful editing target.

func _apply_filter() -> void: # Updates visibility while preserving instantiated cards.
	var shown: int = 0 # Counts the current filtered results.
	for card: CollectionItem in _cards: # Evaluates cached data rather than artwork resources.
		card.visible = card.matches(_query, _filter_index) # Combines name search with ownership filtering.
		shown += int(card.visible) # Counts matching normal and discovered-special entries for the result summary.
	for index: int in range(_filters.size()): # Maintains mutually exclusive visual tab state.
		_filters[index].set_pressed_no_signal(index == _filter_index) # Updates state without signal-based routing.
	_empty.visible = shown == 0 # Shows recovery guidance only when no result exists.
	_scroll.visible = shown > 0 # Gives empty-state content the available page area.
	_summary.text = "%d entries · special editions appear separately after you pull one" % shown # Explains why rare special cards are additional collection entries.
