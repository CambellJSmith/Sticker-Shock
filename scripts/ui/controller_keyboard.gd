class_name ControllerKeyboard
extends Control

const CHARACTER_ROWS: Array[String] = ["1234567890", "QWERTYUIOP", "ASDFGHJKL", "ZXCVBNM", "`~!@#$%^&*", "()-_=+[]{}", ";:',.<>/?", "\\|&"] # Covers letters, digits, spaces, and the practical ASCII punctuation accepted by arbitrary sticker names, Unique codes, and collection searches.

@onready var _rows: VBoxContainer = %key_rows as VBoxContainer # Hosts generated character rows while the surrounding modal layout remains editor-authored.
@onready var _preview: Label = %preview as Label # Shows the exact text that will be committed to the target LineEdit.
@onready var _shift: GameButton = %shift as GameButton # Toggles alphabetic character case for exact case-sensitive Unique names.
@onready var _space: GameButton = %space as GameButton # Inserts a normal space into the working text.
@onready var _backspace: GameButton = %backspace as GameButton # Removes the final character without requiring keyboard input.
@onready var _clear: GameButton = %clear as GameButton # Clears the complete working text in one controller action.
@onready var _cancel: GameButton = %cancel as GameButton # Closes the modal without changing the original LineEdit.
@onready var _done: GameButton = %done as GameButton # Commits the working text to the original LineEdit and returns focus.

var _target: LineEdit # Stores the exact text field being edited during the current modal session.
var _working_text: String = "" # Stores controller-edited text separately until the player explicitly accepts it.
var _uppercase: bool = true # Starts with uppercase letters because authored sticker Names commonly begin with a capital.
var _character_buttons: Array[GameButton] = [] # Retains generated keys for case refreshes and deterministic initial focus.
var _base_characters: Dictionary[int, String] = {} # Maps generated button instance IDs back to their canonical uppercase/symbol character.

func _ready() -> void: # Builds reusable character keys and binds every editor-authored special action once.
	process_mode = Node.PROCESS_MODE_ALWAYS # Keeps the keyboard responsive when opened from any future paused-compatible UI context.
	_build_character_rows() # Creates the repetitive character keys inside the editor-authored row host.
	_shift.bind_action(_toggle_case) # Gives controller users exact upper/lowercase control without signals.
	_space.bind_action(_append_character.bind(" ")) # Inserts one space through the same bounded append path as normal keys.
	_backspace.bind_action(_erase_character) # Removes one trailing character directly.
	_clear.bind_action(_clear_text) # Clears the temporary edit buffer while preserving the target until Done.
	_cancel.bind_action(cancel) # Discards edits and returns focus to the original field.
	_done.bind_action(accept) # Commits edits and returns focus to the original field.
	visible = false # Keeps the modal absent until a controller activates a LineEdit.
	_refresh_presentation() # Initializes special-button labels and preview state after key creation.

func open_for(target: LineEdit) -> void: # Opens controller text entry for one existing native LineEdit without changing keyboard/mouse text support.
	if target == null or not target.is_visible_in_tree(): # Rejects stale or hidden text fields before stealing modal focus.
		return # Leaves the current interface unchanged for an invalid target.
	_target = target # Retains the exact native field that owns the eventual committed text.
	_working_text = target.text # Starts from the field's current value so controller editing is nondestructive.
	_uppercase = true # Returns each new editing session to a predictable initial character case.
	visible = true # Places the controller keyboard above every underlying game surface.
	_refresh_presentation() # Shows the copied text and current case before accepting input.
	if not _character_buttons.is_empty(): # Ensures a generated key exists before assigning modal focus.
		_character_buttons[0].grab_focus.call_deferred() # Selects the first character after layout has completed.
	else: # Provides a safe fallback if key construction ever changes unexpectedly.
		_done.grab_focus.call_deferred() # Keeps the modal closable and usable even without character keys.

func is_open() -> bool: # Reports whether controller text entry currently owns the UI focus scope.
	return visible # Uses modal visibility as the single authoritative open state.

func cancel() -> void: # Closes controller text entry without mutating the original native field.
	var restore_target: LineEdit = _target # Retains the opener long enough to restore focus after clearing session state.
	_target = null # Releases the text field so stale actions cannot modify it after close.
	_working_text = "" # Clears temporary text immediately when edits are discarded.
	visible = false # Releases modal presentation and pointer ownership.
	if is_instance_valid(restore_target) and restore_target.is_visible_in_tree(): # Restores focus only when the original field still exists on the current route.
		restore_target.grab_focus.call_deferred() # Returns controller navigation to the exact field that opened the keyboard.

func accept() -> void: # Commits controller-entered text to the native field and closes the modal.
	var restore_target: LineEdit = _target # Retains the opener through the commit and focus restoration sequence.
	if is_instance_valid(restore_target): # Protects route changes or teardown that removed the original field unexpectedly.
		restore_target.text = _working_text # Applies the complete accepted text in one controlled mutation.
	_target = null # Releases the completed editing session before returning to the underlying interface.
	_working_text = "" # Clears the modal buffer so later fields never inherit stale content.
	visible = false # Releases modal ownership after the accepted text is committed.
	if is_instance_valid(restore_target) and restore_target.is_visible_in_tree(): # Returns focus only when the field remains actionable on the current page.
		restore_target.grab_focus.call_deferred() # Lets the player continue to Redeem, collection cards, or other nearby actions using the left stick.

func _build_character_rows() -> void: # Creates repetitive controller character buttons inside the editor-authored keyboard composition.
	for row_text: String in CHARACTER_ROWS: # Builds each authored character group as a centered horizontal row.
		var row: HBoxContainer = HBoxContainer.new() # Creates one native responsive row for this compact key group.
		row.alignment = BoxContainer.ALIGNMENT_CENTER # Keeps short lower rows centered under the full-width rows above.
		row.add_theme_constant_override("separation", 6) # Gives every generated key the same readable gap.
		_rows.add_child(row) # Parents the row into the modal's editor-authored vertical key host.
		for character_index: int in range(row_text.length()): # Visits every ASCII character exactly once without relying on String iteration coercion.
			var base_character: String = row_text.substr(character_index, 1) # Extracts the canonical uppercase letter, digit, or symbol represented by this key.
			var key: GameButton = GameButton.new() # Uses the project's direct-callback native button so controller activation needs no signals.
			key.custom_minimum_size = Vector2(56.0, 46.0) # Keeps keys large enough for clear focus presentation at the supported minimum window size.
			key.theme_type_variation = &"QuietButton" # Reuses the established Blender-like quiet-control styling.
			key.focus_mode = Control.FOCUS_ALL # Explicitly includes generated keys in UIFocus controller traversal.
			key.bind_action(_append_character.bind(base_character)) # Appends this key's current case-transformed character when activated.
			row.add_child(key) # Adds the interactive key to its responsive row before storing metadata.
			_character_buttons.append(key) # Retains the key for future case-label refresh and deterministic focus.
			_base_characters[key.get_instance_id()] = base_character # Stores the canonical character independently from the visible case label.

func _append_character(base_character: String) -> void: # Adds one controller-selected character while respecting any native LineEdit length limit.
	if _target == null or base_character.is_empty(): # Rejects stale sessions and malformed generated actions.
		return # Leaves the temporary buffer unchanged when no active edit exists.
	var character: String = base_character # Starts symbols and digits unchanged regardless of alphabetic case mode.
	if base_character.to_upper() != base_character.to_lower(): # Detects alphabetic keys without maintaining a separate letter table.
		character = base_character.to_upper() if _uppercase else base_character.to_lower() # Applies the currently selected exact letter case.
	if _target.max_length > 0 and _working_text.length() >= _target.max_length: # Honors native per-field maximum lengths when future text inputs define one.
		return # Prevents controller text from exceeding the same limit as keyboard entry.
	_working_text += character # Appends exactly one selected character to the modal edit buffer.
	_refresh_presentation() # Shows the new value immediately without mutating the target before Done.

func _erase_character() -> void: # Removes one trailing controller-entered character from the temporary edit buffer.
	if _working_text.is_empty(): # Rejects backspace at the start of an already empty value.
		return # Leaves the buffer stable and avoids negative substring lengths.
	_working_text = _working_text.left(_working_text.length() - 1) # Removes exactly the final codepoint used by the supported keyboard character set.
	_refresh_presentation() # Reflects the shortened value immediately.

func _clear_text() -> void: # Clears all temporary controller-entered text without closing the keyboard.
	_working_text = "" # Resets only the modal buffer so Cancel can still preserve the original target value.
	_refresh_presentation() # Shows the intentionally blank working value.

func _toggle_case() -> void: # Switches every alphabetic key between upper and lowercase labels and output.
	_uppercase = not _uppercase # Flips the persistent case mode until the player changes it again.
	_refresh_presentation() # Updates both the shift state label and every generated alphabetic key.

func _refresh_presentation() -> void: # Synchronizes preview text, case state, and generated key labels with modal state.
	_preview.text = _working_text if not _working_text.is_empty() else " " # Preserves preview panel height while clearly representing an empty value.
	_shift.text = "letters: ABC" if _uppercase else "letters: abc" # Makes the current exact-case mode explicit before entering case-sensitive codes.
	for key: GameButton in _character_buttons: # Refreshes only the small fixed character-key collection when text or case changes.
		var base_character: String = str(_base_characters.get(key.get_instance_id(), key.text)) # Recovers the canonical character for this generated key.
		if base_character.to_upper() != base_character.to_lower(): # Applies case only to alphabetic characters.
			key.text = base_character.to_upper() if _uppercase else base_character.to_lower() # Mirrors exactly what activation will append.
		else: # Keeps digits and punctuation stable across case changes.
			key.text = base_character # Restores the canonical nonalphabetic key label unchanged.
