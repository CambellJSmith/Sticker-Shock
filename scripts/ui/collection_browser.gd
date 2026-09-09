class_name CollectionBrowser extends MarginContainer # Owns cached owned-collection cards, search, and collection-first placement.

const CARD_SCENE: PackedScene = preload("res://scenes/ui/collection_item.tscn") # Reuses an editor-authored native button card.
const PREMIUM_EDITIONS: Array[int] = [StickerVariant.EDITION_RAINBOW, StickerVariant.EDITION_SILVER, StickerVariant.EDITION_GOLD] # Defines premium editions tracked separately from normal copies.

@onready var _grid: GridContainer = %grid as GridContainer # Arranges owned sticker cards within the scrollable content area.
@onready var _scroll: ScrollContainer = %scroll as ScrollContainer # Preserves scroll position and follows keyboard focus.
@onready var _search: LineEdit = %search as LineEdit # Supplies native editable search text.
@onready var _empty: Control = %empty_state as Control # Explains when the player owns no matching stickers.
@onready var _summary: Label = %summary as Label # Shows the current owned result count.
@onready var _completion: Label = %completion as Label # Shows unique collection completion.
@onready var _progress: ProgressBar = %progress as ProgressBar # Visualizes progress across the whole authored catalogue.

var _economy: StickerEconomy # Reads current edition-aware ownership without modifying progression.
var _catalog: StickerCatalog # Supplies discovered authored sticker resources.
var _place: Callable = Callable() # Starts book placement for one available collected edition copy.
var _available_count: Callable = Callable() # Reports how many copies of an exact edition remain available to place.
var _cards: Array[CollectionItem] = [] # Keeps instantiated owned-collection cards cached across route changes.
var _card_keys: Dictionary[String, bool] = {} # Prevents duplicate card construction when ownership changes.
var _filters: Array[GameButton] = [] # Retains references to legacy ownership filter controls so they can stay hidden.
var _query: String = "" # Caches the last applied normalized search query.
var _refresh_elapsed: float = 0.0 # Throttles signal-free text and size checks while visible.

func configure(economy: StickerEconomy, catalog: StickerCatalog, place: Callable, available_count: Callable) -> void: # Binds model dependencies and collection placement actions.
	_economy = economy # Retains the authoritative edition-aware ownership model.
	_catalog = catalog # Retains the discovered authored sticker catalogue.
	_place = place # Retains the controller-owned placement entry point.
	_available_count = available_count # Retains the controller-owned availability calculation.
	_filters = [%all_filter as GameButton, %owned_filter as GameButton, %missing_filter as GameButton] # Finds the old catalogue filter controls once.
	for filter_button: GameButton in _filters: # Visits every obsolete ownership filter control.
		filter_button.visible = false # Hides all/owned/missing tabs because this page now always means currently owned stickers.
	(%clear_filter as GameButton).bind_action(_clear_search) # Lets the empty-state recovery action clear only the active search query.

func refresh() -> void: # Builds and updates cards only for sticker editions the player currently owns.
	for index: int in range(_catalog.get_sticker_count()): # Visits every authored design once to discover currently owned editions.
		var artwork_path: String = _catalog.get_sticker_path(index) # Reads the stable normal-edition artwork identity.
		if _economy.get_owned_count(artwork_path) > 0: # Checks whether at least one normal copy is currently owned.
			_ensure_card(artwork_path) # Creates the normal card only after ownership exists.
		for edition: int in PREMIUM_EDITIONS: # Checks rainbow, silver, and gold independently.
			var edition_key: String = StickerVariant.make_edition_key(artwork_path, edition) # Builds the exact persistent collection identity for this premium finish.
			if _economy.get_owned_count(edition_key) > 0: # Checks whether at least one copy of this exact premium edition is owned.
				_ensure_card(edition_key) # Creates the premium card only after the player actually owns it.
	for card: CollectionItem in _cards: # Refreshes every cached card after pack, sale, or book changes.
		var sticker_key: String = card.get_sticker_key() # Reads the exact normal or premium identity once.
		var owned_count: int = _economy.get_owned_count(sticker_key) # Reads current ownership for this exact edition.
		card.refresh_count(owned_count, int(_available_count.call(sticker_key))) # Reflects ownership and copies not already in the book.
		card.visible = owned_count > 0 # Immediately hides a cached edition if the player sells or otherwise loses their final copy.
	_completion.text = "%d / %d discovered" % [_economy.get_unique_owned_count(), _catalog.get_sticker_count()] # Keeps base-design completion independent from premium editions.
	_progress.max_value = maxi(_catalog.get_sticker_count(), 1) # Handles an empty catalogue safely.
	_progress.value = _economy.get_unique_owned_count() # Updates completion by authored designs rather than edition copies.
	_apply_filter() # Applies the current search while preserving the ownership-only rule.

func _ensure_card(sticker_key: String) -> void: # Builds one currently owned normal or premium collection card exactly once.
	if _card_keys.has(sticker_key): # Rejects cards already constructed in this browser session.
		return # Reuses the cached card and imported texture.
	var artwork_path: String = StickerVariant.get_art_path(sticker_key) # Resolves the actual PNG resource shared by every edition.
	var texture: Texture2D = load(artwork_path) as Texture2D # Reuses Godot's imported texture cache.
	if texture == null: # Handles a missing or invalid imported resource safely.
		return # Skips unavailable artwork while keeping the rest of the owned collection usable.
	var card: CollectionItem = CARD_SCENE.instantiate() as CollectionItem # Instantiates the reusable editor-authored card scene.
	_grid.add_child(card) # Adds the card to the native layout before configuration.
	card.configure(sticker_key, texture, _place) # Binds the exact edition identity to collection-first placement.
	_cards.append(card) # Retains the card for future ownership refreshes.
	_card_keys[sticker_key] = true # Records successful construction so later refreshes remain allocation-free.

func focus_search() -> void: # Establishes the keyboard/mouse-oriented collection entry target.
	_search.grab_focus() # Makes native collection search immediately available from a physical keyboard.

func focus_controller() -> void: # Establishes a controller-native entry target without trapping focus inside the native LineEdit.
	if _focus_first_actionable_card(): # Prioritizes the first visible sticker copy that can actually be placed.
		return # Leaves focus on useful collection content instead of controller text entry.
	if _empty.visible: # Handles an active search with no matching owned results.
		(%clear_filter as GameButton).grab_focus() # Gives the controller an immediate way to restore the full collection.
		return # Keeps focus away from hidden grid content.
	_search.grab_focus() # Falls back to controller-accessible search, where A opens the in-game on-screen keyboard.

func _process(delta: float) -> void: # Watches text and available width only while the collection browser is visible.
	if not is_visible_in_tree() or _economy == null: # Avoids hidden-page polling and premature model reads.
		return # Leaves inactive collection content untouched.
	_refresh_elapsed += delta # Accumulates the lightweight polling interval.
	if _refresh_elapsed < 0.1: # Limits search and layout checks during normal rendering.
		return # Defers redundant work until the next short interval.
	_refresh_elapsed = 0.0 # Starts the next observation interval.
	var query: String = _search.text.strip_edges().to_lower() # Normalizes native LineEdit content.
	if query != _query: # Refilters only when the user changes the query.
		_query = query # Stores the query used by the cached owned cards.
		_apply_filter() # Applies search without recreating any nodes.
	var columns: int = maxi(1, int((_scroll.size.x - 16.0) / 168.0)) # Reserves scrollbar width when fitting cards.
	if _grid.columns != columns: # Avoids unnecessary container layout invalidations.
		_grid.columns = columns # Adapts the grid to the actual content width.

func _clear_search() -> void: # Recovers from an empty ownership search result for mouse, keyboard, and controller users.
	_search.text = "" # Clears native editable search text.
	_query = "" # Clears the cached normalized query immediately.
	_apply_filter() # Restores every currently owned sticker edition.
	if not _focus_first_actionable_card(): # Prefers restored collection content when at least one copy can be placed.
		_search.grab_focus() # Falls back to the text field only when no actionable card exists.

func _apply_filter() -> void: # Applies text search while always excluding unowned sticker editions.
	var shown: int = 0 # Counts the currently visible owned results.
	for card: CollectionItem in _cards: # Evaluates cached cards without reloading artwork resources.
		var sticker_key: String = card.get_sticker_key() # Reads the exact edition identity for current ownership validation.
		var owns_copy: bool = _economy.get_owned_count(sticker_key) > 0 # Treats present inventory as the authoritative collection-membership rule.
		card.visible = owns_copy and card.matches(_query, 0) # Applies only text search after enforcing current ownership.
		shown += int(card.visible) # Counts matching owned normal and premium entries for the result summary.
	_empty.visible = shown == 0 # Shows recovery guidance only when no owned result matches.
	_scroll.visible = shown > 0 # Gives empty-state content the available page area when appropriate.
	_summary.text = "%d owned sticker editions" % shown # Describes the actual ownership-only result set.

func _focus_first_actionable_card() -> bool: # Selects the first visible enabled collection card and reports whether one was found.
	for card: CollectionItem in _cards: # Searches cached cards in stable creation/catalogue order.
		if card.visible and not card.disabled: # Requires both the active search result and at least one loose copy available to place.
			card.grab_focus() # Gives controller users an immediately useful physical-placement action.
			return true # Stops after establishing one deterministic entry target.
	return false # Reports that collection content currently has no actionable placement card.
