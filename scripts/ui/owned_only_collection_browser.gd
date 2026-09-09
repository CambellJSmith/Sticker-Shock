class_name OwnedOnlyCollectionBrowser
extends CollectionBrowser

func refresh() -> void: # Updates collection cards only for sticker editions the player currently owns.
	for index: int in range(_catalog.get_sticker_count()): # Visits every authored design once to discover currently owned normal and premium editions.
		var artwork_path: String = _catalog.get_sticker_path(index) # Reads the stable authored artwork identity.
		if _economy.get_owned_count(artwork_path) > 0: # Creates the normal entry only after the player owns at least one copy.
			_ensure_card(artwork_path) # Adds the owned normal edition without exposing undiscovered catalogue entries.
		for edition: int in PREMIUM_EDITIONS: # Checks each premium finish independently so ownership never merges editions together.
			var edition_key: String = StickerVariant.make_edition_key(artwork_path, edition) # Builds the exact persistent collection identity for this finish.
			if _economy.get_owned_count(edition_key) > 0: # Creates premium entries only while at least one exact-edition copy is owned.
				_ensure_card(edition_key) # Adds rainbow, silver, and gold as independent owned entries.
	for card: CollectionItem in _cards: # Refreshes all previously constructed cards so sold-out editions disappear immediately.
		var sticker_key: String = card.get_sticker_key() # Reads the exact normal or premium identity once.
		var owned_count: int = _economy.get_owned_count(sticker_key) # Reads current ownership after purchases, sales, and save restoration.
		card.refresh_count(owned_count, int(_available_count.call(sticker_key))) # Updates placement availability for copies that still exist.
		card.visible = owned_count > 0 # Hides cached entries immediately when the player no longer owns any copy of that edition.
	_completion.text = "%d / %d discovered" % [_economy.get_unique_owned_count(), _catalog.get_sticker_count()] # Keeps authored-design completion independent from premium variants.
	_progress.max_value = maxi(_catalog.get_sticker_count(), 1) # Handles an empty catalogue safely.
	_progress.value = _economy.get_unique_owned_count() # Updates completion by authored designs rather than edition copies.
	_apply_filter() # Applies search while retaining the ownership-only visibility rule.

func _apply_filter() -> void: # Filters only currently owned entries by search text while preventing missing stickers from appearing.
	var shown: int = 0 # Counts currently visible owned entries.
	for card: CollectionItem in _cards: # Evaluates only already discovered/cached collection cards.
		var sticker_key: String = card.get_sticker_key() # Reads the exact edition identity for current ownership validation.
		var owns_copy: bool = _economy.get_owned_count(sticker_key) > 0 # Treats current inventory as the authoritative collection-membership rule.
		card.visible = owns_copy and card.matches(_query, 0) # Applies text search while intentionally ignoring legacy missing/owned catalogue filters.
		shown += int(card.visible) # Counts only owned entries matching the current search.
	for filter_button: GameButton in _filters: # Hides obsolete all/owned/missing tabs because the page itself is now ownership-only.
		filter_button.visible = false # Removes controls that could imply undiscovered catalogue entries are part of this view.
	_empty.visible = shown == 0 # Shows the existing empty state when nothing owned matches the current search.
	_scroll.visible = shown > 0 # Gives the empty state the content area when the player owns no matching stickers.
	_summary.text = "%d owned sticker editions" % shown # Describes the actual ownership-only result set without referencing undiscovered catalogue entries.

func _clear_filters() -> void: # Clears search in the ownership-only collection view.
	_search.text = "" # Clears native editable search text.
	_query = "" # Clears the cached normalized query immediately.
	_filter_index = 0 # Keeps legacy filter state neutral even though ownership tabs are hidden.
	_apply_filter() # Restores every currently owned sticker edition.
	_search.grab_focus() # Returns focus to the collection search field.
