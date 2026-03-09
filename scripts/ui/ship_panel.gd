extends PanelContainer

## Ship management panel — view owned ships, switch active ship, browse shipyard.

@onready var tab_container: TabContainer = %ShipTabs
@onready var status_label: Label = %ShipStatus
@onready var my_ships_list: VBoxContainer = %MyShipsList
@onready var shipyard_list: VBoxContainer = %ShipyardList

var _my_ships: Array = []
var _active_ship_id: String = ""
var _shipyard_ships: Array = []


func _ready() -> void:
	NetworkManager.request_started.connect(_lock_ui)
	NetworkManager.request_completed.connect(_unlock_ui)
	tab_container.tab_changed.connect(_on_tab_changed)
	_fetch_my_ships()


func _on_tab_changed(tab: int) -> void:
	match tab:
		0: _fetch_my_ships()
		1: _fetch_shipyard()


# --- My Ships tab ---

func _fetch_my_ships() -> void:
	status_label.text = "Loading ships..."
	NetworkManager.send_ship_command("list_ships", {}, func(content: Dictionary) -> void:
		_my_ships = content.get("ships", [])
		_active_ship_id = content.get("active_ship_id", "")
		_refresh_my_ships()
		status_label.text = "%d ships" % _my_ships.size()
	)


func _refresh_my_ships() -> void:
	for child in my_ships_list.get_children():
		child.queue_free()

	if _my_ships.is_empty():
		var empty := Label.new()
		empty.text = "No ships found."
		empty.add_theme_font_size_override("font_size", 12)
		empty.modulate = Color(0.5, 0.5, 0.5)
		my_ships_list.add_child(empty)
		return

	var docked := StateManager.is_docked()

	for ship in _my_ships:
		var ship_id: String = ship.get("ship_id", "")
		var class_name_str: String = ship.get("class_name", "Unknown")
		var is_active: bool = ship.get("is_active", false)
		var hull: int = ship.get("hull", 0)
		var fuel: int = ship.get("fuel", 0)
		var cargo_used: int = ship.get("cargo_used", 0)
		var location_str: String = ship.get("location", "")

		var card := VBoxContainer.new()
		card.add_theme_constant_override("separation", 2)

		# Ship name row
		var name_row := HBoxContainer.new()
		name_row.add_theme_constant_override("separation", 6)

		var name_label := Label.new()
		name_label.text = class_name_str
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.add_theme_font_size_override("font_size", 13)
		if is_active:
			name_label.modulate = Color(0.4, 1.0, 0.4)
		name_row.add_child(name_label)

		var status_lbl := Label.new()
		status_lbl.text = "ACTIVE" if is_active else "Stored"
		status_lbl.add_theme_font_size_override("font_size", 11)
		status_lbl.modulate = Color(0.4, 1.0, 0.4) if is_active else Color(0.6, 0.6, 0.6)
		name_row.add_child(status_lbl)

		if not is_active and docked:
			var switch_btn := Button.new()
			switch_btn.text = "Switch"
			switch_btn.add_theme_font_size_override("font_size", 10)
			switch_btn.custom_minimum_size.x = 55
			switch_btn.pressed.connect(_on_switch_pressed.bind(ship_id, class_name_str))
			name_row.add_child(switch_btn)

		card.add_child(name_row)

		# Stats row
		var stats_row := HBoxContainer.new()
		stats_row.add_theme_constant_override("separation", 8)

		var hull_label := Label.new()
		hull_label.text = "Hull: %d" % hull
		hull_label.add_theme_font_size_override("font_size", 11)
		hull_label.modulate = Color(0.7, 0.7, 0.7)
		stats_row.add_child(hull_label)

		var fuel_label := Label.new()
		fuel_label.text = "Fuel: %d" % fuel
		fuel_label.add_theme_font_size_override("font_size", 11)
		fuel_label.modulate = Color(0.7, 0.7, 0.7)
		stats_row.add_child(fuel_label)

		var cargo_label := Label.new()
		cargo_label.text = "Cargo: %d" % cargo_used
		cargo_label.add_theme_font_size_override("font_size", 11)
		cargo_label.modulate = Color(0.7, 0.7, 0.7)
		stats_row.add_child(cargo_label)

		card.add_child(stats_row)

		# Location row (for non-active ships)
		if not is_active and not location_str.is_empty():
			var loc_label := Label.new()
			loc_label.text = "Location: %s" % location_str
			loc_label.add_theme_font_size_override("font_size", 10)
			loc_label.modulate = Color(0.5, 0.5, 0.5)
			card.add_child(loc_label)

		# Separator
		var sep := HSeparator.new()
		sep.modulate = Color(0.3, 0.3, 0.3)
		card.add_child(sep)

		my_ships_list.add_child(card)


func _on_switch_pressed(ship_id: String, ship_name: String) -> void:
	status_label.text = "Switching to %s..." % ship_name
	NetworkManager.send_ship_command("switch_ship", {"ship_id": ship_id}, func(content: Dictionary) -> void:
		status_label.text = "Switched to %s." % ship_name
		_active_ship_id = content.get("active_ship_id", ship_id)
		_fetch_my_ships()
		NetworkManager.send_command("get_status", {})
	)


# --- Shipyard tab ---

func _fetch_shipyard() -> void:
	if not StateManager.is_docked():
		_shipyard_ships = []
		_refresh_shipyard_not_docked()
		return

	status_label.text = "Browsing shipyard..."
	NetworkManager.send_ship_command("browse_ships", {}, func(content: Dictionary) -> void:
		_shipyard_ships = content.get("ships", [])
		_refresh_shipyard()
		status_label.text = "%d ships available" % _shipyard_ships.size()
	)


func _refresh_shipyard_not_docked() -> void:
	for child in shipyard_list.get_children():
		child.queue_free()

	var msg := Label.new()
	msg.text = "Dock at a station to browse the shipyard."
	msg.add_theme_font_size_override("font_size", 12)
	msg.modulate = Color(0.5, 0.5, 0.5)
	msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	shipyard_list.add_child(msg)
	status_label.text = "Not docked"


func _refresh_shipyard() -> void:
	for child in shipyard_list.get_children():
		child.queue_free()

	if _shipyard_ships.is_empty():
		var empty := Label.new()
		empty.text = "No ships available at this station."
		empty.add_theme_font_size_override("font_size", 12)
		empty.modulate = Color(0.5, 0.5, 0.5)
		shipyard_list.add_child(empty)
		return

	# Header
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 4)

	var h_name := Label.new()
	h_name.text = "SHIP"
	h_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h_name.add_theme_font_size_override("font_size", 10)
	h_name.modulate = Color(0.5, 0.6, 0.7)
	header.add_child(h_name)

	var h_price := Label.new()
	h_price.text = "PRICE"
	h_price.custom_minimum_size.x = 65
	h_price.add_theme_font_size_override("font_size", 10)
	h_price.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	h_price.modulate = Color(0.5, 0.6, 0.7)
	header.add_child(h_price)

	var h_spacer := Label.new()
	h_spacer.custom_minimum_size.x = 40
	header.add_child(h_spacer)

	shipyard_list.add_child(header)

	for ship in _shipyard_ships:
		var class_id: String = ship.get("class_id", "")
		var class_name_str: String = ship.get("class_name", ship.get("name", "Unknown"))
		var price: int = ship.get("price", 0)
		var hull_max: int = ship.get("max_hull", ship.get("hull", 0))
		var fuel_max: int = ship.get("max_fuel", ship.get("fuel", 0))
		var cargo_cap: int = ship.get("cargo_capacity", 0)

		var card := VBoxContainer.new()
		card.add_theme_constant_override("separation", 2)

		# Name + price + buy row
		var top_row := HBoxContainer.new()
		top_row.add_theme_constant_override("separation", 4)

		var name_label := Label.new()
		name_label.text = class_name_str
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.add_theme_font_size_override("font_size", 12)
		top_row.add_child(name_label)

		var price_label := Label.new()
		price_label.text = "¢%d" % price if price > 0 else "—"
		price_label.custom_minimum_size.x = 65
		price_label.add_theme_font_size_override("font_size", 12)
		price_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		top_row.add_child(price_label)

		var buy_btn := Button.new()
		buy_btn.text = "Buy"
		buy_btn.add_theme_font_size_override("font_size", 10)
		buy_btn.custom_minimum_size.x = 40
		buy_btn.pressed.connect(_on_buy_pressed.bind(class_id, class_name_str, price))
		top_row.add_child(buy_btn)

		card.add_child(top_row)

		# Stats row
		var stats_row := HBoxContainer.new()
		stats_row.add_theme_constant_override("separation", 8)

		if hull_max > 0:
			var hull_lbl := Label.new()
			hull_lbl.text = "Hull: %d" % hull_max
			hull_lbl.add_theme_font_size_override("font_size", 10)
			hull_lbl.modulate = Color(0.6, 0.6, 0.6)
			stats_row.add_child(hull_lbl)

		if fuel_max > 0:
			var fuel_lbl := Label.new()
			fuel_lbl.text = "Fuel: %d" % fuel_max
			fuel_lbl.add_theme_font_size_override("font_size", 10)
			fuel_lbl.modulate = Color(0.6, 0.6, 0.6)
			stats_row.add_child(fuel_lbl)

		if cargo_cap > 0:
			var cargo_lbl := Label.new()
			cargo_lbl.text = "Cargo: %d" % cargo_cap
			cargo_lbl.add_theme_font_size_override("font_size", 10)
			cargo_lbl.modulate = Color(0.6, 0.6, 0.6)
			stats_row.add_child(cargo_lbl)

		if stats_row.get_child_count() > 0:
			card.add_child(stats_row)

		# Separator
		var sep := HSeparator.new()
		sep.modulate = Color(0.3, 0.3, 0.3)
		card.add_child(sep)

		shipyard_list.add_child(card)


func _on_buy_pressed(class_id: String, ship_name: String, price: int) -> void:
	# Confirm dialog
	var dialog := AcceptDialog.new()
	dialog.title = "Buy Ship"
	dialog.dialog_text = "Buy %s for ¢%d?" % [ship_name, price]
	dialog.size = Vector2i(280, 120)

	dialog.confirmed.connect(func():
		_buy_ship(class_id, ship_name)
		dialog.queue_free()
	)
	dialog.canceled.connect(func(): dialog.queue_free())

	add_child(dialog)
	dialog.popup_centered()


func _buy_ship(class_id: String, ship_name: String) -> void:
	status_label.text = "Buying %s..." % ship_name
	NetworkManager.send_ship_command("buy_ship", {"class_id": class_id}, func(_content: Dictionary) -> void:
		status_label.text = "Bought %s!" % ship_name
		_fetch_my_ships()
		_fetch_shipyard()
		NetworkManager.send_command("get_status", {})
	)


# --- UI lock/unlock ---

func _lock_ui() -> void:
	_set_buttons_disabled(true)


func _unlock_ui() -> void:
	_set_buttons_disabled(false)


func _set_buttons_disabled(disabled: bool) -> void:
	for container in [my_ships_list, shipyard_list]:
		if not container:
			continue
		_set_buttons_in_tree(container, disabled)


func _set_buttons_in_tree(node: Node, disabled: bool) -> void:
	for child in node.get_children():
		if child is Button:
			child.disabled = disabled
		elif child.get_child_count() > 0:
			_set_buttons_in_tree(child, disabled)
