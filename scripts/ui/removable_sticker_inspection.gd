class_name RemovableStickerInspection
extends StickerInspection

const CONTROLLER_ROTATION_SPEED: float = 2.35 # Converts full right-stick deflection into responsive inspection pitch/yaw radians per second.
const CONTROLLER_ROLL_SPEED: float = 2.10 # Converts shoulder-button hold into deliberate camera-facing roll radians per second.

@onready var _return_to_collection_button: Button = $bottom_bar/return_to_collection as Button # References the explicit action that removes the inspected physical placement from the book.
@onready var _edition_badge: Label = $top_bar/content/edition_badge as Label # Shows the exact normal or premium finish beside the authored sticker name.
@onready var _market_value: Label = $details_panel/margin/scroll/details/market_value as Label # Shows the current collector-exchange quote for this exact edition.
@onready var _id_label: Label = $details_panel/margin/scroll/details/id_label as Label # Shows the creator-authored numerical sticker ID.
@onready var _rarity_label: Label = $details_panel/margin/scroll/details/rarity_label as Label # Shows the creator-authored rarity independently from edition finish.
@onready var _edition_label: Label = $details_panel/margin/scroll/details/edition_label as Label # Shows whether this copy is normal, rainbow, silver, or gold.
@onready var _pack_label: Label = $details_panel/margin/scroll/details/pack_label as Label # Shows the creator-authored pack assignment.
@onready var _artist_label: Label = $details_panel/margin/scroll/details/artist_label as Label # Shows the creator-authored artist assignment.
@onready var _description_label: Label = $details_panel/margin/scroll/details/description as Label # Shows the creator-authored flavour description with wrapping.
@onready var _control_hint: Label = $bottom_bar/hint as Label # Explains the active mouse/keyboard or controller inspection mapping without adding another overlay.

var _return_to_collection_action: Callable # Stores the exact placement-removal callback supplied by the book controller.
var _market_value_provider: Callable # Stores a lightweight live-value lookup for the exact inspected edition.
var _market_refresh_elapsed: float = 0.0 # Throttles inspection quote refreshes independently of rendering.
var _last_controller_hint: bool = false # Avoids rewriting the inspection help label every frame while the same input family remains active.

func configure_actions() -> void: # Binds the existing inspection controls plus the collection-return action without signals.
	super.configure_actions() # Preserves close, zoom, and reset behavior from the established inspection surface.
	(_return_to_collection_button as GameButton).bind_action(_return_to_collection) # Routes the new action through the same native button abstraction as the rest of the UI.

func open_inspection(sticker_texture: Texture2D, display_name: String, sticker_size: Vector2) -> void: # Opens the established physical inspector and immediately presents the correct active-device controls.
	super.open_inspection(sticker_texture, display_name, sticker_size) # Preserves mesh setup, canonical orientation, camera fit, zoom reset, and deterministic close-button focus.
	_market_refresh_elapsed = 0.0 # Starts live-value and control-hint polling from a clean interval for this modal session.
	_last_controller_hint = not _is_controller_mode() # Forces the first hint refresh regardless of the previous inspection's input family.
	_refresh_control_hint() # Shows either complete gamepad inspection controls or the established pointer/keyboard gestures.

func handle_input(event: InputEvent) -> bool: # Extends established mouse/keyboard inspection gestures with direct gamepad zoom and reset actions.
	if super.handle_input(event): # Gives existing R/Q/E, mouse wheel, arcball, and right-drag gestures first ownership.
		return true # Reports the inherited interaction as fully handled without duplicating its transform.
	if not visible: # Rejects controller shortcuts while the inspection modal is closed.
		return false # Leaves the active gameplay destination in control.
	if event.is_action_pressed(&"Button_X"): # Maps the physical-action face button to a convenient inspection zoom-out shortcut while the book is blocked beneath the modal.
		_change_zoom(false) # Uses the same clamped multiplicative zoom path as the toolbar and mouse wheel.
		return true # Prevents the same X press from reaching any underlying physical sticker interaction.
	if event.is_action_pressed(&"Button_Y"): # Maps the upper face button to zoom in for symmetric controller inspection.
		_change_zoom(true) # Uses the same established clamped camera path as every other zoom source.
		return true # Consumes the gamepad zoom-in action inside the modal.
	if event.is_action_pressed(&"Button_RightStick"): # Gives the right-stick click a quick canonical-view reset without moving UI focus.
		_reset_transform() # Restores orientation and zoom through the existing inspection reset implementation.
		return true # Consumes the reset action inside inspection.
	return false # Leaves A/B/Start, left-stick UI focus, shoulders-as-held-state, and unrelated input to their normal owners.

func set_sticker_details(definition: StickerDefinition, edition_name: String, market_value_provider: Callable) -> void: # Populates every creator-authored property plus exact edition and live exchange value.
	_market_value_provider = market_value_provider # Retains the exact edition-aware quote lookup while this inspection remains open.
	_market_refresh_elapsed = 0.0 # Forces the next periodic refresh to start from a clean interval.
	var normalized_edition: String = edition_name.strip_edges().to_lower() # Normalizes the controlled edition display name for consistent labels.
	if normalized_edition.is_empty(): # Protects against incomplete callers while preserving a useful ordinary-copy fallback.
		normalized_edition = "normal" # Treats missing edition metadata as the standard printed finish.
	_edition_badge.text = "%s EDITION" % normalized_edition.to_upper() # Makes premium status immediately visible beside the title without hiding normal-copy identity.
	_edition_label.text = "EDITION  %s%s" % [normalized_edition.to_upper(), " · SPECIAL" if normalized_edition != "normal" else ""] # Explicitly identifies whether this is a special edition and which finish it uses.
	if definition == null: # Handles unexpected catalogue misses without leaving stale metadata from a previous inspection.
		_title.text = "unknown sticker" # Replaces stale title content with a safe fallback.
		_id_label.text = "ID  —" # Clears unavailable authored identity.
		_rarity_label.text = "RARITY  —" # Clears unavailable rarity metadata.
		_pack_label.text = "PACK  —" # Clears unavailable pack metadata.
		_artist_label.text = "ARTIST  —" # Clears unavailable artist metadata.
		_description_label.text = "No description available." # Provides a deliberate fallback instead of stale flavour text.
	else: # Presents the complete creator-authored sticker object.
		_title.text = definition.name # Uses the authored custom name rather than deriving display text from the PNG filename.
		_id_label.text = "ID  %06d" % definition.id # Formats the numerical ID compactly while preserving the exact stored integer.
		_rarity_label.text = "RARITY  %s" % definition.rarity.to_upper() # Shows authored rarity independently from the per-copy edition roll.
		_pack_label.text = "PACK  %s" % definition.pack # Shows the exact controlled pack selected in the creator tool.
		_artist_label.text = "ARTIST  %s" % definition.artist # Shows the exact controlled artist selected in the creator tool.
		_description_label.text = definition.description.strip_edges() if not definition.description.strip_edges().is_empty() else "No description set." # Shows creator flavour text while handling intentionally blank batch-import descriptions.
	_refresh_market_value() # Publishes the current exact-edition quote immediately when inspection opens.

func set_return_to_collection_action(action: Callable) -> void: # Configures whether the currently inspected sticker can be removed from the book.
	_return_to_collection_action = action # Retains the exact placement callback for this modal session.
	_return_to_collection_button.text = "return to collection" # Restores the normal action label after any earlier failed removal attempt.
	_return_to_collection_button.visible = action.is_valid() # Shows removal only when inspection came from a removable physical book placement.
	_return_to_collection_button.disabled = not action.is_valid() # Prevents stale focus activation when no placement context exists.

func close_inspection() -> void: # Clears removal and live-market context whenever the modal closes.
	_return_to_collection_action = Callable() # Prevents a later inspection from reusing a stale physical placement callback.
	_market_value_provider = Callable() # Releases the exact-edition value lookup while no sticker is being inspected.
	_market_refresh_elapsed = 0.0 # Resets quote polling state for the next inspection session.
	if is_instance_valid(_return_to_collection_button): # Protects teardown before the editor-authored button has completed ready state.
		_return_to_collection_button.visible = false # Hides the book-only action until another physical placement supplies context.
	super.close_inspection() # Preserves the established rendering shutdown and modal visibility behavior.

func _process(delta: float) -> void: # Drives continuous controller rotation/roll and keeps the displayed exchange value current while inspection is open.
	if not visible: # Avoids analog input, hint updates, and quote work while inspection is closed.
		return # Leaves hidden inspection effectively idle.
	_refresh_control_hint() # Switches the compact help string only when meaningful input changes the active device family.
	if _is_controller_mode(): # Applies continuous analog inspection transforms only while the gamepad is the most recently used device.
		var look: Vector2 = Input.get_vector(&"StickRight_West", &"StickRight_East", &"StickRight_North", &"StickRight_South") # Reads camera-relative two-axis rotation independently from left-stick UI focus.
		if look.length_squared() > 0.0001: # Avoids quaternion work while the right stick rests inside its configured deadzone.
			_apply_controller_rotation(look, delta) # Converts screen-space stick direction into stable world-space pitch and yaw on the inspection pivot.
		var roll_input: float = Input.get_action_strength(&"Button_RightShoulder") - Input.get_action_strength(&"Button_LeftShoulder") # Treats shoulders as symmetric held roll controls.
		if absf(roll_input) > 0.001: # Avoids roll quaternion work while neither shoulder is held.
			_apply_roll(roll_input * CONTROLLER_ROLL_SPEED * delta) # Reuses the established camera-facing roll axis and normalized orientation composition.
	if not _market_value_provider.is_valid(): # Skips quote polling for inspection contexts that do not have an authoritative market value provider.
		return # Leaves controller transforms fully active even when no market quote exists.
	_market_refresh_elapsed += delta # Accumulates elapsed visible time between lightweight quote checks.
	if _market_refresh_elapsed < 1.0: # Limits market advancement/value formatting to one check per second.
		return # Keeps frame-by-frame inspection rendering and analog controls free of economy polling.
	_market_refresh_elapsed = 0.0 # Starts the next one-second quote-refresh interval.
	_refresh_market_value() # Reads the same live market model used by the collector exchange.

func _refresh_market_value() -> void: # Updates the current exact-edition sell value from the authoritative market model.
	if not _market_value_provider.is_valid(): # Handles catalogue-only inspection contexts defensively.
		_market_value.text = "—" # Shows that no live market quote is available instead of inventing a price.
		return # Leaves the rest of the authored metadata intact.
	var value: Variant = _market_value_provider.call() # Requests the current quote through the controller-owned market boundary.
	var pounds: int = maxi(int(value), 0) # Normalizes callback output into the integer pound economy used by sales and packs.
	_market_value.text = "£%d" % pounds # Displays the same denomination used everywhere else in the game economy.

func _return_to_collection() -> void: # Removes the exact inspected placement and returns its owned copy to collection availability.
	if not _return_to_collection_action.is_valid(): # Rejects stale or non-book inspection sessions.
		return # Leaves the inspection unchanged when no authoritative removal callback exists.
	var action: Callable = _return_to_collection_action # Copies the callback so its result can be validated before modal state is cleared.
	var result: Variant = action.call() # Lets the authoritative controller commit the exact placement removal and report success synchronously.
	if not bool(result): # Detects a stale placement or persistence rejection instead of pretending the removal completed.
		_return_to_collection_button.text = "could not return · try again" # Keeps the modal open and gives immediate visible failure feedback.
		return # Preserves the current inspection context so the player can retry or close deliberately.
	close_and_restore_focus() # Releases inspection only after the authoritative book state confirms the sticker was removed.

func _apply_controller_rotation(look: Vector2, delta: float) -> void: # Applies right-stick pitch/yaw in camera screen axes without introducing Euler-angle locking.
	var camera_right: Vector3 = _camera.global_transform.basis.x.normalized() # Resolves the inspection camera's world-space screen-right axis.
	var camera_up: Vector3 = _camera.global_transform.basis.y.normalized() # Resolves the inspection camera's world-space screen-up axis.
	var yaw_rotation: Quaternion = Quaternion(camera_up, -look.x * CONTROLLER_ROTATION_SPEED * delta) # Turns horizontal stick motion around the current screen-up axis.
	var pitch_rotation: Quaternion = Quaternion(camera_right, -look.y * CONTROLLER_ROTATION_SPEED * delta) # Turns vertical stick motion around the current screen-right axis.
	_orientation = (yaw_rotation * pitch_rotation * _orientation).normalized() # Composes both camera-relative rotations onto the existing unrestricted quaternion orientation.
	_apply_orientation() # Writes the new inspection-only transform without touching persistent book placement.

func _is_controller_mode() -> bool: # Reads the persistent application's shared most-recent-input mode for device-specific inspection behavior.
	var game_ui: MarketGameUI = get_parent() as MarketGameUI # Narrows the modal owner to the controller-aware concrete UI used by the actual main scene.
	return game_ui != null and game_ui.is_controller_input_active() # Uses one shared device-mode source so hints and analog transforms change together.

func _refresh_control_hint() -> void: # Presents a complete mapping for the active inspection input family without adding another UI surface.
	var controller_mode: bool = _is_controller_mode() # Reads the current meaningful input family exactly once for this refresh.
	if controller_mode == _last_controller_hint: # Avoids rewriting the same label every frame while input ownership is unchanged.
		return # Leaves the current concise help string stable.
	_last_controller_hint = controller_mode # Records the newly displayed mapping before mutating the label.
	if controller_mode: # Shows every non-menu gamepad transform available in the inspection modal.
		_control_hint.text = "right stick rotate · LB/RB roll · X/Y zoom · R3 reset · B close" # Makes unrestricted inspection fully discoverable without mouse or keyboard.
	else: # Preserves the established desktop gesture mapping when mouse/keyboard is active.
		_control_hint.text = "drag to rotate · right drag to roll · wheel to zoom · r to reset" # Retains concise original pointer/keyboard guidance.
