@tool
class_name StickerDefinition
extends Resource

@export var id: int = 0 # Stores the unique numerical sticker identifier used by tools and game data.
@export var sticker_name: String = "" # Stores the player-facing custom sticker name.
@export var art: Texture2D # Stores the imported PNG texture used to render the physical sticker.
@export_multiline var description: String = "" # Stores the descriptive text associated with the sticker.
@export var pack: String = "" # Stores the selected pack name from the shared pack list.
@export var artist: String = "" # Stores the selected artist name from the shared artist list.
@export var rarity: String = "" # Stores the selected rarity name from the shared rarity list.

func is_valid() -> bool: # Reports whether this resource contains every field required for runtime catalogue use.
	return id > 0 and not sticker_name.strip_edges().is_empty() and art != null and not pack.is_empty() and not artist.is_empty() and not rarity.is_empty() # Validates identity, artwork, and controlled-list metadata in one allocation-free expression.
