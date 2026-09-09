class_name RemovableSpecialEditionGameController
extends SpecialEditionGameController

func _init() -> void: # Extends the established premium/market/free-pack composition with removable book placement state.
	super() # Preserves banked free packs, market-linked pricing, premium guarantees, and edition-aware auto packing.
	_book_state = RemovableStickerBookState.new() # Replaces only physical book persistence with the compatible removable implementation.

func show_sticker_inspection(sticker_key: String) -> bool: # Opens one exact edition and populates its complete authored metadata plus live market value.
	if not super.show_sticker_inspection(sticker_key): # Reuses the established normal/rainbow/silver/gold material and isolated 3D inspection setup.
		return false # Leaves the current destination unchanged when the artwork cannot be inspected.
	var removable_inspection: RemovableStickerInspection = _game_ui._inspection as RemovableStickerInspection # Narrows the configured modal to its richer detail-sheet implementation.
	if removable_inspection != null: # Protects inspection if a future scene swaps the optional richer implementation.
		removable_inspection.set_return_to_collection_action(Callable()) # Keeps the destructive-looking book action hidden for generic inspection contexts.
		removable_inspection.set_sticker_details(_catalog.get_definition(sticker_key), StickerVariant.get_edition_name(sticker_key), get_inspection_market_value.bind(sticker_key)) # Supplies all creator-authored metadata, exact edition identity, and a live value provider without duplicating data.
	return true # Confirms that the detailed inspection surface is now active.

func show_book_sticker_inspection(sticker_key: String, placement_id: String) -> bool: # Opens one exact placed copy and exposes a reversible return-to-collection action alongside its full details.
	if sticker_key.is_empty() or placement_id.is_empty(): # Requires both edition identity and stable physical placement identity.
		return false # Rejects incomplete runtime metadata without opening a misleading removal UI.
	if not show_sticker_inspection(sticker_key): # Reuses the complete detailed inspection path including premium material and live market value.
		return false # Leaves the book unchanged if inspection composition fails.
	var removable_inspection: RemovableStickerInspection = _game_ui._inspection as RemovableStickerInspection # Narrows the configured modal to its book-removal extension.
	if removable_inspection == null: # Protects against scene configuration drift.
		return true # Keeps successful detailed inspection available even if the optional removal control is unavailable.
	removable_inspection.set_return_to_collection_action(return_book_sticker_to_collection.bind(placement_id)) # Binds only the exact clicked physical placement for this modal session.
	return true # Confirms inspection, metadata, live value, and removal context are active.

func get_inspection_market_value(sticker_key: String) -> int: # Returns the same exact-edition live quote used by the collector exchange and sale transaction.
	if sticker_key.is_empty(): # Rejects invalid copy identities without advancing persistent market state.
		return 0 # Reports no value for an unknown sticker.
	_market.advance_to_now(_catalog) # Publishes any due fifteen-second market update before reading the displayed value.
	return _market.get_price(sticker_key, _catalog) # Returns the exact normal/rainbow/silver/gold quote used if this copy were sold now.

func return_book_sticker_to_collection(placement_id: String) -> bool: # Removes one exact placement while keeping its economy-owned copy in the player's collection.
	var removable_state: RemovableStickerBookState = _book_state as RemovableStickerBookState # Narrows authoritative physical persistence to its removal API.
	if removable_state == null or placement_id.is_empty(): # Rejects invalid state/configuration before changing the save.
		return false # Leaves book and collection availability unchanged.
	var sticker_key: String = "" # Resolves the exact edition identity before removal for ownership validation and feedback.
	for placement: Dictionary in removable_state.get_placements_copy(): # Searches a caller-owned snapshot without exposing persistence mutation.
		if str(placement.get("id", "")) == placement_id: # Matches only the physical copy selected in inspection.
			sticker_key = str(placement.get("path", "")) # Preserves normal/rainbow/silver/gold identity exactly.
			break # Stops after the unique stable placement ID is found.
	if sticker_key.is_empty() or _economy.get_owned_count(sticker_key) <= 0: # Refuses to remove malformed placements that have no corresponding owned copy.
		return false # Prevents persistence inconsistencies from manufacturing collection inventory.
	var removed_key: String = removable_state.remove_placement(placement_id) # Deletes only the book placement record and persists the physical layout.
	if removed_key.is_empty(): # Handles a stale action after the placement has already disappeared.
		return false # Avoids duplicate refresh/toast work.
	var removable_book: RemovableSpecialEditionBookWorld = _book_world as RemovableSpecialEditionBookWorld # Narrows the live book scene for visible-spread reconstruction.
	if removable_book != null: # Refreshes immediately when the book world is currently composed.
		removable_book.refresh_after_placement_removal() # Removes the runtime sticker node by rebuilding from authoritative remaining placements.
	_game_ui.notify_progress_changed() # Refreshes collection available counts, placed total, and title-screen progression.
	_game_ui.show_toast("%s returned to collection" % _catalog.get_display_name(removed_key)) # Confirms that the owned copy remains available rather than being deleted.
	return true # Reports a complete reversible placement removal.
