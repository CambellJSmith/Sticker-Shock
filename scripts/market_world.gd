class_name MarketWorld
extends Node3D

@onready var _camera: Camera3D = $world/camera as Camera3D # Projects the physical collector exchange into the shared application viewport.
@onready var _environment_node: WorldEnvironment = $world/environment as WorldEnvironment # Owns the exchange-specific lighting and background while this world is active.
@onready var _interface: CanvasLayer = $interface as CanvasLayer # Owns the screen-space market controls layered over the physical exchange set.
@onready var _hud: MarketHUD = $interface/market_hud as MarketHUD # Owns live quotes, trend presentation, selling controls, and market timing.

var _environment_resource: Environment # Preserves the authored market environment while camera ownership moves between worlds.
var _active: bool = false # Tracks whether the exchange currently owns presentation and processing.

func configure(controller: SpecialEditionGameController, economy: GuaranteedSpecialStickerEconomy, catalog: StickerCatalog, market: StickerMarket, available_count: Callable) -> void: # Binds the physical exchange to authoritative progression and market models.
	_environment_resource = _environment_node.environment # Retains the editor-authored exchange environment for later reactivation.
	_hud.configure(controller, economy, catalog, market, available_count) # Gives the native market HUD only the dependencies required for quoting and selling.

func set_active(active: bool) -> void: # Transfers camera, environment, interface, and processing ownership for this independent physical destination.
	_active = active # Stores the new world-ownership state for diagnostics and future interaction guards.
	visible = active # Shows or hides the complete exchange set without destroying its persistent nodes.
	_interface.visible = active # Shows market controls only while this world owns the current destination.
	_camera.current = active # Transfers shared viewport camera ownership to or from the exchange.
	_environment_node.environment = _environment_resource if active else null # Prevents inactive worlds from competing for the shared World3D environment.
	process_mode = Node.PROCESS_MODE_INHERIT if active else Node.PROCESS_MODE_DISABLED # Stops market-HUD polling completely while the physical exchange is hidden.
	if active: # Refreshes live market information only when entering the exchange.
		_hud.refresh() # Publishes any overdue market tick and synchronizes sellable inventory before the player can act.

func get_ui() -> MarketHUD: # Exposes the exchange HUD to the shared controller-navigation focus system.
	return _hud # Keeps all market presentation ownership inside this world component.
