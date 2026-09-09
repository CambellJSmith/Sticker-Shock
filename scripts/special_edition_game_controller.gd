class_name SpecialEditionGameController
extends GameController

const MARKET_WORLD_SCENE: PackedScene = preload("res://scenes/market_world.tscn") # Preloads the physically separate collector exchange as a persistent third gameplay world.
const MARKET_WORLD_OFFSET: Vector3 = Vector3(2000.0, 0.0, 0.0) # Places the exchange far from book and pack-shop physics inside the shared World3D.

var _market: StickerMarket = StickerMarket.new() # Owns persistent real-world sticker quotes, trend regimes, demand noise, and recent price history.
var _market_world: MarketWorld # Stores the long-lived physical collector exchange scene for the complete application session.

func _init() -> void: # Replaces only the economy and sticker silhouette solver with edition-aware implementations before normal game initialization begins.
	_economy = GuaranteedSpecialStickerEconomy.new() # Preserves the existing economy interface while adding the one-time guaranteed special pull milestone and exact-copy market sales.
	_auto_packer = SpecialEditionAutoPacker.new() # Preserves the complete existing controller flow while ensuring special copy keys never reach ResourceLoader during packing.

func _ready() -> void: # Composes the established game first, then adds persistent live market state and its physically separate exchange world.
	super._ready() # Initializes catalogue, economy, book, pack shop, preferences, shared interface, and startup menu through the established coordinator.
	_market.initialize(_catalog) # Restores persistent design-level market trends and catches quotes up to the current real-world ten-minute tick.
	_market_world = MARKET_WORLD_SCENE.instantiate() as MarketWorld # Instantiates the collector exchange once so navigation never rebuilds its controls or physical set.
	_world_root.add_child(_market_world) # Parents the third world beside the established book and pack shop in the shared World3D.
	_market_world.position = MARKET_WORLD_OFFSET # Separates all market geometry, lights, and interaction coordinates from the other physical destinations.
	_market_world.configure(self, _economy as GuaranteedSpecialStickerEconomy, _catalog, _market, get_available_collection_count) # Binds edition-aware ownership, live quotes, and the physical-copy availability rule to the exchange.
	_market_world.set_active(false) # Leaves the exchange dormant while the startup menu remains the initial presentation owner.

func show_main_menu() -> void: # Returns to the startup menu while deactivating the optional exchange world when it already exists.
	if _market_world != null: # Handles calls made by the base startup path before the market world has been instantiated.
		_market_world.set_active(false) # Releases market camera, environment, HUD, and polling before opening the title screen.
	super.show_main_menu() # Reuses the established book/shop shutdown and title-screen presentation path.

func show_book() -> void: # Activates the book while ensuring the collector exchange cannot retain camera or processing ownership.
	if _market_world != null: # Protects the base startup period before the third world exists.
		_market_world.set_active(false) # Hides and suspends the collector exchange before the book becomes current.
	super.show_book() # Reuses the established authoritative book navigation and shared interface state.

func show_shop() -> void: # Activates the pack shop while ensuring the collector exchange is fully inactive.
	if _market_world != null: # Protects startup before market composition has completed.
		_market_world.set_active(false) # Releases market camera, environment, and HUD before pack-shop activation.
	super.show_shop() # Reuses the existing reveal-only pack-shop route and destination tracking.

func show_market() -> void: # Activates the physically separate collector exchange where only loose collection copies can be sold.
	if _market_world == null or _book_world == null or _shop_world == null: # Rejects navigation until every long-lived physical destination has completed composition.
		return # Leaves current presentation unchanged during incomplete startup state.
	_cancel_manual_placement_for_navigation() # Returns any temporarily carried collection sticker safely before inventory can be sold.
	get_tree().paused = false # Guarantees live market controls and world presentation process normally when entered from pause or overlays.
	_book_world.set_active(false) # Hides the book and releases its camera/environment ownership.
	_shop_world.set_active(false) # Hides the pack shop and releases its camera/environment ownership.
	_market_world.set_active(true) # Shows the collector exchange, publishes overdue quotes, and gives its camera/HUD ownership.
	_last_gameplay_destination = "market" # Records the exchange as the physical destination to resume after pause or complete overlays.
	_game_ui.show_destination("market") # Presents the shared navigation/status shell above the active physical market world.

func resume_last_gameplay_destination() -> void: # Restores the most recently used physical world including the new collector exchange.
	if _last_gameplay_destination == "market": # Detects when pause or an overlay was opened from the exchange.
		show_market() # Restores the collector exchange through its normal authoritative activation path.
		return # Avoids falling through to the base book/shop destination resolver.
	super.resume_last_gameplay_destination() # Preserves existing book and pack-shop resume behavior unchanged.

func _set_worlds_inactive() -> void: # Releases all three physical destinations while collection, settings, or another full-screen page owns presentation.
	super._set_worlds_inactive() # Deactivates the established book and pack-shop worlds through their existing lifecycle path.
	if _market_world != null: # Handles overlay calls that occur before the exchange has finished startup composition.
		_market_world.set_active(false) # Hides the market world and stops its one-second market-clock polling while a full-screen page is active.

func get_active_world_ui() -> Control: # Supplies the active world's native HUD to shared keyboard and controller navigation.
	if _last_gameplay_destination == "market" and _market_world != null: # Detects the collector exchange as the active physical destination.
		return _market_world.get_ui() # Returns the market HUD so sell and back buttons join the current native focus scope.
	return super.get_active_world_ui() # Preserves established book and pack-shop focus composition for every other physical destination.

func focus_active_world_ui() -> void: # Gives initial native focus to the useful action inside the active physical destination.
	if _last_gameplay_destination == "market" and _market_world != null: # Detects entry into the collector exchange.
		_market_world.get_ui().focus_primary() # Focuses the first sellable sticker or the back-to-packs action when nothing is loose.
		return # Prevents the base resolver from focusing unrelated book or shop controls.
	super.focus_active_world_ui() # Preserves established book page and pack-shop focus behavior.

func sell_market_sticker(sticker_key: String) -> int: # Sells one loose exact-edition collection copy at the currently published live market quote.
	if sticker_key.is_empty() or get_available_collection_count(sticker_key) <= 0: # Rejects unknown editions and copies already attached to the book or reserved for placement.
		return 0 # Leaves inventory and currency unchanged when no loose physical copy is available to sell.
	_market.advance_to_now(_catalog) # Publishes any overdue real-world market tick before locking the sale price.
	var sale_price: int = _market.get_price(sticker_key, _catalog) # Reads the exact current normal-or-gold bid after the latest market advancement.
	var special_economy: GuaranteedSpecialStickerEconomy = _economy as GuaranteedSpecialStickerEconomy # Narrows the configured edition-aware economy for its atomic sale transaction.
	if special_economy == null or not special_economy.sell_owned_copy(sticker_key, sale_price): # Atomically validates ownership, removes one exact edition, credits coins, and saves progression.
		return 0 # Reports no sale if persistent inventory changed before the transaction could commit.
	if _market_world != null: # Refreshes the active exchange immediately after successful inventory mutation.
		_market_world.get_ui().refresh() # Updates remaining sellable copies while keeping the current market quote unchanged.
	_game_ui.notify_progress_changed() # Refreshes shared coin balance, collection state, and title-screen progression after the completed sale.
	_game_ui.show_toast("sold %s for %d coins" % [_catalog.get_display_name(sticker_key), sale_price]) # Gives concise transaction feedback without interrupting the market world.
	return sale_price # Returns the committed proceeds for callers that need explicit transaction confirmation.

func show_sticker_inspection(sticker_key: String) -> bool: # Opens a normal or special book sticker while preserving its per-copy edition material in the isolated inspector.
	if _game_ui == null or sticker_key.is_empty(): # Rejects inspection before the persistent interface exists or when no sticker identity was resolved.
		return false # Leaves the physical book unchanged when no modal can be constructed.
	var artwork_path: String = StickerVariant.get_art_path(sticker_key) # Resolves the real PNG shared by normal and special editions.
	if not _game_ui.show_sticker_inspection(artwork_path): # Uses the established modal setup and texture-loading path first.
		return false # Leaves the current destination unchanged when the artwork cannot be inspected.
	if StickerVariant.is_special(sticker_key): # Rebuilds only special copies with the edition-aware material after the common inspector has initialized its state.
		var texture: Texture2D = load(artwork_path) as Texture2D # Reuses Godot's imported texture cache for the already validated artwork.
		if texture != null: # Protects against the resource disappearing between modal setup and the edition-specific rebuild.
			var inspection_mesh: StickerMesh = _game_ui._inspection._sticker_mesh # Retrieves the inspector-owned temporary mesh without touching the persistent book copy.
			inspection_mesh.configure(_catalog.get_default_size(artwork_path), texture, true) # Applies the same special-edition shader path used by shop reveals and placement previews.
			inspection_mesh.clear_peel() # Keeps the isolated inspection copy flat at startup.
			inspection_mesh.clear_turnover() # Keeps the isolated inspection copy front-facing until the player rotates it.
	return true # Confirms that the requested edition is now visible in the inspection modal.
