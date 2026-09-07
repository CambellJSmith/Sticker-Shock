class_name StickerMainMenu extends Control # Owns the title screen's progress presentation and primary action.

@onready var _continue: GameButton = %continue_button as GameButton # References the main progression action.
@onready var _free: GameButton = %free_button as GameButton # References the contextual free-pack shortcut.
@onready var _title: Label = %progress_title as Label # Shows the current collection milestone.
@onready var _detail: Label = %progress_detail as Label # Shows the book summary below the progress bar.
@onready var _progress: ProgressBar = %progress as ProgressBar # Visualizes collection completion.

var _controller: GameController # Holds the authoritative navigation owner.
var _economy: StickerEconomy # Reads pack availability and collection progress.
var _catalog: StickerCatalog # Supplies the current discovery goal.
var _book_state: StickerBookState # Reads placed and unresolved stickers.

func configure(controller: GameController, economy: StickerEconomy, catalog: StickerCatalog, book_state: StickerBookState, navigate: Callable) -> void: # Binds title-screen actions once.
	_controller = controller # Retains the game owner for the primary action.
	_economy = economy # Retains the progression model.
	_catalog = catalog # Retains the dynamic catalogue.
	_book_state = book_state # Retains the saved book model.
	_continue.bind_action(_continue_game) # Routes new players and unresolved packs to the shop.
	_free.bind_action(navigate.bind("shop")) # Opens the shop without making an implicit purchase.
	(%shop_button as GameButton).bind_action(navigate.bind("shop")) # Binds the explicit shop route.
	(%collection_button as GameButton).bind_action(navigate.bind("collection")) # Binds collection browsing.
	(%settings_button as GameButton).bind_action(navigate.bind("settings")) # Binds settings with return history.
	(%quit_button as GameButton).bind_action(controller.request_quit) # Uses the existing pending-pack-safe shutdown.
	refresh() # Presents the loaded save immediately.

func refresh() -> void: # Refreshes compact title-screen progress when requested by the shell.
	var collected: int = _economy.get_unique_owned_count() # Reads the unique design count.
	var total: int = _catalog.get_sticker_count() # Reads the discoverable catalogue size.
	var placed: int = _book_state.get_placement_count() # Reads the constant-time placement total.
	_title.text = "%d / %d stickers discovered" % [collected, total] if collected > 0 else "your collection starts here" # Provides a meaningful new-player state.
	_detail.text = "%d placed · %d pages in your book" % [placed, _book_state.get_page_count()] if placed > 0 else "your first favourite is waiting in a pack" # Shows a useful next step instead of empty statistics.
	_progress.max_value = maxi(total, 1) # Keeps the completion range valid for an empty catalogue.
	_progress.value = collected # Updates the visual progress indicator.
	_continue.text = "finish opening your pack" if _book_state.has_pending_stickers() else ("open your book" if placed > 0 else "start your collection") # Chooses the next useful action from actual progress.
	var remaining: int = _economy.get_free_pack_seconds_remaining() # Reads the persisted real-world cooldown.
	_free.text = "your free pack is ready  →" if remaining <= 0 else "next free pack in %s" % UIFormat.duration(remaining) # Keeps eligibility visible on the title screen.

func focus_primary() -> void: # Establishes predictable keyboard focus on entering the menu.
	_continue.grab_focus() # Selects the main progression action.

func _continue_game() -> void: # Continues at the most useful gameplay destination.
	if _book_state.has_pending_stickers() or _book_state.get_placement_count() == 0: # Detects an unresolved pack or a new collection.
		_controller.show_shop() # Takes the player directly to the pack flow.
	else: # Handles an established book with no unresolved pack.
		_controller.show_book() # Returns to the last saved spread.
