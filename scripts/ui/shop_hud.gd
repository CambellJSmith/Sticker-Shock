class_name ShopHUD extends Control # Owns purchase offers, pack-result actions, and availability feedback.

const CHOICE_SCENE: PackedScene = preload("res://scenes/ui/reveal_choice.tscn") # Reuses a native keyboard-accessible pack-result action.

@onready var _offers: Control = %offer_center as Control # Displays purchase offers before opening a pack.
@onready var _results: Control = %results as Control # Holds actions aligned beneath physical reveal stickers.
@onready var _buy: GameButton = %buy_button as GameButton # Buys a pack using the existing in-game economy.
@onready var _free: GameButton = %free_button as GameButton # Claims a pack only when its cooldown has elapsed.
@onready var _auto: GameButton = %auto_button as GameButton # Places all unresolved copies through the existing packer.

var _controller: GameController # Delegates transactions and placement to the game owner.
var _economy: StickerEconomy # Reads price, currency, and free-pack eligibility.
var _catalog: StickerCatalog # Reads whether artwork is available for packs.
var _book_state: StickerBookState # Reads unresolved copies from the saved pack.
var _choices: Array[GameButton] = [] # Retains native controls for the current physical reveal.
var _targets: Array[Vector3] = [] # Stores world positions used to align actions with reveal artwork.
var _camera: Camera3D # Projects world reveal positions into HUD coordinates.
var _viewport_size: Vector2 = Vector2.ZERO # Avoids repeated projection work while the window is unchanged.
var _refresh_elapsed: float = 0.0 # Throttles countdown updates while the shop is visible.

func configure(controller: GameController, economy: StickerEconomy, catalog: StickerCatalog, book_state: StickerBookState) -> void: # Binds native actions once.
	_controller = controller # Retains authoritative transaction ownership.
	_economy = economy # Retains economy state for offer availability.
	_catalog = catalog # Retains the discovered artwork catalogue.
	_book_state = book_state # Retains the unresolved-copy model.
	_buy.bind_action(_purchase.bind(false)) # Buys only through the controller's transaction guards.
	_free.bind_action(_purchase.bind(true)) # Claims a free pack through the same authoritative flow.
	_auto.bind_action(_auto_place) # Uses the existing automatic packing implementation.
	(%book_button as GameButton).bind_action(controller.show_book) # Leaves the current pack safely pending when browsing the book.

func show_choices(paths: PackedStringArray, targets: Array[Vector3], camera: Camera3D) -> void: # Presents a clear reveal state and accessible placement actions.
	for choice: GameButton in _choices: # Retires controls from the previous unresolved-pack state.
		_results.remove_child(choice) # Removes stale controls from focus immediately.
		choice.queue_free() # Releases the old native button after dispatch completes.
	_choices.clear() # Clears expired references before rebuilding the changed pack.
	_targets = targets # Retains the physical reveal anchors.
	_camera = camera # Retains the active orthographic projection.
	var seen: Dictionary[String, bool] = {} # Marks only the first occurrence of each newly discovered design.
	for index: int in range(paths.size()): # Builds an action for each exact pending copy.
		var path: String = paths[index] # Reads the stable artwork key for this copy.
		var choice: GameButton = CHOICE_SCENE.instantiate() as GameButton # Creates a native focusable placement action.
		_results.add_child(choice) # Adds the action to the editor-authored result host.
		var is_new: bool = _controller.is_new_pack_design(path) and not seen.has(path) # Distinguishes discoveries from duplicates within the same pack.
		seen[path] = true # Records this design's first visible occurrence.
		choice.text = "%s%s\nplace in book" % ["new · " if is_new else "", UIFormat.sticker_name(path)] # Labels the physical result and its next action.
		choice.tooltip_text = "place %s · %d owned" % [UIFormat.sticker_name(path), _economy.get_owned_count(path)] # Explains the selected copy and duplicate count.
		choice.bind_action(_place_one.bind(index, path)) # Binds the exact pending index and resource identity.
		_choices.append(choice) # Retains the current focusable choices.
	_viewport_size = Vector2.ZERO # Forces projection after the result layout changes.
	refresh() # Switches between offers and the current reveal state.
	_update_choice_positions.call_deferred() # Projects after native containers settle.

func refresh() -> void: # Updates availability and explanatory text without rebuilding controls.
	var has_pending: bool = _book_state.has_pending_stickers() # Reads whether a pack is still unresolved.
	_offers.visible = not has_pending # Shows purchase offers only when another pack can be opened.
	_results.visible = has_pending # Shows placement actions only for real pending copies.
	_auto.visible = has_pending # Presents auto-placement only when it can do useful work.
	_auto.text = "place all %d in book" % _book_state.get_pending_count() # Makes the number of affected copies explicit.
	_buy.disabled = has_pending or not _economy.can_buy_pack(_catalog) # Enforces native disabled behavior before transaction dispatch.
	_free.disabled = has_pending or not _economy.can_claim_free_pack(_catalog) # Prevents early or duplicate free-pack claims.
	_buy.text = "open pack · %d coins" % _economy.get_pack_price() # Shows the exact in-game price before activation.
	var missing_coins: int = maxi(_economy.get_pack_price() - _economy.get_currency(), 0) # Computes actionable affordability feedback.
	(%standard_detail as Label).text = "need %d more coins" % missing_coins if missing_coins > 0 else "%d stickers per pack" % _economy.get_pack_size() # Explains affordability rather than leaving an unexplained disabled button.
	var remaining: int = _economy.get_free_pack_seconds_remaining() # Reads the real-world free-pack timer.
	(%free_detail as Label).text = "ready when you are" if remaining <= 0 else "ready in %s" % UIFormat.duration(remaining) # Explains both eligible and cooldown states.
	_free.text = "claim free pack" if remaining <= 0 else "come back for your free pack" # Avoids presenting an unavailable claim as actionable.
	(%heading as Label).text = "look what you found" if has_pending else "a little surprise for your book" # Distinguishes the reward reveal from the shop's purchase state.
	(%subtitle as Label).text = "choose a sticker to place it yourself, or place them all together." if has_pending else "five random stickers in every pack. duplicates are part of the fun." # Explains the next step for the current flow.
	(%status as Label).text = "%d stickers waiting for a home" % _book_state.get_pending_count() if has_pending else "your next favourite could be in here" # Shows one concise footer status.
	if _catalog.is_empty(): # Handles a project with no compatible artwork gracefully.
		(%status as Label).text = "no stickers available yet" # Explains why both purchase actions are unavailable.

func focus_primary() -> void: # Selects the next useful shop action for keyboard and controller users.
	if not _choices.is_empty(): # Prioritizes resolving an opened pack.
		_choices[0].grab_focus() # Selects the first exact pending copy.
	elif not _free.disabled: # Prioritizes an available free reward.
		_free.grab_focus() # Selects the claim action without activating it.
	elif not _buy.disabled: # Offers a paid pack when it is affordable.
		_buy.grab_focus() # Selects the visible priced action.
	else: # Keeps focus useful when every offer is unavailable.
		(%book_button as GameButton).grab_focus() # Allows returning to the book from the keyboard.

func owns_pointer(position: Vector2) -> bool: # Reserves shop controls from physical result picking.
	if (%footer as Control).get_global_rect().has_point(position): # Includes non-button space inside the footer.
		return true # Prevents footer clicks from selecting underlying reveal geometry.
	if _offers.visible: # Treats the offer composition as screen-space interaction.
		return true # Leaves purchase behavior entirely with native buttons.
	for choice: GameButton in _choices: # Checks only the current small set of result controls.
		if choice.get_global_rect().has_point(position): # Detects a native placement button beneath its physical sticker.
			return true # Prevents duplicate activation through the 3D picking path.
	return false # Allows direct clicks on unobstructed physical reveal artwork.

func _process(delta: float) -> void: # Refreshes only visible countdowns and changed window geometry.
	if not is_visible_in_tree() or _economy == null: # Avoids polling hidden shop content.
		return # Leaves inactive HUDs idle.
	_refresh_elapsed += delta # Accumulates time between timer-label updates.
	if _refresh_elapsed >= 1.0: # Limits countdown presentation work.
		_refresh_elapsed = 0.0 # Starts the next timer interval.
		refresh() # Updates availability when the real-world timer expires.
	if _results.visible and _viewport_size != get_viewport_rect().size: # Reprojects only when result layout or window size changes.
		_update_choice_positions() # Keeps labels aligned with their physical artwork.

func _update_choice_positions() -> void: # Aligns native actions beneath the actual orthographic reveal positions.
	if _camera == null: # Handles the interval before the first configured reveal.
		return # Defers projection until a camera exists.
	_viewport_size = get_viewport_rect().size # Caches the current logical viewport geometry.
	var spacing: float = absf(_camera.unproject_position(_camera.global_position + Vector3(2.15, -12.0, 0.0)).x - _camera.unproject_position(_camera.global_position + Vector3(0.0, -12.0, 0.0)).x) # Measures the actual projected spacing between physical reward positions.
	for index: int in range(_choices.size()): # Projects each pending sticker's fixed display anchor.
		_choices[index].size = Vector2(maxf(spacing - 12.0, 100.0), 64.0) # Fits each label between neighboring stickers at narrow window sizes.
		var screen_position: Vector2 = _camera.unproject_position(_targets[index] + Vector3(0.0, 0.0, 1.55)) # Places the action beneath its reveal artwork.
		_choices[index].position = screen_position - _results.global_position - Vector2(_choices[index].size.x * 0.5, 0.0) # Converts the viewport point to the native result host's local coordinates.

func _purchase(use_free_pack: bool) -> void: # Opens a pack through the existing guarded transaction flow.
	if not _controller.purchase_pack(use_free_pack): # Handles a changed cooldown or unavailable purchase gracefully.
		refresh() # Reflects authoritative availability after a rejected action.
		return # Prevents presenting a reward that was never granted.
	focus_primary.call_deferred() # Moves focus from the hidden offer to the new pack choices.

func _place_one(index: int, path: String) -> void: # Places the exact selected pending copy manually.
	if not _controller.begin_manual_placement(index, path): # Handles unavailable artwork or a sticker that cannot fit.
		(%status as Label).text = "this sticker could not be placed. try another one." # Keeps failure visible without losing the pack.

func _auto_place() -> void: # Resolves all pending copies through the existing silhouette packer.
	_controller.auto_stick_pending(true) # Delegates packing, saving, and book transition to the controller.
