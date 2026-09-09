class_name RemovableSpecialEditionGameController
extends SpecialEditionGameController

func _init() -> void: # Extends the established premium/market/free-pack composition with removable book placement state.
	super() # Preserves banked free packs, market-linked pricing, premium guarantees, and edition-aware auto packing.
	_book_state = RemovableStickerBookState.new() # Replaces only physical book persistence with the compatible removable implementation.

func begin_collection_placement(sticker_path: String) -> bool: # Starts collection placement only after releasing any abandoned reservation from an earlier cancelled attempt.
	_release_abandoned_collection_reservation() # Repairs stale reservation state before checking whether this exact owned copy is available.
	var started: bool = super.begin_collection_placement(sticker_path) # Uses the established fit check, reservation, preview construction, and book transition.
	if not started: # Detects a reservation created before an exceptional preview or transition failure.
		_release_abandoned_collection_reservation() # Returns the copy to normal collection availability instead of leaving a hidden blocker behind.
	return started # Reports whether the collection copy successfully entered live manual placement.

func purchase_pack(use_free_pack: bool) -> bool: # Purchases a pack after cleaning up any reservation that no longer has a live placement preview.
	_release_abandoned_collection_reservation() # Prevents cancelled collection placement state from silently blocking an otherwise valid transaction.
	return super.purchase_pack(use_free_pack) # Preserves reveal guards, affordability checks, rewards, progression refresh, and free-pack handling.

func cancel_pending_placement() -> bool: # Cancels collection placement by releasing both its live preview and its temporary inventory reservation.
	if _book_world == null or not _book_world.has_manual_placement(): # Rejects cancellation when no collection copy is actively being positioned.
		return false # Allows the shared back action to continue to its normal pause behavior.
	_book_world.cancel_manual_placement_for_navigation() # Removes the temporary physical preview without routing through the obsolete pack-return behavior.
	_release_abandoned_collection_reservation() # Returns the already-owned copy to collection availability immediately.
	show_collection() # Returns to the collection that initiated placement so the released copy is visible again.
	return true # Confirms that back handled collection-placement cancellation instead of opening pause.

func _cancel_manual_placement_for_navigation() -> void: # Cleans up both runtime preview state and its collection reservation whenever navigation leaves placement.
	super._cancel_manual_placement_for_navigation() # Lets the book remove any temporary preview and cancel its delayed transition first.
	_release_abandoned_collection_reservation() # Releases reservation state only after no live manual preview remains.

func _release_abandoned_collection_reservation() -> bool: # Releases pending state only when it no longer corresponds to an active physical placement preview.
	if _book_world != null and _book_world.has_manual_placement(): # Preserves the reservation while the player is genuinely positioning that copy in the book.
		return false # Reports no cleanup while live placement still owns the reservation.
	var removable_state: RemovableStickerBookState = _book_state as RemovableStickerBookState # Narrows the configured persistence model to its reservation-release API.
	if removable_state == null: # Protects future controller compositions that replace the removable persistence implementation.
		return false # Leaves unknown state untouched rather than assuming compatible reservation semantics.
	if not removable_state.release_pending_collection_reservation(): # Clears stale pending entries and persists only when a reservation actually exists.
		return false # Avoids unnecessary interface refresh work when there was nothing to repair.
	if _game_ui != null: # Handles cleanup that can occur during startup before the persistent interface is ready.
		_game_ui.notify_progress_changed() # Refreshes collection availability, pending status, and progression after releasing the reserved copy.
	return true # Reports that an abandoned reservation was removed successfully.

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
	_release_abandoned_collection_reservation() # Prevents an unrelated stale placement reservation from hiding the newly released collection copy.
	var removed_key: String = removable_state.remove_placement(placement_id) # Deletes only the exact physical book record while leaving persistent economy ownership untouched.
	if removed_key.is_empty(): # Handles a stale action after the placement has already disappeared.
		return false # Keeps the inspection open so the player can see that the action did not commit.
	var removable_book: RemovableSpecialEditionBookWorld = _book_world as RemovableSpecialEditionBookWorld # Narrows the live book scene for visible-spread reconstruction.
	if removable_book != null: # Refreshes immediately when the book world is currently composed.
		removable_book.refresh_after_placement_removal() # Removes the runtime sticker node by rebuilding from authoritative remaining placements.
	_game_ui.notify_progress_changed() # Refreshes collection available counts, placed total, and title-screen progression.
	_game_ui.show_toast("%s returned to collection" % _catalog.get_display_name(removed_key)) # Confirms that the owned copy remains available rather than being deleted.
	return true # Reports a complete reversible placement removal.
