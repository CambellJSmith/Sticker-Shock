class_name ShopHUD extends Control # Owns purchase offers, pack selection, Unique code redemption, reveal-only results, and availability feedback.

const CHOICE_SCENE: PackedScene = preload("res://scenes/ui/reveal_choice.tscn") # Reuses a native result label beneath each revealed sticker.

@onready var _offers: Control = %offer_center as Control # Displays purchase, free-pack, and Unique-code offers before opening a reward.
@onready var _results: Control = %results as Control # Holds labels aligned beneath physical reveal stickers.
@onready var _buy: GameButton = %buy_button as GameButton # Buys the currently selected authored pack using the existing in-game economy.
@onready var _free: GameButton = %free_button as GameButton # Claims a random authored pack only when its cooldown has elapsed.
@onready var _auto: GameButton = %auto_button as GameButton # Finishes the current reveal and returns to acquisition offers.
@onready var _pack_selector: OptionButton = %pack_selector as OptionButton # Lets the player choose which authored pack a paid purchase opens.
@onready var _code_input: LineEdit = %code_input as LineEdit # Accepts the exact case-sensitive Name of a Unique sticker.
@onready var _redeem: GameButton = %redeem_button as GameButton # Attempts one-time Unique code redemption through the shop world.

var _shop_world: ShopWorld # Owns transient physical reveal construction.
var _controller: GameController # Delegates normal pack transactions to the game owner.
var _economy: StickerEconomy # Reads price, currency, selected pack, free-pack eligibility, and Unique redemption state.
var _catalog: StickerCatalog # Reads authored pack names, sticker metadata, and Unique code matches.
var _choices: Array[GameButton] = [] # Retains native result labels for the current reveal.
var _targets: Array[Vector3] = [] # Stores world positions used to align labels with reveal artwork.
var _camera: Camera3D # Projects world reveal positions into HUD coordinates.
var _viewport_size: Vector2 = Vector2.ZERO # Avoids repeated projection work while the window is unchanged.
var _refresh_elapsed: float = 0.0 # Throttles countdown updates while the shop is visible.
var _last_pack_selection: int = -1 # Tracks OptionButton state without relying on signals.

func configure(shop_world: ShopWorld, controller: GameController, economy: StickerEconomy, catalog: StickerCatalog, _book_state: StickerBookState) -> void: # Binds native actions once.
	_shop_world = shop_world # Retains the physical shop owner for reveal construction and completion.
	_controller = controller # Retains authoritative normal transaction ownership.
	_economy = economy # Retains economy state for offer availability and code redemption checks.
	_catalog = catalog # Retains the discovered authored sticker catalogue.
	_buy.bind_action(_purchase.bind(false)) # Buys only through the controller's transaction guards.
	_free.bind_action(_purchase.bind(true)) # Claims a free random pack through the same authoritative flow.
	_redeem.bind_action(_redeem_unique_code) # Redeems exact Unique sticker names directly into the collection.
	_auto.bind_action(_finish_reveal) # Dismisses only the visual reveal; collected ownership remains untouched.
	(%book_button as GameButton).bind_action(controller.show_book) # Lets the player browse the book without changing collection ownership.
	_rebuild_pack_selector() # Populates the paid-pack selector from authored packs containing normal-pull stickers.
	refresh() # Initializes offer availability and explanatory text after all controls have valid data.

func show_choices(paths: PackedStringArray, targets: Array[Vector3], camera: Camera3D) -> void: # Presents collected reward labels without any placement actions.
	for choice: GameButton in _choices: # Retires controls from the previous reveal state.
		_results.remove_child(choice) # Removes stale controls from focus immediately.
		choice.queue_free() # Releases the old native button after dispatch completes.
	_choices.clear() # Clears expired references before rebuilding the changed reward.
	_targets = targets # Retains the physical reveal anchors.
	_camera = camera # Retains the active orthographic projection.
	var seen: Dictionary[String, bool] = {} # Marks only the first occurrence of each newly discovered design.
	for path: String in paths: # Builds one non-destructive result label for each collected copy.
		var choice: GameButton = CHOICE_SCENE.instantiate() as GameButton # Reuses the existing result control for consistent styling.
		_results.add_child(choice) # Adds the label to the editor-authored result host.
		var is_new: bool = _controller.is_new_pack_design(path) and not seen.has(path) # Distinguishes normal-pack discoveries from duplicates within the same reveal.
		seen[path] = true # Records this design's first visible occurrence.
		choice.text = "%s%s\nadded to collection" % ["new · " if is_new else "", UIFormat.sticker_name(path)] # Makes the new collection-only flow explicit.
		choice.tooltip_text = "%d owned · place from collection" % _economy.get_owned_count(path) # Points the player to the only route that can add it to the book.
		choice.disabled = true # Prevents any revealed sticker from directly initiating book placement.
		_choices.append(choice) # Retains the current result label for projection.
	_viewport_size = Vector2.ZERO # Forces projection after the result layout changes.
	refresh() # Switches between offers and the current reveal state.
	_update_choice_positions.call_deferred() # Projects after native containers settle.

func refresh() -> void: # Updates availability and explanatory text without rebuilding controls.
	_sync_pack_selection() # Applies any OptionButton change to the economy before evaluating purchase availability.
	var has_reveal: bool = _shop_world.has_reward_reveal() # Reads only transient shop presentation state.
	_offers.visible = not has_reveal # Shows acquisition offers when no collected reward is being displayed.
	_results.visible = has_reveal # Shows result labels only while the reward is visible.
	_auto.visible = has_reveal # Presents a single reveal-completion action.
	_auto.text = "continue" # Makes it clear this only dismisses the reveal.
	_pack_selector.disabled = has_reveal or _pack_selector.item_count == 0 # Prevents pack-selection changes while the current reward is being viewed.
	_buy.disabled = has_reveal or not _economy.can_buy_pack(_catalog) # Enforces native disabled behavior before a paid selected-pack transaction.
	_free.disabled = has_reveal or not _economy.can_claim_free_pack(_catalog) # Prevents another claim while viewing a reward or before the cooldown expires.
	_redeem.disabled = has_reveal or _code_input.text.is_empty() # Requires exact typed code input and no active reveal.
	_buy.text = "open %s · %d coins" % [_economy.get_selected_pack_name(), _economy.get_pack_price()] if not _economy.get_selected_pack_name().is_empty() else "choose a pack" # Shows the exact authored pack and shared price before activation.
	var missing_coins: int = maxi(_economy.get_pack_price() - _economy.get_currency(), 0) # Computes actionable affordability feedback.
	(%standard_detail as Label).text = "need %d more coins" % missing_coins if missing_coins > 0 else "%d stickers · all packs same price" % _economy.get_pack_size() # Explains affordability and common pricing.
	var remaining: int = _economy.get_free_pack_seconds_remaining() # Reads the real-world free-pack timer.
	(%free_detail as Label).text = "random pack ready" if remaining <= 0 else "random pack ready in %s" % UIFormat.duration(remaining) # Explains that every free claim selects its authored pack randomly.
	_free.text = "claim random free pack" if remaining <= 0 else "come back for your free pack" # Avoids presenting an unavailable claim as actionable.
	(%heading as Label).text = "added to your collection" if has_reveal else "choose your next stickers" # Distinguishes reveal from acquisition state.
	(%subtitle as Label).text = "these stickers are now in your collection. place them into the book whenever you want from the collection screen." if has_reveal else "paid packs are your choice. the six-hour free pack chooses a collection at random." # Explains the new collection-first placement behavior.
	(%status as Label).text = "nothing here is placed into the book automatically" if has_reveal else "Unique codes use the sticker Name exactly, including case" # Reinforces reveal-only behavior.
	if _catalog.get_pack_names().is_empty(): # Handles a project with no normal pack-eligible artwork gracefully.
		(%standard_detail as Label).text = "no normal packs available" # Explains why paid and free pack actions are unavailable.

func focus_primary() -> void: # Selects the next useful shop action for keyboard and controller users.
	if _shop_world.has_reward_reveal(): # Prioritizes finishing the current reveal.
		_auto.grab_focus() # Selects the single continue action instead of any sticker result.
	elif not _free.disabled: # Prioritizes an available free reward.
		_free.grab_focus() # Selects the claim action without activating it.
	elif not _buy.disabled: # Offers the selected paid pack when it is affordable.
		_buy.grab_focus() # Selects the visible priced action.
	else: # Keeps focus useful when every acquisition action is unavailable.
		(%book_button as GameButton).grab_focus() # Allows returning to the book from the keyboard.

func owns_pointer(position: Vector2) -> bool: # Reserves shop controls from physical reveal geometry.
	if (%footer as Control).get_global_rect().has_point(position): # Includes non-button space inside the footer.
		return true # Prevents footer clicks from reaching the physical scene.
	if _offers.visible: # Treats the offer composition as screen-space interaction.
		return true # Leaves purchase, selector, and code behavior entirely with native controls.
	for choice: GameButton in _choices: # Checks only the current small set of result labels.
		if choice.get_global_rect().has_point(position): # Detects a label beneath its physical sticker.
			return true # Prevents reveal geometry from receiving the same click.
	return false # Leaves noninteractive reveal artwork visually inspectable only.

func _process(delta: float) -> void: # Refreshes pack selection, visible countdowns, and changed window geometry without signals.
	if not is_visible_in_tree() or _economy == null: # Avoids polling hidden shop content.
		return # Leaves inactive HUDs idle.
	_sync_pack_selection() # Detects OptionButton changes immediately through its lightweight selected-index state.
	_redeem.disabled = _shop_world.has_reward_reveal() or _code_input.text.is_empty() # Keeps code-button availability responsive while the player types without text signals.
	_refresh_elapsed += delta # Accumulates time between timer-label updates.
	if _refresh_elapsed >= 1.0: # Limits countdown presentation work.
		_refresh_elapsed = 0.0 # Starts the next timer interval.
		refresh() # Updates availability when the real-world timer expires.
	if _results.visible and _viewport_size != get_viewport_rect().size: # Reprojects only when result layout or window size changes.
		_update_choice_positions() # Keeps labels aligned with their physical artwork.

func _rebuild_pack_selector() -> void: # Populates the native paid-pack selector from currently valid authored normal packs.
	_pack_selector.clear() # Removes stale authored pack options before rebuilding from catalogue state.
	var pack_names: PackedStringArray = _catalog.get_pack_names() # Reads every authored pack containing at least one normal weighted-rarity sticker.
	for pack_name: String in pack_names: # Adds each stable sorted authored pack exactly once.
		_pack_selector.add_item(pack_name) # Uses the authored pack name directly as the visible selection text.
	if _pack_selector.item_count <= 0: # Handles projects containing only Unique stickers or no sticker content.
		_last_pack_selection = -1 # Clears selection tracking when no paid pack can be chosen.
		_economy.set_selected_pack_name("", _catalog) # Clears transient economy selection so purchase guards remain authoritative.
		return # Leaves the empty OptionButton disabled through refresh.
	var selected_index: int = 0 # Defaults a fresh session to the first sorted authored pack.
	var existing_selection: String = _economy.get_selected_pack_name() # Reads any valid transient selection established earlier in this session.
	for index: int in range(_pack_selector.item_count): # Searches the small authored pack list for the existing selection.
		if _pack_selector.get_item_text(index) == existing_selection: # Preserves a valid existing choice when rebuilding controls.
			selected_index = index # Retains the matching authored pack index.
			break # Stops after the first exact controlled pack-name match.
	_pack_selector.select(selected_index) # Selects the resolved default or existing authored pack in the native control.
	_last_pack_selection = selected_index # Synchronizes polling state before the next process frame.
	_economy.set_selected_pack_name(_pack_selector.get_item_text(selected_index), _catalog) # Makes the visible selection authoritative for the next paid purchase.

func _sync_pack_selection() -> void: # Applies native OptionButton changes to the economy without using signals.
	if _pack_selector.item_count <= 0: # Rejects polling when there are no authored pack options.
		return # Leaves the economy's selected pack cleared.
	var selected_index: int = _pack_selector.selected # Reads the native control's current selection using constant-time state access.
	if selected_index < 0 or selected_index >= _pack_selector.item_count or selected_index == _last_pack_selection: # Rejects invalid or unchanged selected indices.
		return # Avoids redundant catalogue validation and assignment.
	_last_pack_selection = selected_index # Records the new index before applying the authored pack selection.
	_economy.set_selected_pack_name(_pack_selector.get_item_text(selected_index), _catalog) # Makes the newly chosen authored pack the paid-purchase target.

func _update_choice_positions() -> void: # Aligns native labels beneath the actual orthographic reveal positions.
	if _camera == null: # Handles the interval before the first configured reveal.
		return # Defers projection until a camera exists.
	_viewport_size = get_viewport_rect().size # Caches the current logical viewport geometry.
	var spacing: float = absf(_camera.unproject_position(_camera.global_position + Vector3(2.15, -12.0, 0.0)).x - _camera.unproject_position(_camera.global_position + Vector3(0.0, -12.0, 0.0)).x) # Measures the actual projected spacing between physical reward positions.
	for index: int in range(_choices.size()): # Projects each revealed sticker's fixed display anchor.
		_choices[index].size = Vector2(maxf(spacing - 12.0, 100.0), 64.0) # Fits each label between neighboring stickers at narrow window sizes.
		var screen_position: Vector2 = _camera.unproject_position(_targets[index] + Vector3(0.0, 0.0, 1.55)) # Places the label beneath its reveal artwork.
		_choices[index].position = screen_position - _results.global_position - Vector2(_choices[index].size.x * 0.5, 0.0) # Converts the viewport point to the native result host's local coordinates.

func _purchase(use_free_pack: bool) -> void: # Opens either the selected paid pack or a randomly chosen six-hour free pack through the existing guarded transaction flow.
	_sync_pack_selection() # Ensures the latest visible paid-pack choice reaches the economy before transaction dispatch.
	if not _controller.purchase_pack(use_free_pack): # Handles changed funds, cooldown, content, placement, or reveal-state availability gracefully.
		refresh() # Reflects authoritative availability after a rejected action.
		return # Prevents presenting a reward that was never granted.
	focus_primary.call_deferred() # Moves focus from the hidden offer to the continue action.

func _redeem_unique_code() -> void: # Attempts an exact case-sensitive one-time Unique sticker code redemption directly into the collection.
	if _shop_world.has_reward_reveal(): # Prevents replacement of a reward still being viewed.
		(%code_detail as Label).text = "finish viewing your current stickers first" # Explains the transient reveal guard without consuming the typed code.
		return # Leaves the current reveal untouched.
	var code: String = _code_input.text # Reads the text exactly as entered without trimming or changing case.
	var matching_path: String = _catalog.get_unique_sticker_path_by_code(code) # Checks exact case-sensitive Unique Name matching before mutation.
	if matching_path.is_empty(): # Rejects incorrect case, unknown names, and non-Unique sticker names.
		(%code_detail as Label).text = "code not found · names are case sensitive" # Gives precise corrective feedback without revealing other codes.
		return # Leaves ownership and redemption state unchanged.
	var sticker_id: int = _catalog.get_sticker_id(matching_path) # Resolves the stable Unique identity used for one-time redemption persistence.
	if _economy.has_redeemed_unique(sticker_id): # Detects a valid code already claimed on this progression save.
		(%code_detail as Label).text = "this Unique code has already been redeemed" # Explains the one-time claim rule directly.
		return # Leaves ownership unchanged instead of granting duplicate code copies.
	var rewarded_path: String = _shop_world.redeem_unique_code(code) # Atomically grants ownership, persists redemption, and starts a reveal-only result.
	if rewarded_path.is_empty(): # Handles an unexpected changed state between validation and transaction.
		(%code_detail as Label).text = "code could not be redeemed right now" # Keeps failure visible without clearing the player's input.
		return # Leaves the shop in its authoritative current state.
	_code_input.clear() # Removes the successfully consumed code from the text field.
	(%status as Label).text = "Unique sticker added to your collection" # Confirms the successful collection grant.
	_controller.get_node("game_ui").notify_progress_changed() if _controller.has_node("game_ui") else null # Refreshes collection progress after the code grant when the composed UI is available.
	focus_primary.call_deferred() # Moves focus to the reveal completion action.

func _finish_reveal() -> void: # Dismisses only the visual reward presentation.
	_shop_world.dismiss_reward() # Leaves every rewarded copy owned in the collection and returns to acquisition offers.
	focus_primary.call_deferred() # Selects the next useful shop action after the reveal disappears.
