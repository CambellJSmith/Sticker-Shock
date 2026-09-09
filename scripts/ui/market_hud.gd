class_name MarketHUD
extends Control

const ITEM_SCENE: PackedScene = preload("res://scenes/ui/market_item.tscn") # Reuses an editor-authored market quote row for every sellable sticker edition.
const PREMIUM_EDITIONS: Array[int] = [StickerVariant.EDITION_RAINBOW, StickerVariant.EDITION_SILVER, StickerVariant.EDITION_GOLD] # Defines the premium finishes that receive separate market rows after discovery.

@onready var _list: VBoxContainer = %list as VBoxContainer # Owns cached market rows inside the scrollable exchange listing.
@onready var _empty: Control = %empty_state as Control # Explains when no unstuck collected stickers are available to sell.
@onready var _summary: Label = %summary as Label # Shows total sellable copy count across every edition.
@onready var _market_clock: Label = %market_clock as Label # Shows time remaining until the next live quote update.
@onready var _chart_title: Label = %chart_title as Label # Shows the exact sticker edition represented by the live graph.
@onready var _chart_price: Label = %chart_price as Label # Shows the selected edition's current live quote beside its graph.
@onready var _chart: MarketPriceChart = %chart as MarketPriceChart # Draws the selected edition's rolling thirty-minute price history.
@onready var _back_button: GameButton = %back_button as GameButton # Returns directly to the pack shop world.

var _controller: SpecialEditionGameController # Owns authoritative selling and world navigation.
var _economy: GuaranteedSpecialStickerEconomy # Reads edition-aware ownership after every completed sale.
var _catalog: StickerCatalog # Supplies all authored sticker identities and textures.
var _market: StickerMarket # Owns persistent live quotes and market timing.
var _available_count: Callable = Callable() # Reads only copies that are not already physically attached to the book.
var _rows: Dictionary[String, MarketItem] = {} # Caches one row per discovered exact edition to avoid rebuilds on every market tick.
var _selected_chart_key: String = "" # Stores the exact edition currently displayed in the stock-style graph.
var _refresh_elapsed: float = 0.0 # Throttles market-clock and quote polling while the exchange is visible.

func configure(controller: SpecialEditionGameController, economy: GuaranteedSpecialStickerEconomy, catalog: StickerCatalog, market: StickerMarket, available_count: Callable) -> void: # Binds authoritative market dependencies without signals.
	_controller = controller # Retains the world coordinator and sell transaction owner.
	_economy = economy # Retains edition-aware collection ownership for row discovery.
	_catalog = catalog # Retains authored metadata and artwork discovery.
	_market = market # Retains live quote state and tick scheduling.
	_available_count = available_count # Retains the controller-owned calculation that excludes stickers already in the book.
	_back_button.bind_action(controller.show_shop) # Provides an explicit native route back to pack buying without signals.
	refresh() # Builds the initial exchange listing and chart immediately after all models are available.

func refresh() -> void: # Synchronizes sellable editions, live quotes, counts, chart data, and market timing with persistent state.
	if _economy == null or _catalog == null or _market == null or not _available_count.is_valid(): # Rejects refresh before the world has been configured completely.
		return # Leaves editor-authored placeholders intact until authoritative models exist.
	_market.advance_to_now(_catalog) # Publishes any overdue fifteen-second market tick before showing sale prices.
	var total_available: int = 0 # Counts every unstuck copy currently eligible for sale.
	for index: int in range(_catalog.get_sticker_count()): # Visits each authored sticker design once to discover owned edition rows.
		var artwork_path: String = _catalog.get_sticker_path(index) # Reads the stable normal-edition identity.
		if _economy.get_owned_count(artwork_path) > 0: # Shows the normal row only after at least one copy has ever been collected.
			_ensure_row(artwork_path) # Creates the reusable normal-edition quote row when first discovered.
		for edition: int in PREMIUM_EDITIONS: # Checks each premium finish independently so market inventory never merges them.
			var edition_key: String = StickerVariant.make_edition_key(artwork_path, edition) # Builds the persistent inventory identity for this finish.
			if _economy.get_owned_count(edition_key) > 0: # Shows a premium row only after the player has actually pulled that exact edition.
				_ensure_row(edition_key) # Creates the dedicated rainbow, silver, or gold quote row without duplicating authored content.
	for sticker_key: String in _rows.keys(): # Refreshes existing rows after ownership, placement, or market movement changes.
		var row: MarketItem = _rows[sticker_key] # Reads the cached reusable row for this exact edition.
		var available: int = maxi(int(_available_count.call(sticker_key)), 0) # Calculates how many copies remain outside the physical book.
		row.visible = _economy.get_owned_count(sticker_key) > 0 # Hides completely sold-out edition rows while preserving the cached node for future reacquisition.
		if row.visible: # Updates only editions still present in the player's collection.
			row.refresh() # Synchronizes the displayed quote, trend, and sell-button availability.
			total_available += available # Adds unstuck copies to the exchange-wide inventory summary.
			if _selected_chart_key.is_empty(): # Automatically chooses the first discovered owned edition for immediate graph presentation.
				_selected_chart_key = sticker_key # Stores the first visible market identity as the initial graph target.
	_empty.visible = total_available <= 0 # Shows guidance when every collected sticker is either sold or already attached to the book.
	(%scroll as ScrollContainer).visible = not _empty.visible # Gives the empty-state message the main content area when no sale rows remain actionable.
	_summary.text = "%d unstuck copies available to sell" % total_available # Makes the exchange's exact actionable inventory explicit.
	_refresh_selected_chart() # Updates the live graph after any price or selection change.
	_refresh_market_clock() # Synchronizes the next quote countdown after any catch-up advancement.

func focus_primary() -> void: # Selects a useful controller/keyboard action when the market world becomes active.
	for sticker_key: String in _rows.keys(): # Searches cached rows in stable insertion order for the first actionable sale.
		var row: MarketItem = _rows[sticker_key] # Retrieves the candidate edition row.
		if row.visible and int(_available_count.call(sticker_key)) > 0: # Requires a visible edition with at least one unstuck copy.
			row.focus_sell() # Delegates focus to the row without reaching into its editor-authored child hierarchy.
			return # Stops after selecting one useful primary action.
	_back_button.grab_focus() # Falls back to the pack-shop route when nothing can currently be sold.

func _process(delta: float) -> void: # Polls the live market clock lightly while this physical world is active.
	if not is_visible_in_tree() or _market == null: # Avoids hidden-world market work and premature model access.
		return # Leaves inactive exchange presentation untouched.
	_refresh_elapsed += delta # Accumulates time between low-frequency market checks.
	if _refresh_elapsed < 0.25: # Checks four times per second so the fifteen-second boundary feels immediate without per-frame market work.
		return # Defers redundant polling until the next lightweight interval.
	_refresh_elapsed = 0.0 # Starts the next quarter-second refresh interval.
	if _market.advance_to_now(_catalog): # Detects an actual live quote publication rather than refreshing every poll.
		refresh() # Updates rows and graph only when market state changed.
	else: # Handles ordinary fractions of a second between quote ticks.
		_refresh_market_clock() # Updates only the short countdown label.

func _ensure_row(sticker_key: String) -> void: # Creates one reusable exact-edition quote row exactly once.
	if _rows.has(sticker_key): # Rejects edition rows already cached in this HUD session.
		return # Reuses the existing native controls and imported artwork.
	var artwork_path: String = StickerVariant.get_art_path(sticker_key) # Resolves the actual PNG shared by every edition identity.
	var texture: Texture2D = load(artwork_path) as Texture2D # Reuses Godot's imported texture cache for the row preview.
	if texture == null: # Handles missing or invalid authored artwork safely.
		return # Skips the unavailable entry without breaking the rest of the exchange.
	var row: MarketItem = ITEM_SCENE.instantiate() as MarketItem # Instantiates the editor-authored row layout.
	_list.add_child(row) # Parents the row into the native scrolling list before configuration.
	row.configure(sticker_key, texture, _market, _catalog, _available_count, _show_chart, _controller.sell_market_sticker) # Binds edition identity, graph selection, and authoritative transaction paths.
	_rows[sticker_key] = row # Caches the row for future quote and ownership refreshes.

func _show_chart(sticker_key: String) -> void: # Selects one exact edition for the shared stock-style live graph.
	if sticker_key.is_empty() or not _rows.has(sticker_key): # Rejects invalid or undiscovered edition identities.
		return # Leaves the current chart unchanged for malformed requests.
	_selected_chart_key = sticker_key # Stores the player's requested graph target.
	_refresh_selected_chart() # Rebuilds only the graph header and line data immediately.

func _refresh_selected_chart() -> void: # Synchronizes the shared graph with the selected edition's current quote history.
	if _selected_chart_key.is_empty() or _catalog == null or _market == null: # Rejects graph work before a usable edition and dependencies exist.
		_chart_title.text = "select a sticker to view its market" # Keeps the empty state understandable.
		_chart_price.text = "—" # Clears any stale price value.
		_chart.set_prices(PackedFloat32Array()) # Clears the line while retaining the chart grid.
		return # Stops before edition-specific reads.
	var base_name: String = _catalog.get_display_name(_selected_chart_key) # Reads the authored sticker name for the graph heading.
	var edition_name: String = StickerVariant.get_edition_name(_selected_chart_key) # Reads the exact per-copy finish represented by the selected market key.
	_chart_title.text = "%s · %s" % [base_name, edition_name] # Shows a concise stock-style instrument name.
	_chart_price.text = "£%d" % _market.get_price(_selected_chart_key, _catalog) # Shows the current tradable quote beside the graph in pounds.
	if _market is EditionStickerMarket: # Uses the live-edition market's chart history API when available.
		var live_market: EditionStickerMarket = _market as EditionStickerMarket # Narrows the configured market to its live implementation.
		_chart.set_prices(live_market.get_price_history(_selected_chart_key, _catalog)) # Sends only the compact thirty-minute series to the drawing control.
	else: # Preserves a harmless fallback if a different market model is configured later.
		_chart.set_prices(PackedFloat32Array()) # Leaves the graph empty rather than depending on unsupported history APIs.

func _refresh_market_clock() -> void: # Formats the real-world countdown until the next published live sticker-market quote.
	var seconds_remaining: int = _market.get_seconds_until_next_tick() # Reads the market model's authoritative UTC tick countdown.
	_market_clock.text = "next quote in 00:%02d" % seconds_remaining # Shows the short fifteen-second live-market countdown compactly.
