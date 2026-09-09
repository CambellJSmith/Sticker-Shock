class_name ShopWorld extends Node3D # Owns reveal-only pack presentation while its HUD owns native shop actions.

@onready var _camera: Camera3D = $world/camera as Camera3D # Projects the flat physical reveal into the usable screen area.
@onready var _environment_node: WorldEnvironment = $world/environment as WorldEnvironment # Owns shop-specific lighting and background.
@onready var _interface: CanvasLayer = $interface as CanvasLayer # Controls the composed shop HUD's visibility.
@onready var _hud: ShopHUD = $interface/shop_hud as ShopHUD # Delegates purchase presentation and result actions to native controls.
@onready var _reveal_root: Node3D = $world/reveals as Node3D # Owns physical reveal sheets for the current collected reward.

var _controller: GameController # Delegates economy mutations and world transitions.
var _environment_resource: Environment # Preserves the shop environment while its world is inactive.
var _economy: StickerEconomy # Owns purchases, free-pack claims, and persistent Unique code redemption.
var _catalog: StickerCatalog # Supplies original artwork, authored metadata, and physical dimensions.
var _active: bool = false # Guards hidden-world processing.
var _reveal_nodes: Array[PackRevealSticker] = [] # Tracks the current physical result sheets.
var _revealed_paths: PackedStringArray = PackedStringArray() # Stores transient exact copy identities; ownership already lives in the collection.

func configure(controller: GameController, economy: StickerEconomy, catalog: StickerCatalog, _book_state: StickerBookState) -> void: # Binds authoritative models and the independent HUD.
	_controller = controller # Retains physical shop owner for reveal construction and completion.
	_environment_resource = _environment_node.environment # Preserves the environment for later activation.
	_economy = economy # Retains economy ownership for Unique code redemption coordinated by this shop world.
	_catalog = catalog # Retains the imported artwork catalogue.
	_hud.configure(self, controller, economy, catalog, _book_state) # Binds native offers, pack selection, code redemption, and reveal completion actions.
	show_reward(PackedStringArray(), false) # Initializes an empty reveal-only presentation.

func set_active(active: bool) -> void: # Transfers camera, rendering, and input ownership between worlds.
	_active = active # Updates the hidden-world processing guard.
	visible = active # Shows or hides the physical counter and sticker sheets.
	_interface.visible = active # Shows only the active world's screen-space HUD.
	_camera.current = active # Transfers orthographic camera ownership.
	_environment_node.environment = _environment_resource if active else null # Avoids competing world environments.
	process_mode = Node.PROCESS_MODE_INHERIT if active else Node.PROCESS_MODE_DISABLED # Stops hidden reveal animation and HUD polling.
	if active: # Refreshes the current transient reveal or acquisition offers on shop entry.
		_hud.refresh() # Keeps the existing reveal visible without converting it into book-placement state.

func redeem_unique_code(code: String) -> String: # Redeems one exact case-sensitive Unique sticker directly into the collection and reveal-only shop presentation.
	if has_reward_reveal(): # Prevents a new code reward from replacing a reveal the player has not finished viewing.
		return "" # Leaves the typed code and current reveal untouched.
	var sticker_path: String = _economy.redeem_unique_code(_catalog, code) # Performs the one-time persistent code validation and ownership grant.
	if sticker_path.is_empty(): # Rejects invalid, wrong-case, non-Unique, or previously redeemed codes.
		return "" # Leaves the shop presentation unchanged.
	show_reward(PackedStringArray([sticker_path]), true) # Shows the collected normal-edition Unique without creating any physical-book pending state.
	return sticker_path # Reports the rewarded identity so the HUD can show successful redemption feedback.

func show_reward(paths: PackedStringArray, animate_throw: bool) -> void: # Rebuilds a transient collection reward reveal while preserving each exact edition.
	_clear_reveal() # Retires physical sheets belonging to the previous reveal.
	_revealed_paths = paths.duplicate() # Keeps an independent transient copy of the collected edition identities.
	if animate_throw and not _revealed_paths.is_empty(): # Treats only a newly committed gameplay reward as an achievement synchronization point, not empty setup or restored presentation.
		SteamAchievements.sync_progress() # Re-evaluates collection, rarity, pack, Unique, duplicate, and premium-edition rules after authoritative ownership has already been persisted.
	var global_targets: Array[Vector3] = [] # Aligns native result labels with the physical reveal anchors.
	for index: int in range(_revealed_paths.size()): # Creates a separate sheet for each collected copy.
		var sticker_key: String = _revealed_paths[index] # Reads this copy's exact inventory identity.
		var artwork_path: String = StickerVariant.get_art_path(sticker_key) # Resolves the authored texture shared by every edition.
		var texture: Texture2D = load(artwork_path) as Texture2D # Reuses the imported artwork texture.
		if texture == null: # Handles missing imported artwork without a broken mesh.
			global_targets.append(global_position + Vector3(float(index - 2) * 2.15, 0.6, 0.0)) # Keeps HUD result-index mapping intact.
			continue # Leaves unavailable artwork represented by its text label.
		var target: Vector3 = Vector3((float(index) - float(_revealed_paths.size() - 1) * 0.5) * 2.15, 0.65, 0.0) # Centers the collected copies in one readable row.
		var reveal: PackRevealSticker = PackRevealSticker.new() # Creates the existing shader-based physical sheet.
		reveal.name = "reveal_%d" % index # Gives each copy a stable local debug identity.
		_reveal_root.add_child(reveal) # Attaches the sheet before its material setup.
		reveal.configure(index, sticker_key, _catalog.get_default_size(artwork_path), texture, target) # Applies original dimensions and the exact normal, rainbow, silver, or gold finish.
		if not animate_throw: # Avoids replaying the reward throw when restoring an existing reveal.
			reveal.settle_immediately() # Displays the reveal in its settled presentation.
		_reveal_nodes.append(reveal) # Retains the sheet for cleanup when the reveal ends.
		global_targets.append(_reveal_root.to_global(target)) # Supplies the matching absolute anchor to the HUD.
	_hud.show_choices(_revealed_paths, global_targets, _camera) # Presents edition-aware result labels and a single continue action.

func dismiss_reward() -> void: # Finishes viewing the current reward while leaving every collected copy in inventory.
	_revealed_paths.clear() # Removes only transient reveal state; economy ownership remains unchanged.
	_clear_reveal() # Removes physical sheets from the shop counter.
	_hud.show_choices(PackedStringArray(), [], _camera) # Returns the HUD to normal acquisition offers.

func has_reward_reveal() -> bool: # Reports whether collected stickers are currently being shown in the shop.
	return not _revealed_paths.is_empty() # Keeps reveal state independent from book placement persistence.

func get_ui() -> ShopHUD: # Exposes the composed HUD for scoped keyboard navigation.
	return _hud # Keeps presentation ownership inside the shop component.

func _clear_reveal() -> void: # Releases physical sheets after the transient reveal changes.
	for reveal: PackRevealSticker in _reveal_nodes: # Visits only the current small result set.
		if is_instance_valid(reveal): # Handles a sheet already removed during a transition safely.
			_reveal_root.remove_child(reveal) # Removes stale collision and rendering ownership immediately.
			reveal.queue_free() # Releases the old physical sheet after event dispatch.
	_reveal_nodes.clear() # Clears expired references before creating another reveal.
