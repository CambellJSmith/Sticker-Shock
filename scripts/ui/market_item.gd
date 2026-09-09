class_name MarketItem
extends PanelContainer

@onready var _art: TextureRect = %art as TextureRect # Shows the authored sticker artwork for the quoted edition row.
@onready var _name_label: Label = %name as Label # Shows the authored sticker name plus special-edition identity when applicable.
@onready var _rarity_label: Label = %rarity as Label # Shows the authored rarity used by the base-value model.
@onready var _owned_label: Label = %owned as Label # Shows how many unstuck copies can currently be sold.
@onready var _trend_label: Label = %trend as Label # Shows the persistent bullish, bearish, or sideways market regime and recent move.
@onready var _price_label: Label = %price as Label # Shows the current whole-coin collector bid for one copy.
@onready var _sell_button: GameButton = %sell_button as GameButton # Sells exactly one available copy through the authoritative controller.

var _sticker_key: String = "" # Stores the exact normal-or-special edition identity represented by this row.
var _market: StickerMarket # Reads current live quotes and trend presentation.
var _catalog: StickerCatalog # Reads authored metadata shared by both editions.
var _available_count: Callable = Callable() # Reads copies not already attached to the book or reserved for placement.
var _sell: Callable = Callable() # Delegates the actual inventory mutation and currency credit to the controller.

func configure(sticker_key: String, texture: Texture2D, market: StickerMarket, catalog: StickerCatalog, available_count: Callable, sell: Callable) -> void: # Binds one edition row without exposing model mutation to the UI component.
	_sticker_key = sticker_key # Retains the edition-aware inventory identity used by quote and sale validation.
	_market = market # Retains read-only access to current market pricing.
	_catalog = catalog # Retains authored metadata access for player-facing labels.
	_available_count = available_count # Retains the controller-owned physical availability calculation.
	_sell = sell # Retains the controller-owned transaction entry point.
	_art.texture = texture # Reuses Godot's imported texture cache for the authored artwork preview.
	_name_label.text = "%s · gold special" % _catalog.get_display_name(sticker_key) if StickerVariant.is_special(sticker_key) else _catalog.get_display_name(sticker_key) # Makes gold editions unmistakably separate without changing the authored name.
	_rarity_label.text = _catalog.get_rarity_name(sticker_key) # Shows rarity independently from the special-edition overlay.
	_sell_button.bind_action(_sell_one) # Routes native button activation directly without signals.
	refresh() # Initializes counts, quote, and trend state immediately after binding.

func refresh() -> void: # Updates only lightweight market and ownership fields for the current edition row.
	if _market == null or _catalog == null or not _available_count.is_valid(): # Rejects refresh before all authoritative dependencies exist.
		return # Leaves the editor-authored placeholder state untouched until configuration completes.
	var available: int = maxi(int(_available_count.call(_sticker_key)), 0) # Reads only copies that remain sellable outside the physical book.
	var price: int = _market.get_price(_sticker_key, _catalog) # Reads the current live one-copy market bid.
	var direction: int = _market.get_trend_direction(_sticker_key, _catalog) # Reads the persistent trend regime rather than inferring direction from one noisy tick.
	var recent_change: float = _market.get_recent_change_percent(_sticker_key, _catalog) # Reads the latest realized quote movement for additional market context.
	_owned_label.text = "%d available" % available # Shows exactly how many copies can be sold from collection inventory.
	_price_label.text = "%d coins" % price # Displays the live one-copy sale value in the game's existing currency.
	if direction > 0: # Presents a persistent bullish market regime.
		_trend_label.text = "▲ rising · %+.1f%% last move" % recent_change # Combines direction and noisy recent movement without implying guaranteed future value.
	elif direction < 0: # Presents a persistent bearish market regime.
		_trend_label.text = "▼ falling · %+.1f%% last move" % recent_change # Makes ongoing downward momentum visible for speculative timing.
	else: # Presents a sideways regime dominated by short-term collector noise.
		_trend_label.text = "• steady · %+.1f%% last move" % recent_change # Shows recent volatility even while no directional drift is active.
	_sell_button.text = "sell one · %d" % price # Keeps the exact transaction value visible on the action itself.
	_sell_button.disabled = available <= 0 # Prevents UI activation when every owned copy is already in the book or otherwise unavailable.

func get_sticker_key() -> String: # Exposes the immutable row identity to the market HUD cache.
	return _sticker_key # Returns the exact normal-or-special edition key represented by this row.

func _sell_one() -> void: # Sells exactly one currently available copy at the quote shown by the live market model.
	if not _sell.is_valid() or _sell_button.disabled: # Rejects invalid callbacks and exhausted inventory before attempting a transaction.
		return # Leaves the row unchanged when no authoritative sale can occur.
	_sell.call(_sticker_key) # Delegates validation, inventory decrement, currency credit, and market refresh to the controller.
