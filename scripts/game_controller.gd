class_name GameController
extends Node

const BOOK_WORLD_SCENE: PackedScene = preload("res://scenes/book_world.tscn") # Preloads the persistent physical sticker-book world as an independent gameplay scene.
const SHOP_WORLD_SCENE: PackedScene = preload("res://scenes/shop_world.tscn") # Preloads the physically separate pack shop and reveal world.
const SHOP_WORLD_OFFSET: Vector3 = Vector3(1000.0, 0.0, 0.0) # Places the shop composition far from the book in the shared World3D so their physics, lighting, and coordinates never overlap.

@onready var _world_root: Node3D = $worlds as Node3D # References the stable composition node that owns both long-lived gameplay worlds.
@onready var _game_ui: GameUI = $game_ui as GameUI # References the persistent screen-space game shell that owns main-menu, navigation, pause, collection, and settings UX.

var _catalog: StickerCatalog = StickerCatalog.new() # Owns automatic discovery of every sticker artwork available to random packs.
var _economy: StickerEconomy = StickerEconomy.new() # Owns persistent in-game currency, duplicate collection counts, pack price, and six-hour free cooldown.
var _book_state: StickerBookState = StickerBookState.new() # Owns persistent physical book placements and any currently unresolved won pack stickers.
var _auto_packer: StickerAutoPacker = StickerAutoPacker.new() # Owns cached alpha-silhouette placement solving and reports a full active spread instead of overlapping stickers so new pages can be created.
var _preferences: GamePreferences = GamePreferences.new() # Owns lightweight persisted display preferences exposed through the settings destination.
var _book_world: BookWorld # Stores the long-lived physical sticker-book gameplay scene.
var _shop_world: ShopWorld # Stores the long-lived physically separate sticker-pack shop scene.
var _initialized: bool = false # Guards shutdown recovery logic until persistent models have completed startup initialization.
var _last_gameplay_destination: String = "book" # Stores the most recent physical destination so overlay pages and pause resume into the expected world.
var _quit_requested: bool = false # Prevents repeated close actions from running automatic pending-sticker placement and save work more than once.

func _ready() -> void: # Initializes progression, composes long-lived physical worlds, configures the persistent UX shell, and starts at the main menu.
	get_tree().auto_accept_quit = false # Lets this coordinator finish pending-sticker auto-placement and persistence before any desktop close actually exits.
	_catalog.rebuild() # Discovers every compatible sticker artwork resource before collection, packs, or physical placement sizing can be used.
	_economy.initialize() # Restores currency, owned counts, and the real-world free-pack eligibility timestamp from user storage.
	_book_state.initialize() # Restores every physical book placement, page count, active spread, and any unresolved won pack stickers.
	_preferences.initialize() # Restores and immediately applies persistent window mode and vertical-synchronization preferences.
	if _book_state.has_pending_stickers(): # Detects a previous session that ended before all revealed pack stickers were placed.
		_auto_place_pending_records() # Resolves interrupted physical pack contents into the book before any destination is presented.
	_book_world = BOOK_WORLD_SCENE.instantiate() as BookWorld # Instantiates the persistent physical sticker-book world once for the complete application session.
	_world_root.add_child(_book_world) # Parents the book composition at the origin of the shared World3D.
	_book_world.configure(self, _book_state, _catalog) # Binds authoritative models and reconstructs the saved active spread.
	_book_world.set_active(false) # Leaves the book dormant until selected through the menu or navigation shell.
	_shop_world = SHOP_WORLD_SCENE.instantiate() as ShopWorld # Instantiates the physically separate pack shop once so reveals can survive temporary book visits.
	_world_root.add_child(_shop_world) # Parents the shop composition alongside the book while preserving independent presentation state.
	_shop_world.position = SHOP_WORLD_OFFSET # Separates shop physics, lighting, and coordinates from the book inside the shared World3D.
	_shop_world.configure(self, _economy, _catalog, _book_state) # Binds authoritative progression and pending-pack state to the shop world.
	_shop_world.set_active(false) # Leaves the shop dormant while the startup menu owns presentation.
	_game_ui.configure(self, _economy, _catalog, _book_state, _preferences) # Binds all persistent data needed by navigation, summaries, collection browsing, settings, and pause UX.
	_initialized = true # Enables controlled quit behavior only after all persistent models, worlds, and interface state are valid.
	show_main_menu() # Opens the dedicated startup menu instead of dropping the player directly into a gameplay world.

func show_main_menu() -> void: # Returns to the dedicated startup menu while preserving the complete physical book and shop worlds in memory.
	if _book_world == null or _shop_world == null: # Protects navigation calls during the brief startup period before both worlds exist.
		return # Leaves presentation unchanged until composition is complete.
	_cancel_manual_placement_for_navigation() # Returns any carried pending sticker safely to unresolved state before leaving the physical book.
	get_tree().paused = false # Ensures returning from the pause menu never leaves gameplay globally suspended behind the startup menu.
	_book_world.set_active(false) # Hides book geometry, UI, camera, and environment ownership.
	_shop_world.set_active(false) # Hides shop geometry, UI, camera, and environment ownership.
	_game_ui.show_main_menu() # Presents the full-screen startup surface and refreshed progression summary.

func show_book() -> void: # Activates the persistent sticker-book world under the shared navigation shell.
	if _book_world == null or _shop_world == null: # Protects navigation before both physical destinations are composed.
		return # Leaves camera ownership unchanged when startup is incomplete.
	get_tree().paused = false # Guarantees the selected physical destination is processing when entered from pause or overlay navigation.
	_shop_world.set_active(false) # Hides the physically separate shop and releases its camera/environment ownership.
	_book_world.set_active(true) # Shows the book and gives its camera/input controller ownership.
	_last_gameplay_destination = "book" # Records the book as the destination to resume after collection, settings, or pause overlays.
	_game_ui.show_destination("book") # Presents the persistent navigation/status shell without covering the physical book viewport.

func show_shop() -> void: # Activates the physically separate sticker shop under the shared navigation shell.
	if _book_world == null or _shop_world == null: # Protects navigation before both physical destinations are composed.
		return # Leaves the current world unchanged while startup is incomplete.
	_cancel_manual_placement_for_navigation() # Returns any carried pack sticker safely to pending state before leaving manual placement.
	get_tree().paused = false # Guarantees the selected physical destination is processing when entered from pause or overlay navigation.
	_book_world.set_active(false) # Hides the persistent book and releases its camera/environment ownership.
	_shop_world.set_active(true) # Shows the shop, refreshes unresolved reveal objects, and gives its camera ownership.
	_last_gameplay_destination = "shop" # Records the shop as the destination to resume after collection, settings, or pause overlays.
	_game_ui.show_destination("shop") # Presents the persistent navigation/status shell without obscuring the interactive shop viewport.

func show_collection() -> void: # Opens a complete screen-space collection browser while preserving both physical worlds in memory.
	_cancel_manual_placement_for_navigation() # Safely abandons temporary placement before a non-world destination takes over input.
	get_tree().paused = false # Keeps the application responsive when collection is selected from a paused destination.
	_set_worlds_inactive() # Releases both physical cameras and environments because collection is a complete UI destination.
	_game_ui.show_destination("collection") # Presents the responsive collection grid inside the persistent shell.

func show_settings() -> void: # Opens display settings as a complete screen-space destination inside the persistent navigation shell.
	_cancel_manual_placement_for_navigation() # Safely returns any temporary pack sticker before world input is hidden.
	get_tree().paused = false # Keeps settings responsive when opened from the pause surface.
	_set_worlds_inactive() # Releases both physical cameras and environments while settings owns the content area.
	_game_ui.show_destination("settings") # Presents persisted display controls with the same navigation hierarchy as the rest of the game.

func resume_last_gameplay_destination() -> void: # Returns from pause or full-screen overlay pages to the most recently used physical destination.
	if _last_gameplay_destination == "shop": # Restores the shop when it was the player's last physical context.
		show_shop() # Re-enters the shop through the normal authoritative navigation path.
	else: # Uses the book as the default and fallback physical destination.
		show_book() # Re-enters the book through the normal authoritative navigation path.

func is_pointer_over_game_ui(screen_position: Vector2) -> bool: # Exposes global interface ownership so 3D worlds never react to clicks through menus, navigation chrome, or modal overlays.
	if _game_ui == null: # Protects the first startup frame before the interface node is available.
		return false # Leaves pointer routing unchanged until the shell can answer accurately.
	return _game_ui.is_pointer_over_interface(screen_position) # Delegates exact screen-space hit ownership to the persistent UI composition.

func is_gameplay_input_blocked() -> bool: # Reports whether any full-screen or modal interface state should suppress physical-world input entirely.
	if _game_ui == null: # Protects startup before the persistent shell exists.
		return false # Leaves gameplay input unblocked until the interface is configured.
	return _game_ui.blocks_world_input() # Delegates main-menu, collection, settings, and pause modal state to the interface owner.

func show_sticker_inspection(sticker_path: String) -> bool: # Opens one clicked book sticker in the independent flat zoom-and-rotate modal without changing physical placement state.
	if _game_ui == null or sticker_path.is_empty(): # Rejects inspection before the persistent interface exists or when no artwork identity was resolved.
		return false # Leaves the physical book unchanged when no modal can be constructed.
	return _game_ui.show_sticker_inspection(sticker_path) # Delegates texture loading and temporary presentation ownership to the screen-space interface layer.

func request_quit() -> void: # Auto-places unresolved pack stickers, flushes persistent book state, and exits exactly once.
	if _quit_requested: # Detects repeated button presses or duplicate operating-system close notifications.
		return # Leaves the first controlled shutdown path in sole ownership.
	_quit_requested = true # Locks the shutdown path before any synchronous packing or save work begins.
	get_tree().paused = false # Ensures persistence and any required packing work can complete even if quit was requested from the pause menu.
	if _book_state.has_pending_stickers(): # Detects won physical copies the player has not yet placed.
		_auto_place_pending_records() # Packs every solvable unresolved copy into the multi-page book according to the established quit rule.
	_book_state.save_now() # Flushes final page count, placements, active spread, and pending state to user storage.
	get_tree().quit() # Exits only after physical pack resolution and persistence have completed synchronously.

func _set_worlds_inactive() -> void: # Releases both long-lived physical destinations while a complete screen-space page owns presentation.
	if _book_world != null: # Protects calls during startup or teardown when the book scene may not exist.
		_book_world.set_active(false) # Hides book geometry, local interface, camera, and environment ownership.
	if _shop_world != null: # Protects calls during startup or teardown when the shop scene may not exist.
		_shop_world.set_active(false) # Hides shop geometry, local interface, camera, and environment ownership.

func _cancel_manual_placement_for_navigation() -> void: # Returns a temporarily carried pack sticker to unresolved state before destination changes.
	if _book_world == null: # Protects startup before the physical book exists.
		return # Leaves pending state untouched when there is no runtime preview to clear.
	_book_world.cancel_manual_placement_for_navigation() # Delegates preview cleanup to the world that owns its temporary 3D nodes and placement metadata.

func purchase_pack(use_free_pack: bool) -> bool: # Performs one authoritative pack transaction and creates a persistent five-sticker physical pending reveal.
	if _book_state.has_pending_stickers(): # Prevents multiple opened physical packs from overlapping before the current reveal enters the book.
		return false # Rejects the transaction without deducting currency or changing the free-pack cooldown.
	var pack: PackedStringArray = PackedStringArray() # Stores the exact five won sticker paths returned by the selected transaction route.
	if use_free_pack: # Selects the real-world cooldown claim path for the free-pack button.
		pack = _economy.claim_free_pack(_catalog) # Atomically grants ownership, starts the next six-hour timestamp, and saves economy progression.
	else: # Selects the normal in-game-currency purchase route.
		pack = _economy.buy_pack(_catalog) # Atomically deducts currency, grants duplicate-aware ownership, and saves economy progression.
	if pack.size() != _economy.get_pack_size(): # Detects insufficient funds, early free claims, missing catalogue content, or any incomplete transaction.
		return false # Leaves physical pending state untouched when a complete five-sticker pack was not granted.
	if not _book_state.set_pending_pack(pack): # Persists the exact five physical won copies before beginning any reveal animation.
		push_error("economy pack succeeded but physical pending pack could not be established") # Reports an invariant failure that should be impossible after the pre-transaction pending check.
		return false # Prevents visual reveal from diverging further from authoritative physical state.
	_shop_world.show_pending(true) # Throws the five won physical sticker sheets into the separate shop display with staggered rotating reveal animation.
	_game_ui.notify_progress_changed() # Refreshes currency, free-pack status, collection completion, and pending-pack badges immediately after the transaction.
	return true # Reports a complete pack acquisition and reveal-state commit.

func begin_manual_placement(pending_index: int, sticker_path: String) -> bool: # Moves one clicked physical shop reveal sticker into player-controlled placement on a spread that still has legal room.
	if pending_index < 0 or pending_index >= _book_state.get_pending_count(): # Rejects stale reveal indices after another pending sticker has already been placed.
		return false # Keeps the current shop reveal unchanged.
	if _book_state.get_pending_sticker(pending_index) != sticker_path: # Validates the exact physical pending copy represented by the clicked rotating reveal object.
		return false # Rejects stale or mismatched reveal nodes instead of consuming a different duplicate copy.
	var sticker_size: Vector2 = _catalog.get_default_size(sticker_path) # Retrieves the exact physical dimensions used by both manual preview and alpha-silhouette capacity testing.
	if not _ensure_active_spread_can_fit(sticker_path, sticker_size): # Detects when both currently active pages are full for this physical sticker silhouette.
		return false # Leaves the sticker safely pending when its design is physically too large even for a completely fresh spread.
	_book_world.show_spread(_book_state.get_active_spread_index()) # Ensures the live physical book displays the existing or newly appended spread selected by the capacity check.
	if not _book_world.begin_manual_placement(sticker_path, pending_index): # Builds the floating realistic sticker and exact page landing guide before changing worlds.
		return false # Leaves the player in the shop when the selected artwork cannot be loaded for placement.
	show_book() # Switches into the physical sticker book carrying the selected won sticker above the active pages.
	return true # Reports that manual placement mode was entered successfully.

func _ensure_active_spread_can_fit(sticker_path: String, sticker_size: Vector2) -> bool: # Guarantees manual placement opens a spread with at least one legal zero-overlap location for the selected sticker.
	var active_spread: int = _book_state.get_active_spread_index() # Retrieves the page pair that was active when the player selected the shop sticker.
	var active_placements: Array[Dictionary] = _book_state.get_placements_for_spread_copy(active_spread) # Copies only the two active pages because hidden spreads cannot affect capacity or silhouette overlap here.
	var active_solution: Dictionary = _auto_packer.find_tight_placement(sticker_path, sticker_size, active_placements, active_spread) # Tests whether either currently active page still has a legal alpha-silhouette fit.
	if not active_solution.is_empty(): # Keeps the current pages when at least one zero-overlap placement remains possible.
		return true # Allows manual placement without changing page count or navigation state.
	var candidate_new_spread: int = _book_state.get_spread_count() # Identifies the next spread index without mutating persistent book size yet.
	var fresh_solution: Dictionary = _auto_packer.find_tight_placement(sticker_path, sticker_size, [], candidate_new_spread) # Tests the completely blank future spread without walking or copying unrelated existing book pages.
	if fresh_solution.is_empty(): # Detects a sticker whose physical dimensions exceed usable page space even with no existing material.
		push_warning("manual placement sticker is too large for a blank page: %s" % sticker_path) # Reports the invalid design without consuming the pending pack copy.
		return false # Keeps the sticker pending because creating more identical page geometry cannot solve the size problem.
	_book_state.append_spread(true) # Adds and opens one fresh left/right page pair because both active pages are full for this sticker.
	return true # Reports that manual placement can proceed on the newly created empty spread.

func commit_manual_placement(pending_index: int, sticker_path: String, sticker_size: Vector2, page_index: int, world_xz: Vector2) -> bool: # Atomically converts one pending pack copy into an upright persistent placement on an explicit virtual page.
	if pending_index < 0 or pending_index >= _book_state.get_pending_count(): # Rejects stale pending indices before changing persistent physical state.
		return false # Keeps the temporary preview active so the player can recover safely.
	if _book_state.get_pending_sticker(pending_index) != sticker_path: # Verifies that the selected physical pack copy still occupies the same pending index.
		return false # Prevents duplicate designs from causing the wrong pending copy to be removed.
	if page_index < 0 or page_index >= _book_state.get_page_count(): # Rejects manual placement into a virtual page that has not actually been created.
		return false # Keeps the pending sticker recoverable instead of creating an invisible orphaned placement.
	if StickerBookLayout.get_spread_index_for_page(page_index) != _book_state.get_active_spread_index(): # Ensures the page target belongs to the same left/right pair currently shown to the player.
		return false # Rejects stale preview page metadata after any unexpected spread transition.
	var stack_order: int = _book_state.get_max_stack_order_for_page(page_index) + 1 # Places the newly attached sheet above other material only on its actual target page.
	var placement: Dictionary = _book_state.commit_pending_placement(pending_index, sticker_size, page_index, world_xz, stack_order) # Saves pending removal, canonical orientation, and explicit virtual-page attachment together.
	if placement.is_empty(): # Detects an unexpected persistence rejection after validation.
		return false # Leaves the temporary manual preview unresolved rather than losing the won sticker.
	_book_world.add_placement_record(placement, true) # Creates the real peelable Sticker above the chosen target and plays its bounce-and-slam attachment.
	_game_ui.notify_progress_changed() # Refreshes pending-count, page-count, and collection summary surfaces after the physical copy is filed.
	return true # Reports that the won sticker is now physically and persistently part of the multi-page book.

func auto_stick_pending(show_result_in_book: bool) -> int: # Tight-packs every unresolved won sticker into existing alpha silhouettes and optionally switches to the book to display their landings.
	var new_placements: Array[Dictionary] = _auto_place_pending_records() # Runs the authoritative packing and persistence loop until all possible pending stickers are committed.
	if show_result_in_book and not new_placements.is_empty(): # Displays the physical result when auto-stick was requested interactively from the shop.
		_book_world.show_auto_placements(new_placements) # Adds newly saved stickers to the live book scene with visible bounce-and-slam arrivals.
		show_book() # Switches directly from the shop display into the book so the player sees the automatic packing result.
	elif _shop_world != null: # Refreshes shop presentation when no placement was possible or auto-placement was invoked without a world switch.
		_shop_world.show_pending(false) # Rebuilds any unresolved reveal copies using their current authoritative pending indices.
	_game_ui.notify_progress_changed() # Refreshes page-count and pending-pack status after automatic placement expands or fills the book.
	return new_placements.size() # Returns how many physical sticker copies were successfully committed by the solver.

func _auto_place_pending_records() -> Array[Dictionary]: # Solves and persists every pending sticker sequentially while reusing one active-spread snapshot for the complete pack.
	var committed_placements: Array[Dictionary] = [] # Stores only physical placements successfully added during this packing pass.
	var target_spread: int = _book_state.get_active_spread_index() # Begins automatic packing on the exact page pair that is currently active in persistent book state.
	var working_placements: Array[Dictionary] = _book_state.get_placements_for_spread_copy(target_spread) # Copies only the two pages the solver can actually collide with instead of duplicating the complete multi-page book.
	while _book_state.has_pending_stickers(): # Continues until the unresolved physical pack is empty or one sticker is physically too large for a blank page.
		var sticker_path: String = _book_state.get_pending_sticker(0) # Always solves the first remaining physical copy so index removal stays stable with duplicates.
		if sticker_path.is_empty(): # Detects malformed pending persistence defensively.
			break # Stops before entering an invalid or non-terminating placement loop.
		var sticker_size: Vector2 = _catalog.get_default_size(sticker_path) # Retrieves the aspect-preserving physical artwork dimensions used by render and packing.
		var solution: Dictionary = _auto_packer.find_tight_placement(sticker_path, sticker_size, working_placements, target_spread) # Searches only the active spread using the in-memory layout already updated by earlier stickers in this same pack.
		if solution.is_empty(): # Detects that neither page in the current target spread can legally accept this sticker.
			var candidate_new_spread: int = _book_state.get_spread_count() # Identifies the not-yet-created spread that would follow the current final page pair.
			var fresh_solution: Dictionary = _auto_packer.find_tight_placement(sticker_path, sticker_size, [], candidate_new_spread) # Tests the completely blank future spread without rasterizing the currently full spread again.
			if fresh_solution.is_empty(): # Detects artwork physically too large to fit inside even an empty usable page at its canonical source orientation.
				push_warning("auto_stick could not fit pending sticker inside a blank page: %s" % sticker_path) # Reports the exceptional oversized design without creating pointless empty pages.
				break # Leaves the impossible oversized copy pending and recoverable rather than silently deleting it.
			target_spread = _book_state.append_spread(true) # Adds a new left/right pair because both active pages are full and makes that fresh pair authoritative.
			working_placements.clear() # Starts the in-memory collision snapshot empty because the newly created spread contains no attached stickers yet.
			solution = fresh_solution # Reuses the already-validated blank-spread solution without running the same packing search twice.
		var page_index: int = int(solution.get("page", StickerBookLayout.get_first_page_index_for_spread(target_spread))) # Retrieves the absolute virtual page selected by the alpha-silhouette solver.
		var stack_order: int = _book_state.get_max_stack_order_for_page(page_index) + 1 # Assigns the next paper layer only on the solved target page.
		var world_xz: Vector2 = Vector2(float(solution.get("x", 0.0)), float(solution.get("z", 0.0))) # Reconstructs the solved visible-page center from the packing result.
		var placement: Dictionary = _book_state.commit_pending_placement(0, sticker_size, page_index, world_xz, stack_order) # Atomically removes one pending copy and saves its explicit upright virtual-page attachment.
		if placement.is_empty(): # Detects an unexpected persistence failure that would otherwise leave the while loop unchanged.
			break # Stops safely before a non-terminating retry of the same unresolved sticker.
		working_placements.append(placement.duplicate(true)) # Extends the local solver snapshot so the next sticker packs against this new attachment without another whole-book copy.
		committed_placements.append(placement) # Records the newly persistent attachment for optional live book rendering.
	return committed_placements # Returns every physical sticker committed across the active and any newly appended spreads during this packing pass.

func _notification(what: int) -> void: # Routes operating-system close requests through the same controlled shutdown path as the game interface.
	if not _initialized: # Ignores close notifications received before persistent models are safe to mutate.
		return # Leaves startup teardown behavior untouched until initialization completes.
	if what == NOTIFICATION_WM_CLOSE_REQUEST: # Detects a normal desktop window-manager close request.
		request_quit() # Resolves pending stickers, saves the multi-page book, and quits exactly once.
