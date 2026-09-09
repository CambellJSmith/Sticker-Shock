class_name RemovableStickerBookState
extends StickerBookState

func initialize() -> void: # Restores book state while treating persisted pending entries as temporary collection-placement reservations.
	super.initialize() # Loads placements, pages, navigation state, and any reservation left by an interrupted or older session.
	release_pending_collection_reservation() # Returns any reserved owned copy to collection availability instead of auto-placing it on startup.

func release_pending_collection_reservation() -> bool: # Clears temporary collection-placement reservations without changing economy ownership.
	if _pending_stickers.is_empty(): # Avoids rewriting persistent book state when no collection copy is reserved.
		return false # Reports that no reservation state changed.
	_pending_stickers.clear() # Releases every temporary reservation so its already-owned copy becomes available again.
	_save() # Persists the released reservation immediately so it cannot block later collection or shop actions.
	return true # Reports that pending reservation state was cleared.

func remove_placement(placement_id: String) -> String: # Removes one exact physical book placement while leaving economy ownership untouched.
	if placement_id.is_empty(): # Rejects missing placement identities before scanning persistent state.
		return "" # Reports no removed copy for invalid input.
	for placement_index: int in range(_placements.size()): # Searches the compact placement array by stable physical identifier.
		var placement: Dictionary = _placements[placement_index] # Reads the candidate placement without exposing mutable state externally.
		if str(placement.get("id", "")) != placement_id: # Skips every other physical copy, including duplicates of the same sticker.
			continue # Advances until the exact clicked placement is found.
		var sticker_key: String = str(placement.get("path", "")) # Captures the edition-aware collection identity before removing the book record.
		_placements.remove_at(placement_index) # Deletes only the physical placement so the owned copy becomes available in collection again.
		_save() # Persists the removal immediately so reopening cannot restore the sticker to the book.
		return sticker_key # Returns the exact normal/rainbow/silver/gold identity restored to collection availability.
	return "" # Reports that no matching physical placement existed.
