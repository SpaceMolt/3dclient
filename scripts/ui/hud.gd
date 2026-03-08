extends CanvasLayer

const BATTLE_PANEL_SCENE := preload("res://scenes/ui/battle_panel.tscn")
const TRADE_PANEL_SCENE := preload("res://scenes/ui/trade_panel.tscn")

@onready var player_name_label: Label = %PlayerNameLabel
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
@onready var target_panel: PanelContainer = %TargetPanel
@onready var target_label: Label = %TargetLabel
@onready var target_travel_button: Button = %TargetTravelButton
@onready var target_dock_button: Button = %TargetDockButton

var _battle_panel: PanelContainer = null
var _trade_panel: PanelContainer = null
var _was_docked: bool = false
var _selected_poi_id: String = ""
var _selected_poi_name: String = ""
var _selected_ship_id: String = ""
var _selected_ship_name: String = ""
var _system_renderer: Node3D = null


func _ready() -> void:
	StateManager.state_updated.connect(_refresh)
	StateManager.ship_updated.connect(_refresh_ship)
	StateManager.combat_started.connect(_show_battle_panel)
	StateManager.combat_ended.connect(_hide_battle_panel)
	logout_button.pressed.connect(_on_logout)
	target_travel_button.pressed.connect(_on_target_travel)
	target_dock_button.pressed.connect(_on_target_dock)
	target_panel.hide()
	_refresh()

	# Find the system renderer to listen for POI selection
	_connect_system_renderer.call_deferred()


func _connect_system_renderer() -> void:
	var game_view := get_tree().get_root().find_child("Ships", true, false)
	if game_view and game_view.has_signal("poi_selected"):
		_system_renderer = game_view
		game_view.poi_selected.connect(_on_poi_selected)
		game_view.poi_deselected.connect(_on_poi_deselected)
		game_view.ship_selected.connect(_on_ship_selected)
		game_view.ship_deselected.connect(_on_ship_deselected)


func _on_logout() -> void:
	NetworkManager.logout()


func _refresh() -> void:
	_refresh_location()
	_refresh_player()
	_refresh_ship()
	_refresh_dock_panels()


func _refresh_location() -> void:
	var sys_name: String = StateManager.current_system.get("name", "")
	var poi_name: String = StateManager.get_current_poi_name()
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
	var pname: String = StateManager.player.get("name", "")
	var empire: String = StateManager.player.get("empire", "")
	player_name_label.text = pname + (" [%s]" % empire if empire else "")

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


func _on_poi_selected(poi_id: String, poi_name: String, poi_type: String) -> void:
	_selected_poi_id = poi_id
	_selected_poi_name = poi_name
	_selected_ship_id = ""
	target_label.text = "%s (%s)" % [poi_name, poi_type]
	target_travel_button.visible = true
	target_dock_button.visible = poi_type == "station"
	target_panel.show()


func _on_poi_deselected() -> void:
	_selected_poi_id = ""
	_selected_poi_name = ""
	if _selected_ship_id.is_empty():
		target_panel.hide()


func _on_ship_selected(ship_id: String, ship_name: String, _is_pirate: bool) -> void:
	_selected_ship_id = ship_id
	_selected_ship_name = ship_name
	_selected_poi_id = ""
	target_label.text = ship_name
	target_travel_button.text = "Attack"
	target_travel_button.visible = true
	target_dock_button.visible = false
	target_panel.show()


func _on_ship_deselected() -> void:
	_selected_ship_id = ""
	_selected_ship_name = ""
	target_travel_button.text = "Go"
	if _selected_poi_id.is_empty():
		target_panel.hide()


func _on_target_travel() -> void:
	if not _selected_ship_id.is_empty():
		# Attack the selected ship
		var attack_id: String = _selected_ship_id
		# Strip "pirate_" prefix for the API call
		if attack_id.begins_with("pirate_"):
			attack_id = attack_id.substr(7)
		NetworkManager.send_command("attack", {"id": attack_id}, func(_c):
			pass
		)
		if _system_renderer:
			_system_renderer.deselect_ship()
		_on_ship_deselected()
		return

	if _selected_poi_id.is_empty():
		return
	NetworkManager.send_command("travel", {"id": _selected_poi_id}, func(_c):
		pass
	)
	if _system_renderer:
		_system_renderer.deselect_poi()
	_on_poi_deselected()


func _on_target_dock() -> void:
	if _selected_poi_id.is_empty():
		return
	NetworkManager.send_command("dock", {"id": _selected_poi_id}, func(_c):
		pass
	)
	if _system_renderer:
		_system_renderer.deselect_poi()
	_on_poi_deselected()


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
