extends CanvasLayer

const BATTLE_PANEL_SCENE := preload("res://scenes/ui/battle_panel.tscn")
const TRADE_PANEL_SCENE := preload("res://scenes/ui/trade_panel.tscn")

@onready var system_label: Label = %SystemLabel
@onready var credits_label: Label = %CreditsLabel
@onready var hull_bar: ProgressBar = %HullBar
@onready var shield_bar: ProgressBar = %ShieldBar
@onready var fuel_bar: ProgressBar = %FuelBar
@onready var cargo_bar: ProgressBar = %CargoBar
@onready var hull_label: Label = %HullLabel
@onready var shield_label: Label = %ShieldLabel
@onready var fuel_label: Label = %FuelLabel
@onready var cargo_label: Label = %CargoLabel
@onready var mid_row: HBoxContainer = $Layout/MidRow
@onready var logout_button: Button = %LogoutButton

var _battle_panel: PanelContainer = null
var _trade_panel: PanelContainer = null
var _was_docked: bool = false


func _ready() -> void:
	StateManager.state_updated.connect(_refresh)
	StateManager.ship_updated.connect(_refresh_ship)
	StateManager.combat_started.connect(_show_battle_panel)
	StateManager.combat_ended.connect(_hide_battle_panel)
	logout_button.pressed.connect(_on_logout)
	_refresh()


func _on_logout() -> void:
	NetworkManager.logout()


func _refresh() -> void:
	_refresh_location()
	_refresh_player()
	_refresh_ship()
	_refresh_dock_panels()


func _refresh_location() -> void:
	var sys_name: String = StateManager.current_system.get("name", "")
	var poi_name: String = StateManager.location.get("name", "")
	var docked := StateManager.is_docked()

	var parts: Array = []
	if sys_name:
		parts.append(sys_name)
	if poi_name:
		parts.append(poi_name)
	if docked:
		parts.append("[DOCKED]")

	system_label.text = " — ".join(parts) if parts else "Unknown Location"


func _refresh_player() -> void:
	var credits: int = StateManager.player.get("credits", 0)
	credits_label.text = "¢%s" % _format_number(credits)


func _refresh_ship() -> void:
	var s := StateManager.ship
	var hull: int = s.get("hull", 0)
	var max_hull: int = s.get("hull_max", 1)
	var shield: int = s.get("shield", 0)
	var max_shield: int = s.get("shield_max", 1)
	var fuel: int = s.get("fuel", 0)
	var max_fuel: int = s.get("fuel_max", 1)
	var cargo_used: int = s.get("cargo_used", 0)
	var cargo_cap: int = s.get("cargo_max", 1)

	hull_bar.value = StateManager.hull_pct() * 100.0
	shield_bar.value = StateManager.shield_pct() * 100.0
	fuel_bar.value = StateManager.fuel_pct() * 100.0
	cargo_bar.value = StateManager.cargo_pct() * 100.0

	hull_label.text = "%d/%d" % [hull, max_hull]
	shield_label.text = "%d/%d" % [shield, max_shield]
	fuel_label.text = "%d/%d" % [fuel, max_fuel]
	cargo_label.text = "%d/%d" % [cargo_used, cargo_cap]

	# Color hull bar by health
	if StateManager.hull_pct() < 0.25:
		hull_bar.modulate = Color.RED
	elif StateManager.hull_pct() < 0.5:
		hull_bar.modulate = Color.ORANGE
	else:
		hull_bar.modulate = Color.WHITE


func _refresh_dock_panels() -> void:
	var docked := StateManager.is_docked()
	if docked and not _was_docked:
		_show_trade_panel()
	elif not docked and _was_docked:
		_hide_trade_panel()
	_was_docked = docked


func _show_trade_panel() -> void:
	if _trade_panel:
		return
	_trade_panel = TRADE_PANEL_SCENE.instantiate()
	mid_row.add_child(_trade_panel)
	mid_row.move_child(_trade_panel, 0)


func _hide_trade_panel() -> void:
	if _trade_panel:
		_trade_panel.queue_free()
		_trade_panel = null


func _show_battle_panel() -> void:
	if _battle_panel:
		return
	_battle_panel = BATTLE_PANEL_SCENE.instantiate()
	# Insert before the event log panel (index 1 in MidRow)
	mid_row.add_child(_battle_panel)
	mid_row.move_child(_battle_panel, 0)


func _hide_battle_panel() -> void:
	if _battle_panel:
		_battle_panel.queue_free()
		_battle_panel = null


func _format_number(n: int) -> String:
	var s := str(n)
	var result := ""
	var count := 0
	for i in range(s.length() - 1, -1, -1):
		if count > 0 and count % 3 == 0:
			result = "," + result
		result = s[i] + result
		count += 1
	return result
