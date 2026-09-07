class_name CollectionItem extends GameButton # Makes each collection card a native inspect action.

@onready var _art: TextureRect = %art as TextureRect # Displays the original artwork at its natural aspect ratio.
@onready var _name_label: Label = %name as Label # Displays a readable design name.
@onready var _count_label: Label = %count as Label # Distinguishes owned copies from undiscovered designs.

var _sticker_path: String = "" # Retains the stable catalogue resource identity.
var _search_name: String = "" # Caches normalized text for filtering.
var _owned_count: int = 0 # Caches ownership for the active filter.

func configure(sticker_path: String, texture: Texture2D, inspect: Callable) -> void: # Initializes this reusable card once per catalogue entry.
	_sticker_path = sticker_path # Stores the resource identity independently of its display name.
	_search_name = UIFormat.sticker_name(sticker_path) # Caches the readable lowercase name.
	_name_label.text = _search_name # Labels the native button's artwork.
	_art.texture = texture # Reuses the imported texture rather than reading image data.
	bind_action(inspect.bind(sticker_path)) # Opens the same isolated inspector used by the book.

func refresh_count(count: int) -> void: # Updates ownership without recreating the card or texture.
	_owned_count = maxi(count, 0) # Keeps the ownership presentation nonnegative.
	disabled = _owned_count == 0 # Restricts inspection to collected designs.
	_count_label.text = "%d owned · inspect" % _owned_count if _owned_count > 0 else "not collected" # Communicates state through text as well as colour.
	_art.modulate = Color.WHITE if _owned_count > 0 else Color(0.36, 0.38, 0.43, 0.8) # Shows a silhouette for undiscovered designs.
	tooltip_text = "inspect %s" % _search_name if _owned_count > 0 else "find %s in a sticker pack" % _search_name # Explains both enabled and locked cards.

func matches(query: String, filter_index: int) -> bool: # Applies cached text and ownership filters without texture work.
	return (query.is_empty() or _search_name.contains(query)) and (filter_index == 0 or (filter_index == 1 and _owned_count > 0) or (filter_index == 2 and _owned_count == 0)) # Combines search with the selected ownership tab.

func get_sticker_path() -> String: # Exposes the stable key for model lookups.
	return _sticker_path # Keeps the card's display name separate from saved data.
