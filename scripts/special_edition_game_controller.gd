class_name SpecialEditionGameController
extends GameController

func _init() -> void: # Replaces only the sticker silhouette solver with an edition-aware wrapper before normal game initialization begins.
	_auto_packer = SpecialEditionAutoPacker.new() # Preserves the complete existing controller flow while ensuring special copy keys never reach ResourceLoader during packing.
