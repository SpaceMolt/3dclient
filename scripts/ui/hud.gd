extends CanvasLayer

const BATTLE_PANEL_SCENE := preload("res://scenes/ui/battle_panel.tscn")
const MARKET_PANEL_SCENE := preload("res://scenes/ui/market_panel.tscn")
const STORAGE_PANEL_SCENE := preload("res://scenes/ui/storage_panel.tscn")
const CHAT_PANEL_SCENE := preload("res://scenes/ui/chat_panel.tscn")
const MISSIONS_PANEL_SCENE := preload("res://scenes/ui/missions_panel.tscn")
const CRAFTING_PANEL_SCENE := preload("res://scenes/ui/crafting_panel.tscn")
const ACTION_LOG_PANEL_SCENE := preload("res://scenes/ui/action_log_panel.tscn")
const SHIP_PANEL_SCENE := preload("res://scenes/ui/ship_panel.tscn")
const GALAXY_MAP_SCENE := preload("res://scenes/ui/galaxy_map.tscn")
const SETTINGS_PANEL_SCENE := preload("res://scenes/ui/settings_panel.tscn")
const TRADES_PANEL_SCENE := preload("res://scenes/ui/trades_panel.tscn")
const FACTION_PANEL_SCENE := preload("res://scenes/ui/faction_panel.tscn")
const SKILLS_PANEL_SCENE := preload("res://scenes/ui/skills_panel.tscn")
const FACILITIES_PANEL_SCENE := preload("res://scenes/ui/facilities_panel.tscn")
const INFO_PANEL_SCENE := preload("res://scenes/ui/info_panel.tscn")
const WRECK_PANEL_SCENE := preload("res://scenes/ui/wreck_panel.tscn")

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
@onready var settings_button: Button = %SettingsButton
@onready var target_panel: PanelContainer = %TargetPanel
@onready var target_label: Label = %TargetLabel
@onready var target_travel_button: Button = %TargetTravelButton
@onready var target_dock_button: Button = %TargetDockButton

var _battle_panel: PanelContainer = null
var _market_panel: PanelContainer = null
var _storage_panel: PanelContainer = null
var _trades_panel: PanelContainer = null
var _chat_panel: PanelContainer = null
var _missions_panel: PanelContainer = null
var _crafting_panel: PanelContainer = null
var _action_log_panel: PanelContainer = null
var _ship_panel: PanelContainer = null
var _faction_panel: PanelContainer = null
var _skills_panel: PanelContainer = null
var _facilities_panel: PanelContainer = null
var _info_panel: PanelContainer = null
var _wreck_panel: PanelContainer = null
var _galaxy_map: CanvasLayer = null
var _settings_panel: CanvasLayer = null
var _was_docked: bool = false
var _selected_poi_id: String = ""
var _selected_poi_name: String = ""
var _selected_ship_id: String = ""
var _selected_ship_name: String = ""
var _system_renderer: Node3D = null
var _hull_fill: StyleBoxFlat = null


func _ready() -> void:
	StateManager.state_updated.connect(_refresh)
	StateManager.ship_updated.connect(_refresh_ship)
	StateManager.combat_started.connect(_show_battle_panel)
	StateManager.combat_ended.connect(_hide_battle_panel)
	logout_button.pressed.connect(_on_logout)
	settings_button.pressed.connect(_toggle_settings)
	target_travel_button.pressed.connect(_on_target_travel)
	target_dock_button.pressed.connect(_on_target_dock)
	target_panel.hide()
	_hull_fill = ThemeManager.bar_fill(ThemeColors.BIO_GREEN)
	hull_bar.add_theme_stylebox_override("fill", _hull_fill)
	shield_bar.add_theme_stylebox_override("fill", ThemeManager.bar_fill(ThemeColors.PLASMA_CYAN))
	fuel_bar.add_theme_stylebox_override("fill", ThemeManager.bar_fill(ThemeColors.SHELL_ORANGE))
	cargo_bar.add_theme_stylebox_override("fill", ThemeManager.bar_fill(ThemeColors.CHROME_SILVER))
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


func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed):
		return
	if event.is_echo():
		return

	match (event as InputEventKey).keycode:
		KEY_ESCAPE:
			if _settings_panel and _settings_panel.visible:
				_settings_panel.hide()
				get_viewport().set_input_as_handled()
			elif _galaxy_map and _galaxy_map.visible:
				_galaxy_map.hide()
				get_viewport().set_input_as_handled()
			elif target_panel.visible:
				if _system_renderer:
					_system_renderer.deselect_poi()
					_system_renderer.deselect_ship()
				_on_poi_deselected()
				_on_ship_deselected()
				get_viewport().set_input_as_handled()
			else:
				_toggle_settings()
				get_viewport().set_input_as_handled()
		KEY_C:
			_toggle_panel("chat")
			get_viewport().set_input_as_handled()
		KEY_J:
			_toggle_panel("missions")
			get_viewport().set_input_as_handled()
		KEY_K:
			_toggle_panel("crafting")
			get_viewport().set_input_as_handled()
		KEY_L:
			_toggle_panel("action_log")
			get_viewport().set_input_as_handled()
		KEY_S:
			_toggle_panel("ship")
			get_viewport().set_input_as_handled()
		KEY_G:
			_toggle_galaxy_map()
			get_viewport().set_input_as_handled()
		KEY_T:
			if StateManager.is_docked():
				_toggle_panel("market")
				get_viewport().set_input_as_handled()
		KEY_I:
			if StateManager.is_docked():
				_toggle_panel("storage")
				get_viewport().set_input_as_handled()
		KEY_P:
			if StateManager.is_docked():
				_toggle_panel("trades")
				get_viewport().set_input_as_handled()
		KEY_F:
			_toggle_panel("faction")
			get_viewport().set_input_as_handled()
		KEY_X:
			_toggle_panel("skills")
			get_viewport().set_input_as_handled()
		KEY_N:
			_toggle_panel("info")
			get_viewport().set_input_as_handled()
		KEY_B:
			if StateManager.is_docked():
				_toggle_panel("facilities")
				get_viewport().set_input_as_handled()
		KEY_W:
			if not StateManager.is_docked():
				_toggle_panel("wreck")
				get_viewport().set_input_as_handled()


func _toggle_panel(panel_name: String) -> void:
	match panel_name:
		"chat":
			if _chat_panel:
				_chat_panel.queue_free()
				_chat_panel = null
			else:
				_chat_panel = CHAT_PANEL_SCENE.instantiate()
				mid_row.add_child(_chat_panel)
		"missions":
			if _missions_panel:
				_missions_panel.queue_free()
				_missions_panel = null
			else:
				_missions_panel = MISSIONS_PANEL_SCENE.instantiate()
				mid_row.add_child(_missions_panel)
		"crafting":
			if _crafting_panel:
				_crafting_panel.queue_free()
				_crafting_panel = null
			else:
				_crafting_panel = CRAFTING_PANEL_SCENE.instantiate()
				mid_row.add_child(_crafting_panel)
		"action_log":
			if _action_log_panel:
				_action_log_panel.queue_free()
				_action_log_panel = null
			else:
				_action_log_panel = ACTION_LOG_PANEL_SCENE.instantiate()
				mid_row.add_child(_action_log_panel)
		"ship":
			if _ship_panel:
				_ship_panel.queue_free()
				_ship_panel = null
			else:
				_ship_panel = SHIP_PANEL_SCENE.instantiate()
				mid_row.add_child(_ship_panel)
		"market":
			if _market_panel:
				_market_panel.queue_free()
				_market_panel = null
			else:
				_market_panel = MARKET_PANEL_SCENE.instantiate()
				mid_row.add_child(_market_panel)
				mid_row.move_child(_market_panel, 0)
		"storage":
			if _storage_panel:
				_storage_panel.queue_free()
				_storage_panel = null
			else:
				_storage_panel = STORAGE_PANEL_SCENE.instantiate()
				mid_row.add_child(_storage_panel)
				mid_row.move_child(_storage_panel, 0)
		"trades":
			if _trades_panel:
				_trades_panel.queue_free()
				_trades_panel = null
			else:
				_trades_panel = TRADES_PANEL_SCENE.instantiate()
				mid_row.add_child(_trades_panel)
				mid_row.move_child(_trades_panel, 0)
		"faction":
			if _faction_panel:
				_faction_panel.queue_free()
				_faction_panel = null
			else:
				_faction_panel = FACTION_PANEL_SCENE.instantiate()
				mid_row.add_child(_faction_panel)
		"skills":
			if _skills_panel:
				_skills_panel.queue_free()
				_skills_panel = null
			else:
				_skills_panel = SKILLS_PANEL_SCENE.instantiate()
				mid_row.add_child(_skills_panel)
		"facilities":
			if _facilities_panel:
				_facilities_panel.queue_free()
				_facilities_panel = null
			else:
				_facilities_panel = FACILITIES_PANEL_SCENE.instantiate()
				mid_row.add_child(_facilities_panel)
				mid_row.move_child(_facilities_panel, 0)
		"info":
			if _info_panel:
				_info_panel.queue_free()
				_info_panel = null
			else:
				_info_panel = INFO_PANEL_SCENE.instantiate()
				mid_row.add_child(_info_panel)
		"wreck":
			if _wreck_panel:
				_wreck_panel.queue_free()
				_wreck_panel = null
			else:
				_wreck_panel = WRECK_PANEL_SCENE.instantiate()
				mid_row.add_child(_wreck_panel)


func _toggle_galaxy_map() -> void:
	if _galaxy_map:
		if _galaxy_map.visible:
			_galaxy_map.hide()
		else:
			_galaxy_map.show_map()
	else:
		_galaxy_map = GALAXY_MAP_SCENE.instantiate()
		add_child(_galaxy_map)
		_galaxy_map.show_map()


func _toggle_settings() -> void:
	if _settings_panel:
		if _settings_panel.visible:
			_settings_panel.hide()
		else:
			_settings_panel.show()
	else:
		_settings_panel = SETTINGS_PANEL_SCENE.instantiate()
		add_child(_settings_panel)


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
	if StateManager.is_traveling:
		var dest_name := StateManager.travel_dest_poi_name
		if not dest_name.is_empty():
			parts.append("→ %s" % dest_name)
		else:
			parts.append("[IN TRANSIT]")
	elif poi_name:
		parts.append(poi_name)
	if docked:
		parts.append("[DOCKED]")

	system_label.text = " — ".join(parts) if parts else "Unknown Location"


func _refresh_player() -> void:
	var pname: String = StateManager.player.get("username", StateManager.player.get("name", ""))
	var empire: String = StateManager.player.get("empire", "")
	player_name_label.text = pname + (" [%s]" % empire if empire else "")
	player_name_label.add_theme_color_override("font_color", ThemeColors.empire_color(empire))

	var credits: int = StateManager.player.get("credits", 0)
	credits_label.text = "¢%s" % _format_number(credits)


func _refresh_ship() -> void:
	var s := StateManager.ship
	var hull: int = s.get("hull", 0)
	var max_hull: int = s.get("max_hull", 1)
	var shield: int = s.get("shield", 0)
	var max_shield: int = s.get("max_shield", 1)
	var fuel: int = s.get("fuel", 0)
	var max_fuel: int = s.get("max_fuel", 1)
	var cargo_used: int = s.get("cargo_used", 0)
	var cargo_cap: int = s.get("cargo_capacity", 1)

	hull_bar.value = StateManager.hull_pct() * 100.0
	shield_bar.value = StateManager.shield_pct() * 100.0
	fuel_bar.value = StateManager.fuel_pct() * 100.0
	cargo_bar.value = StateManager.cargo_pct() * 100.0

	hull_label.text = "%d/%d" % [hull, max_hull]
	shield_label.text = "%d/%d" % [shield, max_shield]
	fuel_label.text = "%d/%d" % [fuel, max_fuel]
	cargo_label.text = "%d/%d" % [cargo_used, cargo_cap]

	_hull_fill.bg_color = hull_color(StateManager.hull_pct())


## Traffic-light hull colour: green while sound, yellow under half, red under a quarter.
static func hull_color(pct: float) -> Color:
	if pct < 0.25:
		return ThemeColors.CLAW_RED
	if pct < 0.5:
		return ThemeColors.WARNING_YELLOW
	return ThemeColors.BIO_GREEN


func _refresh_dock_panels() -> void:
	var docked := StateManager.is_docked()
	if not docked and _was_docked:
		_close_dock_panels()
	_was_docked = docked


func _close_dock_panels() -> void:
	if _market_panel:
		_market_panel.queue_free()
		_market_panel = null
	if _storage_panel:
		_storage_panel.queue_free()
		_storage_panel = null
	if _trades_panel:
		_trades_panel.queue_free()
		_trades_panel = null
	if _facilities_panel:
		_facilities_panel.queue_free()
		_facilities_panel = null


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
	var dest_id := _selected_poi_id
	var dest_name := _selected_poi_name
	var origin_id: String = StateManager.location.get("poi_id", "")
	StateManager.begin_travel(dest_id, dest_name)
	NetworkManager.send_command("travel", {"id": dest_id}, func(_c):
		if StateManager.location.get("poi_id", "") == origin_id:
			StateManager.abort_travel()
		else:
			StateManager.end_travel()
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
