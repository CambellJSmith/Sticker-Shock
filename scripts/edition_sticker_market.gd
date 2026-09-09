class_name EditionStickerMarket
extends StickerMarket

const RAINBOW_VALUE_RATIO: float = 0.25 # Converts the legacy twelve-times premium into a three-times rainbow premium.
const SILVER_VALUE_RATIO: float = 0.50 # Converts the legacy twelve-times premium into a six-times silver premium.

func get_price(sticker_key: String, catalog: StickerCatalog) -> int: # Returns the live quote while scaling premium value according to actual edition scarcity.
	var base_quote: int = super.get_price(sticker_key, catalog) # Reuses the complete persistent trend, randomness, rarity, and collector-demand model.
	match StickerVariant.get_edition(sticker_key): # Adjusts only premium editions after the shared market movement is calculated.
		StickerVariant.EDITION_RAINBOW: return maxi(int(round(float(base_quote) * RAINBOW_VALUE_RATIO)), 1) # Values the one-percent rainbow edition at roughly three times normal.
		StickerVariant.EDITION_SILVER: return maxi(int(round(float(base_quote) * SILVER_VALUE_RATIO)), 1) # Values the half-percent silver edition at roughly six times normal.
		_: return base_quote # Keeps normal values unchanged and preserves the full twelve-times premium for the rarest gold edition.
