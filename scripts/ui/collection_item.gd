class_name CollectionItem extends GameButton # Makes each collection card a native placement action.

@onready var _art: TextureRect = %art as TextureRect # Displays the original artwork at its natural aspect ratio.
@onready var _name_label: Label = %name as Label # Displays a readable design name.
@onready var _count_label: Label = %count as Label # Distinguishes owned copies from available physical copies.

var _sticker_path: String = "" # Retains the stable catalogue resource identity.
var _search_name: String = "" # Caches normalized text for filtering.
var _owned_count: int = 0 # Caches lifetime ownership for the active filter.
var _available_count: int = 0 # Caches copies not yet attached to the physical book.

func configure(sticker_path: String, texture: Texture2D, place: Callable) -> void: # Initializes this reusable card once per catalogue entry.
	_sticker_path = sticker_path # Stores the resource identity independently of its display name.
	_search_name = UIFormat.sticker_name(sticker_path) # Caches the readable lowercase name.
	_name_label.text = _search_name # Labels the native button's artwork.
	_art.texture = texture # Reuses the imported texture rather than reading image data.
	bind_action(place.bind(sticker_path)) # Starts physical book placement only from the collection.

func refresh_count(owned_count: int, available_count: int) -> void: # Updates ownership and placement availability without recreating the card or texture.
	_owned_count = maxi(owned_count, 0) # Keeps lifetime ownership presentation nonnegative.
	_available_count = clampi(available_count, 0, _owned_count) # Restricts available copies to the number actually collected.
	disabled = _available_count == 0 # Allows placement only while at least one collected copy is not already in the book.
	if _owned_count <= 0: # Handles undiscovered designs distinctly.
		_count_label.text = "not collected" # Explains that the player does not own this design yet.
	elif _available_count > 0: # Handles collected copies that can still be placed.
		_count_label.text = "%d owned · %d available" % [_owned_count, _available_count] # Shows both lifetime collection and physical availability.
	else: # Handles designs whose collected copies are all already attached.
		_count_label.text = "%d owned · all in book" % _owned_count # Explains why the card cannot create another copy.
	_art.modulate = Color.WHITE if _owned_count > 0 else Color(0.36, 0.38, 0.43, 0.8) # Shows a silhouette only for undiscovered designs.
	tooltip_text = "add %s to your book" % _search_name if _available_count > 0 else ("all collected copies are already in your book" if _owned_count > 0 else "find %s in a sticker pack" % _search_name) # Explains the current action or lock reason.

func matches(query: String, filter_index: int) -> bool: # Applies cached text and ownership filters without texture work.
	return (query.is_empty() or _search_name.contains(query)) and (filter_index == 0 or (filter_index == 1 and _owned_count > 0) or (filter_index == 2 and _owned_count == 0)) # Combines search with the selected ownership tab.

func get_sticker_path() -> String: # Exposes the stable key for model lookups.
	return _sticker_path # Keeps the card's display name separate from saved data.
