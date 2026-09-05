extends PanelContainer

@onready var travel_button: MenuButton = %TravelButton
@onready var attack_button: MenuButton = %AttackButton
@onready var scan_button: Button = %ScanButton
@onready var survey_button: Button = %SurveyButton
@onready var dock_button: Button = %DockButton
@onready var undock_button: Button = %UndockButton
@onready var mine_button: Button = %MineButton
@onready var repair_button: Button = %RepairButton
@onready var refuel_button: Button = %RefuelButton
@onready var pending_label: Label = %PendingLabel
@onready var status_label: Label = %ActionStatusLabel

var _all_buttons: Array[Control] = []


static func _system_jump_id(system_data: Dictionary) -> String:
	return system_data.get("system_id", system_data.get("id", ""))


func _ready() -> void:
	_all_buttons = [travel_button, attack_button, scan_button, survey_button,
					dock_button, undock_button, mine_button, repair_button, refuel_button]

	NetworkManager.request_started.connect(_lock)
	NetworkManager.request_completed.connect(_unlock)
	UIManager.error_shown.connect(func(msg): _set_status(msg, true))
	UIManager.info_shown.connect(func(msg): _set_status(msg, false))
	StateManager.state_updated.connect(_refresh_visibility)

	scan_button.pressed.connect(_on_scan)
	survey_button.pressed.connect(_on_survey)
	dock_button.pressed.connect(_on_dock)
	undock_button.pressed.connect(_on_undock)
	mine_button.pressed.connect(_on_mine)
	repair_button.pressed.connect(_on_repair)
	refuel_button.pressed.connect(_on_refuel)
	_bind_popup_positioning(travel_button, _setup_travel_menu)
	_bind_popup_positioning(attack_button, _setup_attack_menu)

	_refresh_visibility()
	_setup_travel_menu()
	_setup_attack_menu()

	StateManager.location_changed.connect(func(_a, _b):
		_setup_travel_menu()
		_setup_attack_menu()
	)
	StateManager.nearby_updated.connect(_setup_attack_menu)
	StateManager.combat_started.connect(_refresh_visibility)
	StateManager.combat_ended.connect(_refresh_visibility)


func _refresh_visibility() -> void:
	var docked := StateManager.is_docked()
	var in_combat := StateManager.in_combat

	# Check if current POI is dockable (has_base)
	var at_dockable := false
	var poi_id: String = StateManager.location.get("poi_id", "")
	for poi in StateManager.current_system.get("pois", []):
		if poi.get("id", "") == poi_id and poi.get("has_base", false):
			at_dockable = true
			break

	# Check if current POI is minable
	var poi_type: String = StateManager.location.get("poi_type", StateManager.location.get("type", ""))
	var at_minable := poi_type in ["asteroid_belt", "ice_field", "gas_cloud"]

	# Hide most actions during combat
	travel_button.visible = not docked and not in_combat
	attack_button.visible = not docked and not in_combat
	scan_button.visible = not docked and not in_combat
	survey_button.visible = not docked and not in_combat
	mine_button.visible = not docked and not in_combat and at_minable
	dock_button.visible = not docked and not in_combat and at_dockable
	undock_button.visible = docked and not in_combat
	repair_button.visible = docked and not in_combat
	refuel_button.visible = docked and not in_combat

	# Show pending indicator for server-side pending actions
	pending_label.visible = StateManager.has_pending


func _setup_travel_menu() -> void:
	var popup := travel_button.get_popup()
	popup.clear()
	for c in popup.id_pressed.get_connections():
		popup.id_pressed.disconnect(c["callable"])

	# Add POIs within the current system
	var pois: Array = StateManager.current_system.get("pois", [])
	var current_poi: String = StateManager.location.get("poi_id", "")

	for poi in pois:
		if poi.get("id", "") == current_poi:
			continue
		popup.add_item(poi.get("name", "Unknown"))
		popup.set_item_metadata(popup.item_count - 1, {"id": poi.get("id", ""), "type": "poi"})

	# Add connected systems (if available from get_system response)
	var connections: Array = StateManager.current_system.get("connections", [])
	if connections.size() > 0 and pois.size() > 0:
		popup.add_separator("Systems")
	for sys in connections:
		popup.add_item(">> " + sys.get("name", "Unknown System"))
		popup.set_item_metadata(popup.item_count - 1, {"id": _system_jump_id(sys), "type": "system"})

	popup.id_pressed.connect(func(id: int):
		var meta: Dictionary = popup.get_item_metadata(id)
		var target_name: String = popup.get_item_text(id)
		if meta.get("type", "") == "system":
			_set_status("Jumping to %s..." % target_name)
			var target_system_id: String = meta["id"]
			NetworkManager.execute_jump(target_system_id, func(succeeded: bool):
				if not succeeded:
					_set_status("Jump to %s failed." % target_name, true)
					return
				_set_status("Arrived in %s." % target_name)
			)
		else:
			var origin_id: String = StateManager.location.get("poi_id", "")
			_set_status("Traveling to %s..." % target_name)
			StateManager.begin_travel(meta["id"], target_name)
			NetworkManager.send_command("travel", {"id": meta["id"]}, func(content):
				if StateManager.location.get("poi_id", "") == origin_id:
					StateManager.abort_travel()
					_set_status("Travel failed.")
				else:
					StateManager.end_travel()
					_set_status("Arrived at %s." % target_name)
			)
	)


func _bind_popup_positioning(button: MenuButton, refresh_menu: Callable) -> void:
	var popup := button.get_popup()
	popup.about_to_popup.connect(func():
		refresh_menu.call()
		_position_popup_above_button(button)
		call_deferred("_position_popup_above_button", button)
	)


func _position_popup_above_button(button: MenuButton) -> void:
	var popup := button.get_popup()
	popup.reset_size()

	var button_rect := button.get_global_rect()
	var visible_rect := get_viewport().get_visible_rect()
	var menu_size := _popup_menu_size(popup)
	popup.position = _desired_popup_position(button_rect, menu_size, visible_rect)


func _popup_menu_size(popup: PopupMenu) -> Vector2i:
	var content_size := popup.get_contents_minimum_size().ceil()
	var popup_size := Vector2(popup.size)
	var width := maxi(int(content_size.x), int(ceil(popup_size.x)))
	var height := maxi(int(content_size.y), int(ceil(popup_size.y)))
	return Vector2i(width, height)


func _desired_popup_position(button_rect: Rect2, menu_size: Vector2i, visible_rect: Rect2) -> Vector2i:
	var popup_pos := Vector2i(button_rect.position)
	var min_x := int(visible_rect.position.x)
	var max_x := int(visible_rect.end.x) - menu_size.x
	popup_pos.x = clampi(popup_pos.x, min_x, max_x)

	var preferred_y := int(button_rect.position.y) - menu_size.y
	if preferred_y >= int(visible_rect.position.y):
		popup_pos.y = preferred_y
	else:
		var below_y := int(button_rect.end.y)
		var max_y := int(visible_rect.end.y) - menu_size.y
		popup_pos.y = clampi(below_y, int(visible_rect.position.y), max_y)

	return popup_pos


func _setup_attack_menu() -> void:
	var popup := attack_button.get_popup()
	popup.clear()
	for c in popup.id_pressed.get_connections():
		popup.id_pressed.disconnect(c["callable"])

	for p in StateManager.nearby_players:
		popup.add_item(p.get("username", "Unknown Player"))
		popup.set_item_metadata(popup.item_count - 1, {"id": p.get("player_id", ""), "type": "player"})

	for pirate in StateManager.nearby_pirates:
		popup.add_item("⚠ " + pirate.get("name", "Unknown Pirate"))
		popup.set_item_metadata(popup.item_count - 1, {"id": pirate.get("id", ""), "type": "pirate"})

	popup.id_pressed.connect(func(id: int):
		var meta: Dictionary = popup.get_item_metadata(id)
		var name_text: String = popup.get_item_text(id)
		_set_status("Attacking %s..." % name_text)
		NetworkManager.send_command("attack", {"id": meta["id"]}, func(content):
			_set_status("Attack complete.")
	))


func _on_scan() -> void:
	var poi_id: String = StateManager.location.get("poi_id", "")
	_set_status("Scanning...")
	NetworkManager.send_command("scan", {"id": poi_id}, func(content: Dictionary):
		var revealed: Array = content.get("revealed_info", [])
		if revealed.is_empty():
			_set_status("Scan complete — nothing new found.")
		else:
			_set_status("Scan revealed %d results." % revealed.size())
			for info in revealed:
				UIManager.show_info("Scan: %s" % str(info))
	)


func _on_survey() -> void:
	_set_status("Surveying system...")
	NetworkManager.send_command("survey_system", {}, func(_content: Dictionary):
		_set_status("Survey complete.")
	)


func _on_dock() -> void:
	var poi_id: String = StateManager.location.get("poi_id", "")
	if poi_id.is_empty():
		_set_status("No dockable location.", true)
		return
	_set_status("Docking...")
	StateManager.is_docking = true
	NetworkManager.send_command("dock", {"id": poi_id}, func(_c):
		StateManager.is_docking = false
		_set_status("Docked.")
	)


func _on_undock() -> void:
	_set_status("Undocking...")
	StateManager.is_undocking = true
	NetworkManager.send_command("undock", {}, func(_c):
		StateManager.is_undocking = false
		_set_status("Undocked.")
	)


func _on_mine() -> void:
	var poi_id: String = StateManager.location.get("poi_id", "")
	_set_status("Mining...")
	StateManager.is_mining = true
	NetworkManager.send_command("mine", {"id": poi_id}, func(_c):
		StateManager.is_mining = false
		_set_status("Mining complete.")
	)


func _on_repair() -> void:
	_set_status("Repairing...")
	NetworkManager.send_command("repair", {}, func(_c): _set_status("Repair complete."))


func _on_refuel() -> void:
	_set_status("Refueling...")
	NetworkManager.send_command("refuel", {"quantity": 10}, func(_c): _set_status("Refueled."))


func _unhandled_key_input(event: InputEvent) -> void:
	if not event.is_pressed() or event.is_echo():
		return
	if NetworkManager.is_request_pending:
		return

	match (event as InputEventKey).keycode:
		KEY_D:
			if StateManager.is_docked():
				_on_undock()
			elif dock_button.visible:
				_on_dock()
		KEY_M:
			if mine_button.visible and not mine_button.disabled:
				_on_mine()
		KEY_R:
			if repair_button.visible and not repair_button.disabled:
				_on_repair()
		KEY_U:
			if refuel_button.visible and not refuel_button.disabled:
				_on_refuel()
		KEY_V:
			if scan_button.visible and not scan_button.disabled:
				_on_scan()
		KEY_Y:
			if survey_button.visible and not survey_button.disabled:
				_on_survey()


func _lock() -> void:
	for btn in _all_buttons:
		btn.disabled = true
	pending_label.show()


func _unlock() -> void:
	for btn in _all_buttons:
		btn.disabled = false
	pending_label.hide()
	_refresh_visibility()


func _set_status(text: String, is_error: bool = false) -> void:
	status_label.text = text
	status_label.modulate = ThemeColors.TEXT_ERROR if is_error else ThemeColors.CHROME_SILVER
