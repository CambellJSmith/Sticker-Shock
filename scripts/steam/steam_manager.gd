extends Node # Owns the Steamworks client lifecycle and exposes safe game-wide Steam helpers without signal wiring.

const APP_ID_SETTING: StringName = &"steam/initialization/app_id" # Identifies the GodotSteam project setting used for the real Steam application identity.
const REQUIRE_STEAM_SETTING: StringName = &"steam/integration/require_steam" # Identifies whether a failed Steam session should prevent the game from continuing.
const RESTART_THROUGH_STEAM_SETTING: StringName = &"steam/integration/restart_through_steam" # Identifies whether exported builds should relaunch through the Steam client when required.

var _initialized: bool = false # Stores whether the Steam API completed initialization for the current process.
var _shutdown: bool = false # Prevents the Steam API from being shut down more than once during application teardown.
var _app_id: int = 0 # Stores the configured or runtime-resolved Steam application identifier.
var _steam_id: int = 0 # Stores the local player's Steam account identifier after successful initialization.
var _persona_name: String = "" # Stores the local player's current Steam display name for lightweight UI access.
var _subscribed: bool = false # Stores whether Steam reports that the current account owns a license for this application.
var _steam_hardware_type: int = 0 # Stores Steamworks SDK 1.65's diagnostic hardware classification for this session.
var _steam_hardware_default_config: int = 0 # Stores Steamworks SDK 1.65's recommended hardware configuration tier for functional defaults.
var _running_under_proton: bool = false # Stores whether Steam reports that the current process is running through Proton.

func _ready() -> void: # Initializes Steam before the main scene starts using any platform services.
	process_mode = Node.PROCESS_MODE_ALWAYS # Keeps Steam callbacks moving even while Sticker-Shock pauses its gameplay SceneTree.
	set_process(false) # Avoids callback work until the Steam API has actually initialized.
	_app_id = int(ProjectSettings.get_setting(APP_ID_SETTING, 0)) # Reads the real application identity without embedding account-specific values in code.
	if _should_restart_through_steam() and Steam.restartAppIfNecessary(_app_id): # Lets release builds re-enter through Steam so overlay and ownership context are established before initialization.
		get_tree().quit() # Stops this process because Steam is launching the authoritative replacement instance.
		return # Prevents any Steam API initialization work inside the superseded process.
	var initialize_response: Dictionary = Steam.steamInitEx(_app_id, false) # Uses explicit manual callbacks so lifecycle ownership remains inside this autoload.
	var initialize_status: int = int(initialize_response.get("status", -1)) # Reads the detailed Steamworks initialization result without depending on a version-specific enum name.
	if initialize_status != 0: # Treats the Steamworks success status as the only initialized state.
		_handle_initialization_failure(str(initialize_response.get("verbal", "unknown Steam initialization error"))) # Reports the exact Steamworks reason and applies the configured fallback policy.
		return # Leaves callback processing disabled when Steam is unavailable.
	_initialized = true # Marks every later Steam helper as safe to use.
	_shutdown = false # Clears teardown state for the newly established client session.
	_app_id = int(Steam.getAppID()) # Resolves the authoritative runtime application identity when Steam supplied it during launch.
	_steam_id = int(Steam.getSteamID()) # Caches the local account identity once instead of repeatedly crossing the extension boundary.
	_persona_name = str(Steam.getPersonaName()) # Caches the current local Steam persona name for ordinary game presentation.
	_subscribed = bool(Steam.isSubscribed()) # Caches Steam's ownership result for optional release enforcement and diagnostics.
	_steam_hardware_type = int(Steam.isRunningOnSteamHardware()) # Uses the current SDK 1.65 hardware classification instead of the removed dedicated Steam Deck query.
	_steam_hardware_default_config = int(Steam.getSteamHardwareDefaultConfig()) # Caches Steam's current recommended hardware tier for future presentation defaults without per-frame API calls.
	_running_under_proton = bool(Steam.isRunningUnderProton()) # Caches the current Proton environment hint for diagnostics and future platform-specific compatibility decisions.
	if bool(ProjectSettings.get_setting(REQUIRE_STEAM_SETTING, false)) and not _subscribed: # Enforces ownership only when the project explicitly requests Steam-only execution.
		push_error("Steam initialized, but the current account does not own Sticker-Shock") # Reports the ownership failure clearly before teardown.
		shutdown() # Releases the initialized Steam API before leaving the process.
		get_tree().quit() # Stops execution because the configured Steam-only policy rejected the current account.
		return # Prevents callback processing from being re-enabled after shutdown.
	Steam.run_callbacks() # Pumps one initial callback pass so queued Steam events do not wait for the first process frame.
	set_process(true) # Enables continuous Steam callback pumping for the rest of the session.
	print("Steam initialized: app=%d user=%d persona=%s" % [_app_id, _steam_id, _persona_name]) # Emits one concise startup diagnostic for local and Steam build verification.

func _process(_delta: float) -> void: # Pumps Steamworks callbacks independently from gameplay update cadence.
	if not _initialized or _shutdown: # Rejects callback work before initialization or after teardown begins.
		return # Leaves the frame without crossing into an unavailable Steam API.
	Steam.run_callbacks() # Processes Steamworks callback traffic every frame because embedded callbacks are deliberately disabled.

func _exit_tree() -> void: # Releases Steamworks when the application tears down through any normal Godot quit path.
	shutdown() # Uses the idempotent central teardown path so window close, menu quit, and scene-tree exit behave identically.

func is_available() -> bool: # Reports whether Steam features are safe to call in the current process.
	return _initialized and not _shutdown # Requires a successful live API session rather than only a running Steam client.

func get_app_id() -> int: # Returns the authoritative Steam application identity for this session.
	return _app_id # Exposes the cached identifier without another extension call.

func get_steam_id() -> int: # Returns the local player's Steam account identity when available.
	return _steam_id # Exposes the cached identifier without leaking mutable session state.

func get_persona_name() -> String: # Returns the local player's cached Steam display name.
	return _persona_name # Exposes the startup persona value for optional UI use.

func is_subscribed() -> bool: # Reports Steam's cached ownership result for the current application.
	return _subscribed # Exposes ownership without allowing callers to mutate enforcement state.

func get_steam_hardware_type() -> int: # Returns Steamworks' diagnostic hardware classification for the current session.
	return _steam_hardware_type # Exposes the cached SDK 1.65 hardware enum value without another native call.

func get_steam_hardware_default_config() -> int: # Returns Steamworks' recommended hardware-default tier for functional graphics or performance defaults.
	return _steam_hardware_default_config # Exposes the cached SDK 1.65 configuration enum value without another native call.

func is_running_under_proton() -> bool: # Reports whether Steam identified the current process as running through Proton.
	return _running_under_proton # Exposes the cached compatibility-layer state for diagnostics or future platform behavior.

func open_overlay(dialog: String) -> bool: # Opens one supported Steam overlay destination while leaving gameplay state ownership to the caller.
	if not is_available() or dialog.is_empty(): # Rejects overlay requests when Steam is unavailable or no destination was supplied.
		return false # Reports that no overlay request was sent.
	Steam.activateGameOverlay(dialog) # Delegates the requested standard Steam overlay destination to Steamworks.
	return true # Reports that the overlay activation request was submitted.

func open_achievements_overlay() -> bool: # Opens the standard Steam achievements overlay for Sticker-Shock.
	return open_overlay("Achievements") # Uses Steam's documented achievements dialog identifier through the common guarded path.

func open_friends_overlay() -> bool: # Opens the standard Steam friends overlay for the local player.
	return open_overlay("Friends") # Uses Steam's documented friends dialog identifier through the common guarded path.

func set_rich_presence(key: String, value: String) -> bool: # Writes one Steam Rich Presence field for dashboard-configured status presentation.
	if not is_available() or key.is_empty(): # Rejects Rich Presence writes without a live Steam API or a valid field name.
		return false # Reports that no presence field was changed.
	return bool(Steam.setRichPresence(key, value)) # Returns Steamworks' result so gameplay code can detect unpublished or invalid presence configuration.

func clear_rich_presence() -> void: # Removes every Steam Rich Presence field owned by the current game session.
	if not is_available(): # Avoids calling Steamworks after initialization failed or shutdown already completed.
		return # Leaves teardown and non-Steam sessions harmlessly unchanged.
	Steam.clearRichPresence() # Clears presence so stale activity text cannot survive a normal game exit.

func shutdown() -> void: # Performs one explicit Steamworks teardown and disables every later helper call.
	if not _initialized or _shutdown: # Makes shutdown safe when called from multiple normal quit paths.
		return # Avoids duplicate SteamAPI shutdown calls.
	_shutdown = true # Blocks callbacks and feature calls before releasing native Steam resources.
	set_process(false) # Stops callback pumping immediately while teardown owns the API.
	Steam.clearRichPresence() # Removes any active Rich Presence before disconnecting from the Steam client.
	Steam.steamShutdown() # Releases the Steamworks API according to GodotSteam's explicit lifecycle contract.
	_initialized = false # Marks all later feature requests unavailable for the remainder of the process.

func _should_restart_through_steam() -> bool: # Resolves whether this process should invoke Steam's restart-under-client check.
	if _app_id <= 0: # Requires the real application identity because restartAppIfNecessary cannot target an unknown game.
		return false # Leaves launch ownership unchanged until the App ID is configured.
	if OS.has_feature("editor"): # Keeps ordinary Godot editor runs from constantly relaunching themselves through the Steam client.
		return false # Preserves fast local development while exported builds still get the proper Steam launch path.
	return bool(ProjectSettings.get_setting(RESTART_THROUGH_STEAM_SETTING, true)) # Applies the explicit project policy for exported builds.

func _handle_initialization_failure(verbal_error: String) -> void: # Reports Steam startup failure and applies the project's required-or-optional policy.
	push_warning("Steam initialization unavailable: %s" % verbal_error) # Keeps non-Steam development usable while preserving a precise diagnostic.
	if not bool(ProjectSettings.get_setting(REQUIRE_STEAM_SETTING, false)): # Allows the normal standalone fallback when Steam is intentionally optional.
		return # Leaves Sticker-Shock running without Steam features.
	push_error("Sticker-Shock is configured to require Steam, so startup cannot continue") # Explains why the process is terminating instead of using the fallback.
	get_tree().quit() # Stops the game when the release policy requires a valid Steam session.
