class_name RemovableStickerBookState
extends StickerBookState

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
