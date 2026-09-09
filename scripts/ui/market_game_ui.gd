class_name MarketGameUI
extends GameUI

func configure(controller: GameController, economy: StickerEconomy, catalog: StickerCatalog, book_state: StickerBookState, preferences: GamePreferences) -> void: # Extends the established persistent game shell with one native collector-exchange destination.
	super.configure(controller, economy, catalog, book_state, preferences) # Binds all existing book, packs, collection, settings, pause, and inspection controls first.
	var market_button: GameButton = %nav_market as GameButton # References the editor-authored market navigation button in the shared left rail.
	_nav["market"] = market_button # Adds the collector exchange to the same destination-selection lookup used by existing routes.
	market_button.bind_action(_navigate.bind("market")) # Routes native activation through the established destination navigation path without signals.

func show_destination(destination: String) -> void: # Presents existing routes normally while giving the physical market world its own player-facing title.
	super.show_destination(destination) # Reuses shell visibility, navigation highlighting, modal closure, focus, and countdown handling.
	if destination == "market": # Corrects the base fallback title only for the newly introduced physical exchange route.
		(%page_title as Label).text = "collector exchange" # Gives the market world an explicit title in the persistent top bar.

func _route(destination: String) -> void: # Extends authoritative destination dispatch with the collector market world.
	if destination == "market": # Handles the one route unknown to the base GameUI implementation.
		if _controller is SpecialEditionGameController: # Requires the edition-aware root controller that owns the third physical world.
			(_controller as SpecialEditionGameController).show_market() # Transfers camera, environment, HUD, and market polling ownership through the controller.
		return # Prevents the base route matcher from ignoring the new destination.
	super._route(destination) # Preserves all established main-menu, book, packs, collection, and settings routing unchanged.
