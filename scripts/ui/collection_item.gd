class_name CollectionItem
extends PanelContainer

@onready var _art: TextureRect = $margin/content/art as TextureRect # References the editor-authored artwork preview for this collection entry.
@onready var _name_label: Label = $margin/content/name as Label # References the editor-authored sticker display-name label.
@onready var _count_label: Label = $margin/content/count as Label # References the editor-authored duplicate-count label.

func configure(sticker_name: String, texture: Texture2D, owned_count: int) -> void: # Populates one reusable collection card from authoritative catalogue and economy data.
	_art.texture = texture # Displays the catalogue artwork through the card's aspect-preserving preview node.
	_name_label.text = sticker_name # Shows the catalogue-derived display name beneath the artwork.
	_count_label.text = "owned  %d" % maxi(owned_count, 0) # Shows the validated duplicate-inclusive ownership count for this design.
	if owned_count > 0: # Presents collected artwork at full readability when at least one copy has been obtained.
		_art.modulate = Color(1.0, 1.0, 1.0, 1.0) # Keeps owned artwork fully visible and naturally colored.
		_name_label.modulate = Color(1.0, 1.0, 1.0, 1.0) # Keeps owned sticker names at normal interface contrast.
	else: # Presents undiscovered catalogue entries as silhouettes without hiding collection completeness.
		_art.modulate = Color(0.17, 0.19, 0.22, 0.32) # Dims unowned artwork strongly while retaining its overall shape as a collection hint.
		_name_label.modulate = Color(0.58, 0.61, 0.66, 1.0) # Reduces unowned label emphasis relative to collected designs.
