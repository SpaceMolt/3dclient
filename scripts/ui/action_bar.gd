extends PanelContainer

@onready var travel_button: MenuButton = %TravelButton
@onready var attack_button: MenuButton = %AttackButton
@onready var dock_button: Button = %DockButton
@onready var undock_button: Button = %UndockButton
@onready var mine_button: Button = %MineButton
@onready var repair_button: Button = %RepairButton
@onready var refuel_button: Button = %RefuelButton
@onready var pending_label: Label = %PendingLabel
@onready var status_label: Label = %ActionStatusLabel

var _all_buttons: Array[Control] = []


func _ready() -> void:
	_all_buttons = [travel_button, attack_button, dock_button, undock_button,
					mine_button, repair_button, refuel_button]

	NetworkManager.request_started.connect(_lock)
	NetworkManager.request_completed.connect(_unlock)
	UIManager.error_shown.connect(func(msg): _set_status(msg, true))
	UIManager.info_shown.connect(func(msg): _set_status(msg, false))
	StateManager.state_updated.connect(_refresh_visibility)

	dock_button.pressed.connect(_on_dock)
	undock_button.pressed.connect(_on_undock)
	mine_button.pressed.connect(_on_mine)
	repair_button.pressed.connect(_on_repair)
	refuel_button.pressed.connect(_on_refuel)

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
	# Hide most actions during combat
	travel_button.visible = not docked and not in_combat
	attack_button.visible = not docked and not in_combat
	mine_button.visible = not docked and not in_combat
	dock_button.visible = not docked and not in_combat
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
		popup.set_item_metadata(popup.item_count - 1, {"id": sys.get("id", ""), "type": "system"})

	popup.id_pressed.connect(func(id: int):
		var meta: Dictionary = popup.get_item_metadata(id)
		var target_name: String = popup.get_item_text(id)
		_set_status("Traveling to %s..." % target_name)
		NetworkManager.send_command("travel", {"id": meta["id"]}, func(content):
			_set_status("Arrived at %s." % target_name)
	))


func _setup_attack_menu() -> void:
	var popup := attack_button.get_popup()
	popup.clear()
	for c in popup.id_pressed.get_connections():
		popup.id_pressed.disconnect(c["callable"])

	for p in StateManager.nearby_players:
		popup.add_item(p.get("player_name", "Unknown Player"))
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


func _on_dock() -> void:
	var poi_id: String = StateManager.location.get("poi_id", "")
	if poi_id.is_empty():
		_set_status("No dockable location.", true)
		return
	_set_status("Docking...")
	NetworkManager.send_command("dock", {"id": poi_id}, func(_c): _set_status("Docked."))


func _on_undock() -> void:
	_set_status("Undocking...")
	NetworkManager.send_command("undock", {}, func(_c): _set_status("Undocked."))


func _on_mine() -> void:
	var poi_id: String = StateManager.location.get("poi_id", "")
	_set_status("Mining...")
	NetworkManager.send_command("mine", {"id": poi_id}, func(_c): _set_status("Mining complete."))


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
		KEY_F:
			if refuel_button.visible and not refuel_button.disabled:
				_on_refuel()


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
	status_label.modulate = Color.RED if is_error else Color(0.8, 0.8, 0.8)
