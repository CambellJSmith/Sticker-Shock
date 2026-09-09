class_name MarketHUD
extends Control

const ITEM_SCENE: PackedScene = preload("res://scenes/ui/market_item.tscn") # Reuses an editor-authored market quote row for every sellable sticker edition.

@onready var _list: VBoxContainer = %list as VBoxContainer # Owns cached market rows inside the scrollable exchange listing.
@onready var _empty: Control = %empty_state as Control # Explains when no unstuck collected stickers are available to sell.
@onready var _summary: Label = %summary as Label # Shows total sellable copy count across normal and gold editions.
@onready var _market_clock: Label = %market_clock as Label # Shows time remaining until the next live quote update.
@onready var _back_button: GameButton = %back_button as GameButton # Returns directly to the pack shop world.

var _controller: SpecialEditionGameController # Owns authoritative selling and world navigation.
var _economy: GuaranteedSpecialStickerEconomy # Reads edition-aware ownership after every completed sale.
var _catalog: StickerCatalog # Supplies all authored sticker identities and textures.
var _market: StickerMarket # Owns persistent live quotes and market timing.
var _available_count: Callable = Callable() # Reads only copies that are not already physically attached to the book.
var _rows: Dictionary[String, MarketItem] = {} # Caches one row per discovered normal or special edition to avoid rebuilds on every market tick.
var _refresh_elapsed: float = 0.0 # Throttles market-clock and quote polling while the exchange is visible.

func configure(controller: SpecialEditionGameController, economy: GuaranteedSpecialStickerEconomy, catalog: StickerCatalog, market: StickerMarket, available_count: Callable) -> void: # Binds authoritative market dependencies without signals.
	_controller = controller # Retains the world coordinator and sell transaction owner.
	_economy = economy # Retains edition-aware collection ownership for row discovery.
	_catalog = catalog # Retains authored metadata and artwork discovery.
	_market = market # Retains live quote state and tick scheduling.
	_available_count = available_count # Retains the controller-owned calculation that excludes stickers already in the book.
	_back_button.bind_action(controller.show_shop) # Provides an explicit native route back to pack buying without signals.
	refresh() # Builds the initial exchange listing immediately after all models are available.

func refresh() -> void: # Synchronizes sellable editions, live quotes, counts, and market timing with persistent state.
	if _economy == null or _catalog == null or _market == null or not _available_count.is_valid(): # Rejects refresh before the world has been configured completely.
		return # Leaves editor-authored placeholders intact until authoritative models exist.
	_market.advance_to_now(_catalog) # Publishes an overdue ten-minute market tick before showing any sale price.
	var total_available: int = 0 # Counts every unstuck copy currently eligible for sale.
	for index: int in range(_catalog.get_sticker_count()): # Visits each authored sticker design once to discover owned edition rows.
		var artwork_path: String = _catalog.get_sticker_path(index) # Reads the stable normal-edition identity.
		if _economy.get_owned_count(artwork_path) > 0: # Shows the normal row only after at least one copy has ever been collected.
			_ensure_row(artwork_path) # Creates the reusable normal-edition quote row when first discovered.
		var special_key: String = StickerVariant.make_key(artwork_path, true) # Builds the distinct gold-edition inventory identity for this design.
		if _economy.get_owned_count(special_key) > 0: # Shows gold editions separately only after the player has actually pulled one.
			_ensure_row(special_key) # Creates a dedicated premium quote row without duplicating authored content.
	for sticker_key: String in _rows.keys(): # Refreshes existing rows after ownership, placement, or market movement changes.
		var row: MarketItem = _rows[sticker_key] # Reads the cached reusable row for this exact edition.
		var available: int = maxi(int(_available_count.call(sticker_key)), 0) # Calculates how many copies remain outside the physical book.
		row.visible = _economy.get_owned_count(sticker_key) > 0 # Hides completely sold-out edition rows while preserving the cached node for future reacquisition.
		if row.visible: # Updates only editions still present in the player's collection.
			row.refresh() # Synchronizes the displayed quote, trend, and sell-button availability.
			total_available += available # Adds unstuck copies to the exchange-wide inventory summary.
	_empty.visible = total_available <= 0 # Shows guidance when every collected sticker is either sold or already attached to the book.
	(%scroll as ScrollContainer).visible = not _empty.visible # Gives the empty-state message the main content area when no sale rows remain actionable.
	_summary.text = "%d unstuck copies available to sell" % total_available # Makes the exchange's exact actionable inventory explicit.
	_refresh_market_clock() # Synchronizes the next quote countdown after any catch-up advancement.

func focus_primary() -> void: # Selects a useful controller/keyboard action when the market world becomes active.
	for sticker_key: String in _rows.keys(): # Searches cached rows in stable insertion order for the first actionable sale.
		var row: MarketItem = _rows[sticker_key] # Retrieves the candidate edition row.
		if row.visible and int(_available_count.call(sticker_key)) > 0: # Requires a visible edition with at least one unstuck copy.
			(row.get_node("%sell_button") as GameButton).grab_focus() # Gives focus directly to the first actionable native sell button.
			return # Stops after selecting one useful primary action.
	_back_button.grab_focus() # Falls back to the pack-shop route when nothing can currently be sold.

func _process(delta: float) -> void: # Polls the real-world market clock lightly only while this physical world is active.
	if not is_visible_in_tree() or _market == null: # Avoids hidden-world market work and premature model access.
		return # Leaves inactive exchange presentation untouched.
	_refresh_elapsed += delta # Accumulates time between low-frequency market checks.
	if _refresh_elapsed < 1.0: # Limits wall-clock and quote checks to once per second.
		return # Defers redundant polling until the next lightweight interval.
	_refresh_elapsed = 0.0 # Starts the next one-second refresh interval.
	if _market.advance_to_now(_catalog): # Detects an actual ten-minute quote publication rather than refreshing every second.
		refresh() # Updates every visible price and trend only when market state changed.
	else: # Handles ordinary seconds between market ticks.
		_refresh_market_clock() # Updates only the countdown label without touching sticker rows.

func _ensure_row(sticker_key: String) -> void: # Creates one reusable normal or gold quote row exactly once.
	if _rows.has(sticker_key): # Rejects edition rows already cached in this HUD session.
		return # Reuses the existing native controls and imported artwork.
	var artwork_path: String = StickerVariant.get_art_path(sticker_key) # Resolves the actual PNG shared by both edition identities.
	var texture: Texture2D = load(artwork_path) as Texture2D # Reuses Godot's imported texture cache for the row preview.
	if texture == null: # Handles missing or invalid authored artwork safely.
		return # Skips the unavailable entry without breaking the rest of the exchange.
	var row: MarketItem = ITEM_SCENE.instantiate() as MarketItem # Instantiates the editor-authored row layout.
	_list.add_child(row) # Parents the row into the native scrolling list before configuration.
	row.configure(sticker_key, texture, _market, _catalog, _available_count, _controller.sell_market_sticker) # Binds exact edition identity and authoritative transaction paths.
	_rows[sticker_key] = row # Caches the row for future quote and ownership refreshes.

func _refresh_market_clock() -> void: # Formats the real-world countdown until the next published sticker-market quote.
	var seconds_remaining: int = _market.get_seconds_until_next_tick() # Reads the market model's authoritative UTC tick countdown.
	var minutes: int = seconds_remaining / 60 # Converts the remaining interval into whole displayed minutes.
	var seconds: int = seconds_remaining % 60 # Preserves the remaining seconds within the current minute.
	_market_clock.text = "next market move in %02d:%02d" % [minutes, seconds] # Shows a compact live countdown that makes speculative timing legible.
