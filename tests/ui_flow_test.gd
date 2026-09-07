extends SceneTree # Exercises native UI input, modal isolation, and persisted gameplay flows headlessly.

var _game: GameController # Holds the real main scene under test.
var _ui: GameUI # References the real persistent UI coordinator.
var _book: BookWorld # References the physical book instance.
var _shop: ShopWorld # References the physical shop instance.
var _state: StickerBookState # Reads the same authoritative model as gameplay.
var _economy: StickerEconomy # Reads transaction outcomes from the live game.
var _frame: int = 0 # Spaces test stages so deferred native layouts settle.
var _stage: int = 0 # Tracks the next independent interaction step.
var _failures: int = 0 # Counts failed behavioral assertions.
var _checks: int = 0 # Counts executed behavioral assertions.
var _selected_card: CollectionItem # Remembers the card that should regain focus after inspection.
var _card_id: int = 0 # Verifies that collection visits reuse their existing cards.
var _inspection_before: String = "" # Captures saved placements before rotating temporary inspection artwork.
var _gesture_point: Vector2 = Vector2.ZERO # Retains the projected start of a real physical sticker gesture.
var _pending_before: int = 0 # Verifies cancelled placement never consumes a copy.
var _owned_before: int = 0 # Verifies exact placement and pending-copy conservation.

func _initialize() -> void: # Requires an isolated data directory before starting a real economy flow.
	if not OS.get_environment("XDG_DATA_HOME").contains("sticker_shock_ui_test"): # Protects a player's real book from this test's intentional purchases.
		push_error("set XDG_DATA_HOME to a temporary sticker_shock_ui_test directory before running this test") # Explains the required isolation guard.
		quit(2) # Refuses to mutate any normal user save.
		return # Stops initialization after the guard fails.
	for file_name: String in ["sticker_progress.json", "sticker_book.json", "game_preferences.json"]: # Starts each run with a deterministic isolated save.
		var path: String = "user://".path_join(file_name) # Resolves only this isolated project's test files.
		if FileAccess.file_exists(path): # Avoids errors when no prior test save exists.
			DirAccess.remove_absolute(path) # Removes only the explicitly named isolated test data.
	root.size = Vector2i(1280, 800) # Establishes the default desktop layout for native input tests.
	_game = load("res://scenes/main.tscn").instantiate() as GameController # Loads the actual scene and composed HUDs.
	root.add_child(_game) # Runs normal game initialization and persistence loading.
	_ui = _game.get_node("game_ui") as GameUI # References the actual shell under test.
	_state = _game.get("_book_state") as StickerBookState # Observes live saved state without creating a second model.
	_economy = _game.get("_economy") as StickerEconomy # Observes actual transaction outcomes.

func _process(_delta: float) -> bool: # Advances a deterministic signal-free integration scenario.
	if _game == null: # Handles initialization rejected by the isolation guard.
		return false # Waits for the requested guarded shutdown.
	_frame += 1 # Counts engine frames while normal native input and layouts run.
	if _frame % 24 != 0: # Gives deferred navigation, polling, and short landing animation time to settle.
		return false # Lets the real game process between test stages.
	match _stage: # Runs the actual user flow as a sequence of native input actions.
		0: # Checks the first-session menu and enters the pack flow.
			_book = _game.get("_book_world") as BookWorld # Reads the physical book after normal ready-time composition.
			_shop = _game.get("_shop_world") as ShopWorld # Reads the physical shop after normal ready-time composition.
			_check(_visible(_ui, "%main_menu"), "new session opens the title screen") # Verifies the startup destination.
			_check(_state.get_placement_count() == 0, "test starts with an empty book") # Confirms save isolation.
			_click(_button(_ui.get_node("%main_menu"), "%continue_button")) # Uses a real native pointer click on the primary title action.
		1: # Checks shop layout and begins a purchase press without release.
			_check(_shop.visible and not _book.visible, "new-player primary action opens the shop") # Verifies useful first-session routing.
			_check(_shop.get_ui().get_node("area").get_rect().position == Vector2(160, 64), "shop content respects the shell safe area") # Catches anchor-order regressions.
			_check((_ui.get_node("%nav_panel") as Control).size.x == 160.0, "navigation rail matches camera framing") # Prevents native minimum size from silently widening the rail.
			_mouse(_button(_shop.get_ui(), "%buy_button").get_global_rect().get_center(), true) # Starts a real button press without committing it.
		2: # Verifies that pointer-down alone cannot spend currency.
			_check(_economy.get_currency() == 500, "purchase activates on release rather than press") # Protects normal cancelable button semantics.
			_motion(Vector2(900, 150)) # Moves off the button before releasing the cancelled gesture.
			_mouse(Vector2(900, 150), false) # Releases outside the purchase button to cancel the gesture.
		3: # Verifies cancellation and commits a deliberate priced purchase.
			_check(_economy.get_currency() == 500 and _state.get_pending_count() == 0, "dragging off a purchase button cancels it") # Prevents accidental spending.
			_click(_button(_shop.get_ui(), "%buy_button")) # Opens one paid pack through native GUI dispatch.
		4: # Verifies transaction conservation and opens pause during a real reward reveal.
			_check(_economy.get_currency() == 400 and _state.get_pending_count() == 5, "one native purchase charges once and grants exactly five copies") # Verifies the guarded economy flow.
			_check(not _game.purchase_pack(true), "an unresolved pack blocks another transaction") # Prevents overlapping packs and lost copies.
			_key(KEY_ESCAPE) # Opens pause using the player's actual back input.
		5: # Verifies that clicks cannot reach navigation underneath pause.
			_check(paused and _visible(_ui, "%pause_overlay"), "pause genuinely suspends physical worlds") # Checks processing and presentation state together.
			_click(_button(_ui, "%nav_book")) # Attempts the original click-through path beneath the modal dimmer.
		6: # Verifies modal isolation and wraps focus through the pause scope.
			_check(paused and _shop.visible and not _book.visible, "pause blocks underlying navigation clicks") # Catches a concrete previously possible routing bug.
			for index: int in range(9): # Exercises repeated native tab traversal.
				_key(KEY_TAB) # Moves focus through the active modal.
				_check((_ui.get_node("%pause_overlay") as Node).is_ancestor_of(root.gui_get_focus_owner()), "tab focus stays inside pause") # Rejects hidden or background focus targets.
			_click(_button(_ui, "%pause_settings")) # Opens settings from the pause modal.
		7: # Verifies the contextual pause-to-settings route.
			_check(_visible(_ui, "%settings_page") and not paused, "pause settings opens a usable settings page") # Ensures the native settings page can process input.
			_key(KEY_ESCAPE) # Returns to the surface that opened settings.
		8: # Verifies that returning from pause settings preserves pause.
			_check(paused and _shop.visible and _visible(_ui, "%pause_overlay"), "settings returns to the paused shop") # Protects nested back behavior.
			_click(_button(_ui, "%resume_button")) # Resumes through the native primary modal action.
		9: # Opens the collection and checks the shared shell remains usable.
			_check(not paused, "resume restores gameplay processing") # Confirms modal teardown.
			_click(_button(_ui, "%nav_collection")) # Enters the collection through persistent navigation.
		10: # Verifies responsive collection placement and ownership filtering.
			_check(_visible(_ui, "%collection_browser"), "collection navigation opens the browser") # Confirms the intended route.
			_check((_ui.get_node("%content_overlay") as Control).position == Vector2(160, 64), "collection preserves navigation and status chrome") # Prevents full-screen content from covering the rail.
			_click(_button(_ui.get_node("%collection_browser"), "%owned_filter")) # Selects the collected-only tab through native input.
		11: # Opens an owned design from the cached collection cards.
			var grid: GridContainer = _ui.get_node("%collection_browser").get_node("%grid") as GridContainer # Reads the real native card container.
			for child: Node in grid.get_children(): # Finds an actual visible owned card after filtering.
				if child is CollectionItem and (child as CollectionItem).visible: # Excludes missing or filtered designs.
					_selected_card = child as CollectionItem # Remembers the modal opener.
					break # Uses the first real collected design.
			_check(_selected_card != null, "owned filter exposes granted designs") # Confirms the collection reflects pack rewards.
			_card_id = _selected_card.get_instance_id() # Records card identity for cache verification.
			_inspection_before = JSON.stringify(_state.get_placements_copy()) # Captures saved book state before inspection.
			_click(_selected_card) # Opens the selected artwork through its native card button.
		12: # Exercises inspection navigation and temporary rotation.
			var inspection: StickerInspection = _ui.get_node("%sticker_inspection") as StickerInspection # References the actual modal stage.
			_check(inspection.is_open(), "owned collection cards open the 3D inspector") # Verifies the new collection interaction.
			_key(KEY_TAB) # Moves from close to the native zoom toolbar.
			_check(inspection.is_ancestor_of(root.gui_get_focus_owner()), "inspection tab navigation stays inside its toolbar") # Catches the old all-input swallowing behavior.
			_key(KEY_Q) # Applies a real keyboard roll to the temporary mesh.
			_click(_button(inspection, "bottom_bar/zoom_in")) # Activates native zoom through the toolbar.
		13: # Verifies inspection never mutates physical book persistence.
			_check(JSON.stringify(_state.get_placements_copy()) == _inspection_before, "inspection leaves saved placements unchanged") # Protects canonical book orientation.
			_click(_button(_ui.get_node("%sticker_inspection"), "top_bar/content/close")) # Closes inspection through native release activation.
		14: # Verifies exact focus restoration and native text-entry behavior.
			_check(root.gui_get_focus_owner() == _selected_card, "closing inspection restores the exact collection card") # Preserves the player's place in the collection.
			var search: LineEdit = _ui.get_node("%collection_browser").get_node("%search") as LineEdit # References native collection search.
			search.grab_focus() # Enters text editing explicitly.
			search.text = "no matching sticker" # Selects a query with no catalogue results.
			search.caret_column = search.text.length() # Positions the caret for a native space key.
			_key(KEY_SPACE, 32) # Verifies space is treated as text rather than global confirmation.
		15: # Verifies empty-state recovery and text editing.
			var browser: CollectionBrowser = _ui.get_node("%collection_browser") as CollectionBrowser # References the active browser.
			_check((browser.get_node("%search") as LineEdit).text.ends_with(" "), "space remains editable in collection search") # Prevents global confirm from swallowing native text entry.
			_check(_visible(browser, "%empty_state"), "empty search results provide a recovery state") # Checks the searchable collection's empty state.
			_click(_button(browser, "%clear_filter")) # Uses the visible recovery action.
		16: # Returns to pending rewards and resolves them automatically.
			_check(not _visible(_ui.get_node("%collection_browser"), "%empty_state"), "clear filters restores collection results") # Confirms empty-state recovery.
			_click(_button(_ui, "%nav_shop")) # Returns to the existing pending pack.
		17: # Uses the native auto-place action.
			_click(_button(_shop.get_ui(), "%auto_button")) # Invokes the existing silhouette packing flow.
		18: # Verifies reward placement and checks full-book camera bounds.
			_check(_book.visible and _state.get_pending_count() == 0 and _state.get_placement_count() == 5, "auto-place saves every copy and opens the book") # Checks copy conservation through the main loop.
			_check(not _visible(_book.get_ui(), "%empty"), "first placement dismisses book onboarding") # Prevents tutorial overlays covering a populated book.
			_check_book_frame() # Verifies the physical cover fits the reserved UI region.
			_click(_button(_ui, "%nav_shop")) # Opens the shop for a free-pack eligibility check.
		19: # Claims the free pack through native button semantics.
			_click(_button(_shop.get_ui(), "%free_button")) # Exercises the real free-reward transaction path.
		20: # Enters manual placement from a keyboard-accessible reward choice.
			_pending_before = _state.get_pending_count() # Captures unresolved copies before a cancelable placement.
			_check(_pending_before == 5 and _economy.get_currency() == 400, "claiming a free pack grants copies without spending coins") # Checks the free transaction's exact behavior.
			_owned_before = _state.get_placement_count() # Records already placed copies for conservation checks.
			_shop.get_ui().focus_primary() # Selects the first exact pending copy.
			_action("Button_A") # Confirms via the project's real controller action.
		21: # Cancels manual placement through conventional back behavior.
			_check(_book.has_manual_placement(), "controller confirmation enters manual placement") # Verifies accessible pack-result selection.
			_key(KEY_ESCAPE) # Cancels placement through the global back action.
		22: # Verifies cancelling placement preserves the unresolved copy.
			_check(_shop.visible and not paused and _state.get_pending_count() == _pending_before, "escape cancels placement without losing the selected copy") # Protects the cancellation flow.
			_shop.get_ui().focus_primary() # Selects the same unresolved pack again.
			_action("Button_A") # Re-enters manual placement through native controller dispatch.
		23: # Commits a real mouse-positioned manual placement.
			var camera: Camera3D = _book.get_node("world/camera") as Camera3D # Reads the active book projection.
			var point: Vector2 = camera.unproject_position(Vector3(-3.0, StickerBookLayout.PAGE_SURFACE_Y, 0.0)) # Targets a legal position inside the left page.
			_motion(point) # Moves the actual pending sticker preview onto the page.
			_mouse(point, true) # Commits placement through physical world input after GUI dispatch.
			_mouse(point, false) # Completes the pointer gesture.
		24: # Verifies manual placement consumes exactly one copy.
			_check(_shop.visible and _state.get_pending_count() == _pending_before - 1 and _state.get_placement_count() == _owned_before + 1, "manual placement saves one copy and returns to the remaining pack") # Checks the manual branch of the main loop.
			_game.auto_stick_pending(true) # Resolves remaining copies before checking cooldown UI.
		25: # Returns to the shop with the free reward now on cooldown.
			_game.show_shop() # Opens the purchase state after resolving the current pack.
		26: # Verifies native disabled free-pack behavior.
			_check(_button(_shop.get_ui(), "%free_button").disabled, "free pack remains disabled during cooldown") # Checks visible eligibility state.
			_click(_button(_shop.get_ui(), "%free_button")) # Attempts to activate the disabled native control.
			_check(_state.get_pending_count() == 0, "disabled free-pack click grants no additional copies") # Verifies the native disabled guard and transaction state.
			_game.show_collection() # Reopens cached collection content after multiple progress changes.
		27: # Verifies collection reuse and starts narrow-window layout checks.
			_check(is_instance_id_valid(_card_id), "collection navigation reuses existing card instances") # Protects the no-rebuild caching behavior.
			root.size = Vector2i(960, 640) # Exercises the minimum supported desktop viewport.
		28: # Verifies narrow collection layout and switches to narrow shop offers.
			_check_screen_bounds(_ui.get_node("%collection_browser")) # Checks native interactive bounds within their scroll clipping.
			_game.show_shop() # Exercises offers at the same narrow width.
		29: # Verifies narrow shop layout and switches to narrow book framing.
			_check_screen_bounds(_shop.get_ui()) # Checks offers and footer actions fit the supported viewport.
			_game.show_book() # Exercises physical camera fitting at the narrow aspect ratio.
		30: # Verifies camera bounds and title-screen layout at the minimum size.
			_check_book_frame() # Ensures the whole book remains clear of persistent chrome.
			_game.show_main_menu() # Exercises the title composition at the same narrow size.
		31: # Completes layout checks and reports the behavioral outcome.
			_check_screen_bounds(_ui.get_node("%main_menu")) # Verifies native title-screen actions stay on screen.
			_game.show_shop() # Checks pending-result layout at the same minimum window size.
		32: # Opens another real pack for narrow reward-label checks.
			_click(_button(_shop.get_ui(), "%buy_button")) # Creates real reward choices through native input.
		33: # Verifies that result actions never overlap at the narrow supported width.
			var choices: Array[Node] = _shop.get_ui().get_node("%results").get_children() # Reads the actual focusable result row.
			_check(choices.size() == 5, "narrow shop shows every pending-copy action") # Protects access to every revealed sticker.
			for index: int in range(choices.size()): # Checks each native projected choice rectangle.
				var rect: Rect2 = (choices[index] as Control).get_global_rect() # Reads the native computed reward-label bounds.
				_check(root.get_visible_rect().encloses(rect), "reward action stays inside the narrow viewport") # Prevents labels from being clipped by resizing.
				if index > 0: # Compares adjacent reward actions after responsive projection.
					_check(not rect.intersects((choices[index - 1] as Control).get_global_rect()), "neighboring reward actions do not overlap") # Protects unambiguous pointer and focus targets.
			_game.auto_stick_pending(true) # Resolves the pack before physical gesture regression checks.
		34: # Starts a physical sticker peel through the normal input pipeline.
			var sticker: Sticker = _book.get_node("world/stickers").get_child(0) as Sticker # Selects an actual landed physical sticker.
			var camera: Camera3D = _book.get_node("world/camera") as Camera3D # Reads the active responsive book projection.
			_gesture_point = camera.unproject_position(sticker.global_position) # Targets the actual physical sheet.
			_mouse(_gesture_point, true) # Starts the world's click-or-drag candidate.
			_motion(_gesture_point + Vector2(95, 50)) # Crosses the real peel threshold through pointer motion.
		35: # Pauses an active peel without leaving stale gesture ownership.
			_check(_book.get("_active_sticker") != null, "dragging a physical book sticker starts peeling") # Confirms the real physical interaction path remains usable.
			_action("Button_Start") # Pauses while the world owns an active gesture.
			_check(paused and _book.get("_active_sticker") == null, "pausing safely releases an active peel") # Protects against stuck drags after modal input takeover.
			_mouse(_gesture_point + Vector2(95, 50), false) # Releases the physical button while the modal owns input.
		36: # Resumes and tests releasing an existing world gesture over the navigation rail.
			_key(KEY_ESCAPE) # Resumes from the pause modal.
			var sticker: Sticker = _book.get_node("world/stickers").get_child(0) as Sticker # Uses the same persisted physical book instance.
			_gesture_point = (_book.get_node("world/camera") as Camera3D).unproject_position(sticker.global_position) # Reprojects its current saved position.
			_mouse(_gesture_point, true) # Starts a new physical pointer candidate.
			_motion(_gesture_point + Vector2(80, 45)) # Begins a peel before moving across UI.
			_motion(Vector2(70, 360)) # Moves the pointer onto persistent navigation.
			_mouse(Vector2(70, 360), false) # Releases over the native rail instead of the physical world.
		37: # Completes the critical UI and gesture regression scenario.
			_check(_book.get("_active_sticker") == null and _book.get("_pressed_sticker") == null, "releasing over the navigation rail never strands a peel") # Checks gesture cleanup across GUI ownership boundaries.
			_check(_state.get_placement_count() == 15 and _state.get_pending_count() == 0, "all granted copies remain placed after navigation and gesture checks") # Verifies progression conservation across the complete scenario.
			print("ui_flow_test: %d checks, %d failures" % [_checks, _failures]) # Reports the regression result concisely.
			quit(1 if _failures > 0 else 0) # Returns a meaningful process status for local or CI verification.
	_stage += 1 # Advances to the next interaction after deferred engine work.
	return false # Keeps SceneTree processing active until the scenario completes.

func _button(owner: Node, path: String) -> GameButton: # Resolves a real editor-authored native control.
	return owner.get_node(NodePath(path)) as GameButton # Uses NodePath explicitly for scene lookup.

func _visible(owner: Node, path: String) -> bool: # Reads effective visibility including hidden ancestor pages.
	return (owner.get_node(NodePath(path)) as Control).is_visible_in_tree() # Distinguishes a hidden route from a locally visible child.

func _click(button: GameButton) -> void: # Simulates a native pointer press and release on a control.
	var position: Vector2 = button.get_global_rect().get_center() # Targets the actual container-computed button rectangle.
	_motion(position) # Updates native hover ownership before pressing.
	_mouse(position, true) # Begins the native cancelable button gesture.
	_mouse(position, false) # Releases to activate through Godot's real GUI path.

func _mouse(position: Vector2, pressed: bool) -> void: # Sends pointer events through the real root viewport.
	var event: InputEventMouseButton = InputEventMouseButton.new() # Constructs a native mouse-button event.
	event.button_index = MOUSE_BUTTON_LEFT # Uses the player's primary interaction button.
	event.position = position # Supplies logical viewport coordinates.
	event.global_position = position # Keeps global pointer coordinates consistent with the local viewport.
	event.pressed = pressed # Selects press or release behavior.
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0 # Preserves native held-button state.
	root.push_input(event, true) # Exercises _input, native GUI handling, and _unhandled_input in their real order.

func _motion(position: Vector2) -> void: # Moves the native pointer for hover and manual-placement input.
	var event: InputEventMouseMotion = InputEventMouseMotion.new() # Constructs an ordinary native motion event.
	event.position = position # Uses logical viewport coordinates after resize.
	event.global_position = position # Matches local and global pointer coordinates.
	root.push_input(event, true) # Sends movement through the actual scene input pipeline.

func _key(code: Key, unicode_value: int = 0) -> void: # Sends a complete native keyboard gesture.
	for pressed: bool in [true, false]: # Includes both press and release for native button semantics.
		var event: InputEventKey = InputEventKey.new() # Constructs a real keyboard input event.
		event.keycode = code # Supplies the logical key used by the UI.
		event.unicode = unicode_value # Supports actual text entry in the native LineEdit.
		event.pressed = pressed # Selects the current half of the keyboard gesture.
		root.push_input(event, true) # Exercises global handling and native focus or text input.

func _action(name: String) -> void: # Exercises the project's named controller actions directly.
	for pressed: bool in [true, false]: # Sends complete action state transitions.
		var event: InputEventAction = InputEventAction.new() # Creates a native named input action.
		event.action = StringName(name) # Keeps action identifiers strongly typed independently of NodePath lookups.
		event.pressed = pressed # Selects confirmation press or release.
		root.push_input(event, true) # Dispatches through the real global UI input owner.

func _check(condition: bool, message: String) -> void: # Records a concrete behavioral expectation without mirroring implementation internals.
	_checks += 1 # Counts completed behavioral assertions.
	if not condition: # Reports unexpected user-facing outcomes.
		_failures += 1 # Records a failing scenario for the final exit status.
		push_error("ui_flow_test: " + message) # Identifies the affected interaction precisely.

func _check_book_frame() -> void: # Checks the real projected book cover against persistent UI boundaries.
	var camera: Camera3D = _book.get_node("world/camera") as Camera3D # Uses the actual responsive physical camera.
	var safe: Rect2 = Rect2(Vector2(160, 64), root.get_visible_rect().size - Vector2(160, 148)) # Defines the unobstructed gameplay rectangle.
	for corner: Vector3 in [Vector3(-5.65, 0, -3.675), Vector3(5.65, 0, -3.675), Vector3(-5.65, 0, 3.675), Vector3(5.65, 0, 3.675)]: # Samples every outer cover corner.
		_check(safe.has_point(camera.unproject_position(corner)), "physical book corner fits the unobstructed viewport") # Detects reversed offsets and narrow-window clipping.

func _check_screen_bounds(node: Node, clipped: bool = false) -> void: # Checks native actions while allowing intentionally scrollable collection content.
	if node is Control and not (node as Control).is_visible_in_tree(): # Excludes inactive destinations and filtered results.
		return # Skips the entire hidden subtree.
	if node is ScrollContainer: # Treats content below a scroll viewport as intentionally clipped.
		clipped = true # Avoids incorrectly flagging offscreen scroll items as layout overflow.
	if node is GameButton and not clipped: # Checks non-scrollable actions that must remain fully accessible.
		var rect: Rect2 = (node as Control).get_global_rect() # Reads the actual native computed button bounds.
		_check(root.get_visible_rect().grow(1.0).encloses(rect), "native action fits viewport: " + str(node.name)) # Detects inaccessible controls at the minimum supported window size.
	for child: Node in node.get_children(): # Traverses the visible composed interface.
		_check_screen_bounds(child, clipped) # Preserves intentional scroll clipping for descendants.
