class_name CollectionItem extends GameButton # Makes each normal or special collection card a native placement action.

@onready var _art: TextureRect = %art as TextureRect # Displays the original artwork at its natural aspect ratio.
@onready var _name_label: Label = %name as Label # Displays a readable design and edition name.
@onready var _count_label: Label = %count as Label # Distinguishes owned copies from available physical copies.

var _sticker_key: String = "" # Retains the stable normal or special per-copy identity used by inventory and placement.
var _search_name: String = "" # Caches normalized text for filtering.
var _owned_count: int = 0 # Caches lifetime ownership for the active edition.
var _available_count: int = 0 # Caches copies of this edition not yet attached to the physical book.

func configure(sticker_key: String, texture: Texture2D, place: Callable) -> void: # Initializes this reusable card once per normal or special collection entry.
	_sticker_key = sticker_key # Stores the edition-aware identity independently of its artwork resource path.
	var artwork_path: String = StickerVariant.get_art_path(sticker_key) # Resolves the authored artwork used by both normal and special copies.
	var base_name: String = UIFormat.sticker_name(artwork_path) # Reads the normal human-readable sticker name from the authored path.
	_search_name = ("special %s" % base_name) if StickerVariant.is_special(sticker_key) else base_name # Makes special entries searchable independently while preserving base-name matches.
	_name_label.text = ("★ special · %s" % base_name) if StickerVariant.is_special(sticker_key) else base_name # Labels special copies as a distinct collection entry without changing authored metadata.
	_art.texture = texture # Reuses the imported base artwork rather than creating duplicate image assets.
	bind_action(place.bind(sticker_key)) # Starts physical book placement for the exact selected edition only from the collection.

func refresh_count(owned_count: int, available_count: int) -> void: # Updates ownership and placement availability without recreating the card or texture.
	_owned_count = maxi(owned_count, 0) # Keeps lifetime ownership presentation nonnegative.
	_available_count = clampi(available_count, 0, _owned_count) # Restricts available copies to the number actually collected for this edition.
	disabled = _available_count == 0 # Allows placement only while at least one collected copy of this exact edition is not already in the book.
	if _owned_count <= 0: # Handles undiscovered normal designs distinctly.
		_count_label.text = "not collected" # Explains that the player does not own this collection entry yet.
	elif _available_count > 0: # Handles collected copies that can still be placed.
		_count_label.text = "%d owned · %d available" % [_owned_count, _available_count] # Shows both lifetime collection and physical availability.
	else: # Handles editions whose collected copies are all already attached.
		_count_label.text = "%d owned · all in book" % _owned_count # Explains why the card cannot create another copy.
	_art.modulate = Color.WHITE if _owned_count > 0 else Color(0.36, 0.38, 0.43, 0.8) # Shows a silhouette only for undiscovered normal designs.
	tooltip_text = "add %s to your book" % _search_name if _available_count > 0 else ("all collected copies are already in your book" if _owned_count > 0 else "find %s in a sticker pack" % _search_name) # Explains the current action or lock reason.

func matches(query: String, filter_index: int) -> bool: # Applies cached text and ownership filters without texture work.
	return (query.is_empty() or _search_name.contains(query)) and (filter_index == 0 or (filter_index == 1 and _owned_count > 0) or (filter_index == 2 and _owned_count == 0)) # Combines search with the selected ownership tab.

func get_sticker_key() -> String: # Exposes the stable normal or special identity for model lookups.
	return _sticker_key # Keeps edition identity separate from the authored artwork path.
