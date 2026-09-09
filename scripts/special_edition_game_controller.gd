class_name SpecialEditionGameController
extends GameController

func _init() -> void: # Replaces only the economy and sticker silhouette solver with edition-aware implementations before normal game initialization begins.
	_economy = GuaranteedSpecialStickerEconomy.new() # Preserves the existing economy interface while adding persistent fixed-cadence guaranteed special pulls.
	_auto_packer = SpecialEditionAutoPacker.new() # Preserves the complete existing controller flow while ensuring special copy keys never reach ResourceLoader during packing.
