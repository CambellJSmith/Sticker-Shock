class_name RemovableStickerInspection
extends StickerInspection

const CONTROLLER_ROTATION_SPEED: float = 2.35 # Converts full right-stick deflection into responsive inspection pitch/yaw radians per second.
const CONTROLLER_ROLL_SPEED: float = 2.10 # Converts shoulder-button hold into deliberate camera-facing roll radians per second.
const CONTROLLER_DETAIL_SCROLL_SPEED: float = 520.0 # Converts trigger pressure into readable details-panel scrolling pixels per second.

@onready var _return_to_collection_button: Button = $bottom_bar/return_to_collection as Button # References the explicit action that removes the inspected physical placement from the book.
@onready var _edition_badge: Label = $top_bar/content/edition_badge as Label # Shows the exact normal or premium finish beside the authored sticker name.
@onready var _details_scroll: ScrollContainer = $details_panel/margin/scroll as ScrollContainer # Owns creator-authored metadata overflow so long descriptions remain controller-accessible.
@onready var _market_value: Label = $details_panel/margin/scroll/details/market_value as Label # Shows the current collector-exchange quote for this exact edition.
@onready var _id_label: Label = $details_panel/margin/scroll/details/id_label as Label # Shows the creator-authored numerical sticker ID.
@onready var _rarity_label: Label = $details_panel/margin/scroll/details/rarity_label as Label # Shows the creator-authored rarity independently from edition finish.
@onready var _edition_label: Label = $details_panel/margin/scroll/details/edition_label as Label # Shows whether this copy is normal, rainbow, silver, or gold.
@onready var _pack_label: Label = $details_panel/margin/scroll/details/pack_label as Label # Shows the creator-authored pack assignment.
@onready var _artist_label: Label = $details_panel/margin/scroll/details/artist_label as Label # Shows the creator-authored artist assignment.
@onready var _description_label: Label = $details_panel/margin/scroll/details/description as Label # Shows the creator-authored flavour description with wrapping.
@onready var _control_hint: Label = $bottom_bar/hint as Label # Explains the active mouse/keyboard, conventional controller, and Steam gyro inspection mappings without another overlay.

var _return_to_collection_action: Callable # Stores the exact placement-removal callback supplied by the book controller.
var _market_value_provider: Callable # Stores a lightweight live-value lookup for the exact inspected edition.
var _market_refresh_elapsed: float = 0.0 # Throttles inspection quote refreshes independently of rendering.
var _last_controller_hint: bool = false # Avoids rewriting the inspection help label every frame while the same input family remains active.
var _last_gyro_hint_available: bool = false # Rewrites the help label only when a Steam Input gyro appears, disconnects, or changes modal availability.
var _steam_gyro: SteamInspectionGyro = SteamInspectionGyro.new() # Owns inspection-scoped Steam Input motion discovery, neutral reference, filtering, and coordinate conversion.

func configure_actions() -> void: # Binds the existing inspection controls plus the collection-return action without signals.
	super.configure_actions() # Preserves close, zoom, and reset behavior from the established inspection surface.
	(_return_to_collection_button as GameButton).bind_action(_return_to_collection) # Routes the new action through the same native button abstraction as the rest of the UI.

func open_inspection(sticker_texture: Texture2D, display_name: String, sticker_size: Vector2) -> void: # Opens the established physical inspector and automatically enables Steam Input gyro motion when available.
	super.open_inspection(sticker_texture, display_name, sticker_size) # Preserves mesh setup, canonical orientation, camera fit, zoom reset, and deterministic close-button focus.
	_market_refresh_elapsed = 0.0 # Starts live-value and control-hint polling from a clean interval for this modal session.
	_details_scroll.scroll_vertical = 0 # Starts every sticker's creator-authored details at the top for predictable controller reading.
	_steam_gyro.begin_session() # Discovers a Steam Controller or Deck-class motion device and treats its current physical pose as neutral without snapping the sticker.
	_last_controller_hint = not _is_controller_mode() # Forces the first hint refresh regardless of the previous inspection's input family.
	_last_gyro_hint_available = not _steam_gyro.is_available() # Forces the first hint refresh regardless of whether Steam Input gyro discovery succeeded immediately.
	_refresh_control_hint() # Shows the complete mapping including automatic gyro support when a motion device is available.

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
	if event.is_action_pressed(&"Button_RightStick"): # Gives the right-stick click a canonical-view reset and matching Steam gyro recenter without moving UI focus.
		_reset_transform() # Restores orientation and zoom while also making the controller's next gyro sample the new neutral reference.
		return true # Consumes the reset action inside inspection.
	return false # Leaves A/B/Start, left-stick UI focus, shoulders/triggers-as-held-state, and unrelated input to their normal owners.

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

func close_inspection() -> void: # Clears removal, live-market, and Steam gyro context whenever the modal closes.
	_return_to_collection_action = Callable() # Prevents a later inspection from reusing a stale physical placement callback.
	_market_value_provider = Callable() # Releases the exact-edition value lookup while no sticker is being inspected.
	_market_refresh_elapsed = 0.0 # Resets quote polling state for the next inspection session.
	_steam_gyro.end_session() # Stops motion polling and discards the old controller pose so every later inspection establishes a fresh neutral orientation.
	if is_instance_valid(_return_to_collection_button): # Protects teardown before the editor-authored button has completed ready state.
		_return_to_collection_button.visible = false # Hides the book-only action until another physical placement supplies context.
	super.close_inspection() # Preserves the established rendering shutdown and modal visibility behavior.

func _process(delta: float) -> void: # Drives automatic Steam gyro rotation, conventional controller controls, detail scrolling, and live exchange-value updates while inspection is open.
	if not visible: # Avoids gyro polling, analog input, hint updates, scrolling, and quote work while inspection is closed.
		return # Leaves hidden inspection effectively idle.
	var gyro_delta: Quaternion = _steam_gyro.sample_rotation_delta() # Reads one filtered frame-to-frame Steam Input orientation change without applying the controller's absolute physical pose.
	if gyro_delta.get_angle() > 0.0: # Applies only deliberate motion samples that survived gyro jitter and discontinuity filtering.
		_orientation = (gyro_delta * _orientation).normalized() # Adds physical controller motion to the same unrestricted quaternion used by mouse and right-stick inspection.
		_apply_orientation() # Updates the temporary sticker immediately while leaving persistent book placement untouched.
	_refresh_control_hint() # Switches the compact help string when input family or Steam gyro availability changes.
	if _is_controller_mode(): # Applies conventional controller controls alongside gyro so the right stick remains a complete fallback and can fine-adjust the gyro-driven view.
		var look: Vector2 = Input.get_vector(&"StickRight_West", &"StickRight_East", &"StickRight_North", &"StickRight_South") # Reads camera-relative two-axis rotation independently from left-stick UI focus.
		if look.length_squared() > 0.0001: # Avoids quaternion work while the right stick rests inside its configured deadzone.
			_apply_controller_rotation(look, delta) # Converts screen-space stick direction into stable world-space pitch and yaw on the inspection pivot.
		var roll_input: float = Input.get_action_strength(&"Button_RightShoulder") - Input.get_action_strength(&"Button_LeftShoulder") # Treats shoulders as symmetric held roll controls.
		if absf(roll_input) > 0.001: # Avoids roll quaternion work while neither shoulder is held.
			_apply_roll(roll_input * CONTROLLER_ROLL_SPEED * delta) # Reuses the established camera-facing roll axis and normalized orientation composition.
		var scroll_input: float = Input.get_action_strength(&"Trigger_Right") - Input.get_action_strength(&"Trigger_Left") # Treats triggers as symmetric down/up scrolling for long creator-authored metadata.
		if absf(scroll_input) > 0.001: # Avoids touching ScrollContainer state while both triggers rest.
			_details_scroll.scroll_vertical += int(round(scroll_input * CONTROLLER_DETAIL_SCROLL_SPEED * delta)) # Lets the native ScrollContainer clamp continuous trigger scrolling to its actual content range.
	if not _market_value_provider.is_valid(): # Skips quote polling for inspection contexts that do not have an authoritative market value provider.
		return # Leaves gyro, controller transforms, and details scrolling fully active even when no market quote exists.
	_market_refresh_elapsed += delta # Accumulates elapsed visible time between lightweight quote checks.
	if _market_refresh_elapsed < 1.0: # Limits market advancement/value formatting to one check per second.
		return # Keeps frame-by-frame inspection rendering and input free of economy polling.
	_market_refresh_elapsed = 0.0 # Starts the next one-second quote-refresh interval.
	_refresh_market_value() # Reads the same live market model used by the collector exchange.

func _reset_transform() -> void: # Restores the canonical sticker presentation and recenters Steam gyro motion around the controller's current physical pose.
	super._reset_transform() # Preserves the established orientation, zoom, gesture, camera, and toolbar reset behavior.
	_steam_gyro.recenter() # Makes the next valid Steam Input orientation sample neutral so resetting never causes the gyro to rotate the sticker back immediately.

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

func _is_controller_mode() -> bool: # Reads the persistent application's shared most-recent-input mode for device-specific conventional-controller behavior.
	var game_ui: MarketGameUI = get_parent() as MarketGameUI # Narrows the modal owner to the controller-aware concrete UI used by the actual main scene.
	return game_ui != null and game_ui.is_controller_input_active() # Uses one shared device-mode source so focus and non-gyro analog controls change together.

func _refresh_control_hint() -> void: # Presents complete inspection controls while reflecting Steam gyro hot-plug availability without adding another UI surface.
	var controller_mode: bool = _is_controller_mode() # Reads the current meaningful conventional input family exactly once for this refresh.
	var gyro_available: bool = _steam_gyro.is_available() # Reads whether a live Steam Input motion device currently owns automatic inspection rotation.
	if controller_mode == _last_controller_hint and gyro_available == _last_gyro_hint_available: # Avoids rewriting the same help label every frame while neither input family nor gyro availability changed.
		return # Leaves the current concise help string stable.
	_last_controller_hint = controller_mode # Records the newly displayed conventional input mapping before mutating the label.
	_last_gyro_hint_available = gyro_available # Records the newly displayed Steam gyro availability state for hot-plug comparison.
	if controller_mode and gyro_available: # Shows gyro plus every conventional controller fallback when both are available.
		_control_hint.text = "gyro + right stick rotate · LB/RB roll · LT/RT details · X/Y zoom · R3 reset/recenter · B close" # Makes automatic motion control and manual fine adjustment equally discoverable.
	elif controller_mode: # Shows the established complete gamepad mapping when no Steam Input gyro is available.
		_control_hint.text = "right stick rotate · LB/RB roll · LT/RT details · X/Y zoom · R3 reset · B close" # Preserves full controller functionality as a transparent fallback.
	elif gyro_available: # Keeps automatic Steam gyro rotation discoverable even if the most recent conventional input was mouse or keyboard.
		_control_hint.text = "Steam gyro rotate · drag to rotate · right drag to roll · wheel to zoom · r reset/recenter" # Allows physical controller motion and desktop gestures to coexist without switching modes.
	else: # Preserves the established desktop gesture mapping when no gamepad motion device is available.
		_control_hint.text = "drag to rotate · right drag to roll · wheel to zoom · r to reset" # Retains concise original pointer/keyboard guidance.
