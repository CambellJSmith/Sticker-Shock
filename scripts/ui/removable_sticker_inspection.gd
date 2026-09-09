class_name RemovableStickerInspection
extends StickerInspection

@onready var _return_to_collection_button: Button = $bottom_bar/return_to_collection as Button # References the explicit action that removes the inspected physical placement from the book.
@onready var _edition_badge: Label = $top_bar/content/edition_badge as Label # Shows the exact normal or premium finish beside the authored sticker name.
@onready var _market_value: Label = $details_panel/margin/scroll/details/market_value as Label # Shows the current collector-exchange quote for this exact edition.
@onready var _id_label: Label = $details_panel/margin/scroll/details/id_label as Label # Shows the creator-authored numerical sticker ID.
@onready var _rarity_label: Label = $details_panel/margin/scroll/details/rarity_label as Label # Shows the creator-authored rarity independently from edition finish.
@onready var _edition_label: Label = $details_panel/margin/scroll/details/edition_label as Label # Shows whether this copy is normal, rainbow, silver, or gold.
@onready var _pack_label: Label = $details_panel/margin/scroll/details/pack_label as Label # Shows the creator-authored pack assignment.
@onready var _artist_label: Label = $details_panel/margin/scroll/details/artist_label as Label # Shows the creator-authored artist assignment.
@onready var _description_label: Label = $details_panel/margin/scroll/details/description as Label # Shows the creator-authored flavour description with wrapping.

var _return_to_collection_action: Callable # Stores the exact placement-removal callback supplied by the book controller.
var _market_value_provider: Callable # Stores a lightweight live-value lookup for the exact inspected edition.
var _market_refresh_elapsed: float = 0.0 # Throttles inspection quote refreshes independently of rendering.

func configure_actions() -> void: # Binds the existing inspection controls plus the collection-return action without signals.
	super.configure_actions() # Preserves close, zoom, and reset behavior from the established inspection surface.
	(_return_to_collection_button as GameButton).bind_action(_return_to_collection) # Routes the new action through the same native button abstraction as the rest of the UI.

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

func _process(delta: float) -> void: # Keeps the displayed exchange value current while the player leaves inspection open.
	if not visible or not _market_value_provider.is_valid(): # Avoids all quote work while inspection is closed or no market context exists.
		return # Leaves hidden inspection effectively idle.
	_market_refresh_elapsed += delta # Accumulates elapsed visible time between lightweight quote checks.
	if _market_refresh_elapsed < 1.0: # Limits market advancement/value formatting to one check per second.
		return # Keeps frame-by-frame inspection rendering free of economy polling.
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
