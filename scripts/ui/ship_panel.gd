extends PanelContainer
class_name ShipPanel

## Ship management panel — view owned ships, switch active ship, browse shipyard,
## manage modules, track commissions, and browse the ship marketplace.

@onready var tab_container: TabContainer = %ShipTabs
@onready var status_label: Label = %ShipStatus
@onready var my_ships_list: VBoxContainer = %MyShipsList
@onready var shipyard_list: VBoxContainer = %ShipyardList
@onready var modules_list: VBoxContainer = %ModulesList
@onready var commissions_list: VBoxContainer = %CommissionsList
@onready var market_list: VBoxContainer = %MarketList

var _my_ships: Array = []
var _active_ship_id: String = ""
var _shipyard_ships: Array = []
var _commissions: Array = []
var _market_listings: Array = []


func _ready() -> void:
	NetworkManager.request_started.connect(_lock_ui)
	NetworkManager.request_completed.connect(_unlock_ui)
	tab_container.tab_changed.connect(_on_tab_changed)
	_fetch_my_ships()


func _on_tab_changed(tab: int) -> void:
	match tab:
		0: _fetch_my_ships()
		1: _fetch_shipyard()
		2: _refresh_modules()
		3: _fetch_commissions()
		4: _fetch_market()


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
		empty.modulate = ThemeColors.TEXT_MUTED
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
			name_label.modulate = ThemeColors.ACTIVE
		name_row.add_child(name_label)

		var status_lbl := Label.new()
		status_lbl.text = "ACTIVE" if is_active else "Stored"
		status_lbl.add_theme_font_size_override("font_size", 11)
		status_lbl.modulate = ThemeColors.ACTIVE if is_active else ThemeColors.TEXT_SECONDARY
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
		hull_label.modulate = ThemeColors.CHROME_SILVER
		stats_row.add_child(hull_label)

		var fuel_label := Label.new()
		fuel_label.text = "Fuel: %d" % fuel
		fuel_label.add_theme_font_size_override("font_size", 11)
		fuel_label.modulate = ThemeColors.CHROME_SILVER
		stats_row.add_child(fuel_label)

		var cargo_label := Label.new()
		cargo_label.text = "Cargo: %d" % cargo_used
		cargo_label.add_theme_font_size_override("font_size", 11)
		cargo_label.modulate = ThemeColors.CHROME_SILVER
		stats_row.add_child(cargo_label)

		card.add_child(stats_row)

		# Location row (for non-active ships)
		if not is_active and not location_str.is_empty():
			var loc_label := Label.new()
			loc_label.text = "Location: %s" % location_str
			loc_label.add_theme_font_size_override("font_size", 10)
			loc_label.modulate = ThemeColors.TEXT_MUTED
			card.add_child(loc_label)

		# Separator
		var sep := HSeparator.new()
		sep.modulate = ThemeColors.DIM_GREY
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
	msg.modulate = ThemeColors.TEXT_MUTED
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
		empty.modulate = ThemeColors.TEXT_MUTED
		shipyard_list.add_child(empty)
		return

	# Header
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 4)

	var h_name := Label.new()
	h_name.text = "SHIP"
	h_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h_name.add_theme_font_size_override("font_size", 10)
	h_name.modulate = ThemeColors.HULL_GREY
	header.add_child(h_name)

	var h_price := Label.new()
	h_price.text = "PRICE"
	h_price.custom_minimum_size.x = 65
	h_price.add_theme_font_size_override("font_size", 10)
	h_price.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	h_price.modulate = ThemeColors.HULL_GREY
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
		price_label.text = "%d cr" % price if price > 0 else "--"
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
			hull_lbl.modulate = ThemeColors.TEXT_SECONDARY
			stats_row.add_child(hull_lbl)

		if fuel_max > 0:
			var fuel_lbl := Label.new()
			fuel_lbl.text = "Fuel: %d" % fuel_max
			fuel_lbl.add_theme_font_size_override("font_size", 10)
			fuel_lbl.modulate = ThemeColors.TEXT_SECONDARY
			stats_row.add_child(fuel_lbl)

		if cargo_cap > 0:
			var cargo_lbl := Label.new()
			cargo_lbl.text = "Cargo: %d" % cargo_cap
			cargo_lbl.add_theme_font_size_override("font_size", 10)
			cargo_lbl.modulate = ThemeColors.TEXT_SECONDARY
			stats_row.add_child(cargo_lbl)

		if stats_row.get_child_count() > 0:
			card.add_child(stats_row)

		# Separator
		var sep := HSeparator.new()
		sep.modulate = ThemeColors.DIM_GREY
		card.add_child(sep)

		shipyard_list.add_child(card)


func _on_buy_pressed(class_id: String, ship_name: String, price: int) -> void:
	# Confirm dialog
	var dialog := AcceptDialog.new()
	dialog.title = "Buy Ship"
	dialog.dialog_text = "Buy %s for %d cr?" % [ship_name, price]
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


# ==========================================================================
# --- Modules tab ---
# ==========================================================================

func _refresh_modules() -> void:
	_clear_container(modules_list)

	var docked := StateManager.is_docked()

	# -- Section: Installed Modules --
	var header := _make_section_header("INSTALLED MODULES")
	modules_list.add_child(header)

	var installed: Array = StateManager.modules
	if installed.is_empty():
		modules_list.add_child(_make_muted_label("No modules installed."))
	else:
		for mod in installed:
			var card := _build_installed_module_card(mod, docked)
			modules_list.add_child(card)

	# Separator between sections
	var section_sep := HSeparator.new()
	section_sep.modulate = ThemeColors.PLASMA_CYAN
	modules_list.add_child(section_sep)

	# -- Section: Installable Modules from Cargo --
	var cargo_header := _make_section_header("CARGO MODULES")
	modules_list.add_child(cargo_header)

	var installable := get_installable_modules_from_cargo()
	if installable.is_empty():
		modules_list.add_child(_make_muted_label("No installable modules in cargo."))
	else:
		for item in installable:
			var card := _build_cargo_module_card(item, docked)
			modules_list.add_child(card)

	status_label.text = "%d installed, %d in cargo" % [installed.size(), installable.size()]


func _build_installed_module_card(mod: Dictionary, docked: bool) -> VBoxContainer:
	var card := VBoxContainer.new()
	card.add_theme_constant_override("separation", 2)

	var mod_id: String = mod.get("module_id", mod.get("id", ""))
	var mod_name: String = mod.get("name", "Unknown Module")
	var mod_type: String = mod.get("type", "")
	var mod_size: int = mod.get("size", 0)
	var wear: float = mod.get("wear", 0.0)
	var cpu_usage: int = mod.get("cpu", 0)
	var power_usage: int = mod.get("power", 0)

	# Name + type row
	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 6)

	var name_lbl := Label.new()
	name_lbl.text = mod_name
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.add_theme_font_size_override("font_size", 12)
	name_row.add_child(name_lbl)

	if not mod_type.is_empty():
		var type_lbl := Label.new()
		type_lbl.text = mod_type.to_upper()
		type_lbl.add_theme_font_size_override("font_size", 10)
		type_lbl.modulate = ThemeColors.HULL_GREY
		name_row.add_child(type_lbl)

	card.add_child(name_row)

	# Stats row: size, CPU, power, wear
	var stats_row := HBoxContainer.new()
	stats_row.add_theme_constant_override("separation", 8)

	if mod_size > 0:
		var size_lbl := Label.new()
		size_lbl.text = "Size: %d" % mod_size
		size_lbl.add_theme_font_size_override("font_size", 10)
		size_lbl.modulate = ThemeColors.TEXT_SECONDARY
		stats_row.add_child(size_lbl)

	if cpu_usage > 0:
		var cpu_lbl := Label.new()
		cpu_lbl.text = "CPU: %d" % cpu_usage
		cpu_lbl.add_theme_font_size_override("font_size", 10)
		cpu_lbl.modulate = ThemeColors.TEXT_SECONDARY
		stats_row.add_child(cpu_lbl)

	if power_usage > 0:
		var pwr_lbl := Label.new()
		pwr_lbl.text = "PWR: %d" % power_usage
		pwr_lbl.add_theme_font_size_override("font_size", 10)
		pwr_lbl.modulate = ThemeColors.TEXT_SECONDARY
		stats_row.add_child(pwr_lbl)

	# Wear percentage
	var wear_pct := compute_wear_pct(wear)
	var wear_lbl := Label.new()
	wear_lbl.text = "Wear: %d%%" % wear_pct
	wear_lbl.add_theme_font_size_override("font_size", 10)
	if wear_pct > 50:
		wear_lbl.modulate = ThemeColors.CLAW_RED
	elif wear_pct > 20:
		wear_lbl.modulate = ThemeColors.WARNING_YELLOW
	else:
		wear_lbl.modulate = ThemeColors.BIO_GREEN
	stats_row.add_child(wear_lbl)

	card.add_child(stats_row)

	# Action buttons row
	if docked:
		var btn_row := HBoxContainer.new()
		btn_row.add_theme_constant_override("separation", 4)

		var uninstall_btn := Button.new()
		uninstall_btn.text = "Uninstall"
		uninstall_btn.add_theme_font_size_override("font_size", 10)
		uninstall_btn.custom_minimum_size.x = 65
		uninstall_btn.pressed.connect(_on_uninstall_module.bind(mod_id, mod_name))
		btn_row.add_child(uninstall_btn)

		if wear_pct > 0:
			var repair_btn := Button.new()
			repair_btn.text = "Repair"
			repair_btn.add_theme_font_size_override("font_size", 10)
			repair_btn.custom_minimum_size.x = 55
			repair_btn.pressed.connect(_on_repair_module.bind(mod_id, mod_name))
			btn_row.add_child(repair_btn)

		card.add_child(btn_row)

	# Separator
	var sep := HSeparator.new()
	sep.modulate = ThemeColors.DIM_GREY
	card.add_child(sep)

	return card


func _build_cargo_module_card(item: Dictionary, docked: bool) -> VBoxContainer:
	var card := VBoxContainer.new()
	card.add_theme_constant_override("separation", 2)

	var item_id: String = item.get("item_id", item.get("id", ""))
	var item_name: String = item.get("item_name", item.get("name", "Unknown"))
	var item_type: String = item.get("type", item.get("item_type", ""))
	var quantity: int = item.get("quantity", 1)

	# Name row
	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 6)

	var name_lbl := Label.new()
	name_lbl.text = item_name
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.add_theme_font_size_override("font_size", 12)
	name_row.add_child(name_lbl)

	if quantity > 1:
		var qty_lbl := Label.new()
		qty_lbl.text = "x%d" % quantity
		qty_lbl.add_theme_font_size_override("font_size", 10)
		qty_lbl.modulate = ThemeColors.TEXT_SECONDARY
		name_row.add_child(qty_lbl)

	if not item_type.is_empty():
		var type_lbl := Label.new()
		type_lbl.text = item_type.to_upper()
		type_lbl.add_theme_font_size_override("font_size", 10)
		type_lbl.modulate = ThemeColors.HULL_GREY
		name_row.add_child(type_lbl)

	card.add_child(name_row)

	# Install button
	if docked:
		var install_btn := Button.new()
		install_btn.text = "Install"
		install_btn.add_theme_font_size_override("font_size", 10)
		install_btn.custom_minimum_size.x = 55
		install_btn.pressed.connect(_on_install_module.bind(item_id, item_name))
		card.add_child(install_btn)

	# Separator
	var sep := HSeparator.new()
	sep.modulate = ThemeColors.DIM_GREY
	card.add_child(sep)

	return card


func _on_install_module(module_id: String, module_name: String) -> void:
	status_label.text = "Installing %s..." % module_name
	NetworkManager.send_command("install_mod", {"module_id": module_id}, func(_content: Dictionary) -> void:
		status_label.text = "Installed %s." % module_name
		_refresh_modules()
	)


func _on_uninstall_module(module_id: String, module_name: String) -> void:
	status_label.text = "Uninstalling %s..." % module_name
	NetworkManager.send_command("uninstall_mod", {"module_id": module_id}, func(_content: Dictionary) -> void:
		status_label.text = "Uninstalled %s." % module_name
		_refresh_modules()
	)


func _on_repair_module(module_id: String, module_name: String) -> void:
	status_label.text = "Repairing %s..." % module_name
	NetworkManager.send_command("repair_module", {"module_id": module_id}, func(_content: Dictionary) -> void:
		status_label.text = "Repaired %s." % module_name
		_refresh_modules()
	)


## Returns cargo items that are modules (type contains "module" or category is module-like).
static func get_installable_modules_from_cargo() -> Array:
	var result: Array = []
	for item in StateManager.cargo:
		var item_type: String = item.get("type", item.get("item_type", "")).to_lower()
		var category: String = item.get("category", "").to_lower()
		if item_type.contains("module") or category.contains("module"):
			result.append(item)
	return result


## Computes wear as an integer percentage (0-100) from a float 0.0-1.0 or 0-100.
static func compute_wear_pct(wear_value) -> int:
	var w: float = float(wear_value)
	# If the value is > 1.0 treat it as already a percentage
	if w > 1.0:
		return clampi(int(w), 0, 100)
	return clampi(int(w * 100.0), 0, 100)


# ==========================================================================
# --- Commissions tab ---
# ==========================================================================

func _fetch_commissions() -> void:
	if not StateManager.is_docked():
		_clear_container(commissions_list)
		commissions_list.add_child(_make_muted_label("Dock at a station to view commissions."))
		status_label.text = "Not docked"
		return

	status_label.text = "Loading commissions..."
	NetworkManager.send_command("commission_status", {}, func(content: Dictionary) -> void:
		_commissions = content.get("commissions", [])
		_refresh_commissions()
		status_label.text = "%d commissions" % _commissions.size()
	)


func _refresh_commissions() -> void:
	_clear_container(commissions_list)

	# -- Active commissions --
	var active_header := _make_section_header("YOUR COMMISSIONS")
	commissions_list.add_child(active_header)

	if _commissions.is_empty():
		commissions_list.add_child(_make_muted_label("No active commissions."))
	else:
		for commission in _commissions:
			var card := _build_commission_card(commission)
			commissions_list.add_child(card)

	# Separator
	var section_sep := HSeparator.new()
	section_sep.modulate = ThemeColors.PLASMA_CYAN
	commissions_list.add_child(section_sep)

	# -- Commission new ship section --
	var new_header := _make_section_header("COMMISSION NEW SHIP")
	commissions_list.add_child(new_header)

	var quote_btn := Button.new()
	quote_btn.text = "Get Quote..."
	quote_btn.add_theme_font_size_override("font_size", 10)
	quote_btn.custom_minimum_size.x = 90
	quote_btn.pressed.connect(_on_commission_quote_pressed)
	commissions_list.add_child(quote_btn)


func _build_commission_card(commission: Dictionary) -> VBoxContainer:
	var card := VBoxContainer.new()
	card.add_theme_constant_override("separation", 2)

	var comm_id: String = commission.get("id", "")
	var ship_class: String = commission.get("ship_class", "Unknown")
	var ship_name: String = commission.get("name", ship_class)
	var comm_status: String = commission.get("status", "building")
	var eta: String = commission.get("eta", "")

	# Name + status row
	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 6)

	var name_lbl := Label.new()
	name_lbl.text = ship_name
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.add_theme_font_size_override("font_size", 12)
	name_row.add_child(name_lbl)

	var status_lbl := Label.new()
	status_lbl.text = comm_status.to_upper()
	status_lbl.add_theme_font_size_override("font_size", 10)
	match comm_status:
		"complete", "ready":
			status_lbl.modulate = ThemeColors.BIO_GREEN
		"building", "in_progress":
			status_lbl.modulate = ThemeColors.WARNING_YELLOW
		"cancelled":
			status_lbl.modulate = ThemeColors.CLAW_RED
		_:
			status_lbl.modulate = ThemeColors.TEXT_SECONDARY
	name_row.add_child(status_lbl)

	card.add_child(name_row)

	# ETA row
	if not eta.is_empty() and comm_status != "complete" and comm_status != "ready":
		var eta_lbl := Label.new()
		eta_lbl.text = "ETA: %s" % eta
		eta_lbl.add_theme_font_size_override("font_size", 10)
		eta_lbl.modulate = ThemeColors.TEXT_SECONDARY
		card.add_child(eta_lbl)

	# Action buttons
	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 4)

	if comm_status == "complete" or comm_status == "ready":
		var claim_btn := Button.new()
		claim_btn.text = "Claim"
		claim_btn.add_theme_font_size_override("font_size", 10)
		claim_btn.custom_minimum_size.x = 50
		claim_btn.pressed.connect(_on_commission_claim.bind(comm_id, ship_name))
		btn_row.add_child(claim_btn)

	if comm_status != "complete" and comm_status != "ready" and comm_status != "cancelled":
		var cancel_btn := Button.new()
		cancel_btn.text = "Cancel"
		cancel_btn.add_theme_font_size_override("font_size", 10)
		cancel_btn.custom_minimum_size.x = 50
		cancel_btn.pressed.connect(_on_commission_cancel.bind(comm_id, ship_name))
		btn_row.add_child(cancel_btn)

	if btn_row.get_child_count() > 0:
		card.add_child(btn_row)

	# Separator
	var sep := HSeparator.new()
	sep.modulate = ThemeColors.DIM_GREY
	card.add_child(sep)

	return card


func _on_commission_claim(comm_id: String, ship_name: String) -> void:
	status_label.text = "Claiming %s..." % ship_name
	NetworkManager.send_command("commission_claim", {"commission_id": comm_id}, func(_content: Dictionary) -> void:
		status_label.text = "Claimed %s!" % ship_name
		_fetch_commissions()
		NetworkManager.send_command("get_status", {})
	)


func _on_commission_cancel(comm_id: String, ship_name: String) -> void:
	var dialog := AcceptDialog.new()
	dialog.title = "Cancel Commission"
	dialog.dialog_text = "Cancel commission for %s?" % ship_name
	dialog.size = Vector2i(280, 120)

	dialog.confirmed.connect(func():
		status_label.text = "Cancelling %s..." % ship_name
		NetworkManager.send_command("commission_cancel", {"commission_id": comm_id}, func(_content: Dictionary) -> void:
			status_label.text = "Cancelled %s." % ship_name
			_fetch_commissions()
		)
		dialog.queue_free()
	)
	dialog.canceled.connect(func(): dialog.queue_free())

	add_child(dialog)
	dialog.popup_centered()


func _on_commission_quote_pressed() -> void:
	# For now, prompt for a ship class ID. In the future this could be a dropdown.
	var dialog := AcceptDialog.new()
	dialog.title = "Commission Quote"
	dialog.dialog_text = "Enter ship class ID:"
	dialog.size = Vector2i(300, 160)

	var input := LineEdit.new()
	input.placeholder_text = "e.g. scout_mk2"
	input.add_theme_font_size_override("font_size", 12)
	dialog.add_child(input)

	dialog.confirmed.connect(func():
		var class_id: String = input.text.strip_edges()
		if class_id.is_empty():
			dialog.queue_free()
			return
		_get_commission_quote(class_id)
		dialog.queue_free()
	)
	dialog.canceled.connect(func(): dialog.queue_free())

	add_child(dialog)
	dialog.popup_centered()


func _get_commission_quote(class_id: String) -> void:
	status_label.text = "Getting quote..."
	NetworkManager.send_command("commission_quote", {"ship_class": class_id}, func(content: Dictionary) -> void:
		var cost: int = content.get("cost", 0)
		var duration: String = content.get("duration", "unknown")
		var requirements: String = content.get("requirements", "")

		var info_dialog := AcceptDialog.new()
		info_dialog.title = "Commission Quote"
		var msg := "Ship: %s\nCost: %d cr\nBuild Time: %s" % [class_id, cost, duration]
		if not requirements.is_empty():
			msg += "\nRequirements: %s" % requirements
		info_dialog.dialog_text = msg
		info_dialog.size = Vector2i(320, 200)

		# Add a "Commission" button
		info_dialog.add_button("Commission", false, "commission")
		info_dialog.custom_action.connect(func(action: StringName):
			if action == "commission":
				_start_commission(class_id)
				info_dialog.queue_free()
		)
		info_dialog.canceled.connect(func(): info_dialog.queue_free())
		info_dialog.confirmed.connect(func(): info_dialog.queue_free())

		add_child(info_dialog)
		info_dialog.popup_centered()
		status_label.text = "Quote received."
	)


func _start_commission(class_id: String) -> void:
	status_label.text = "Commissioning %s..." % class_id
	NetworkManager.send_command("commission_ship", {"ship_class": class_id, "name": ""}, func(_content: Dictionary) -> void:
		status_label.text = "Commission started!"
		_fetch_commissions()
	)


# ==========================================================================
# --- Ship Market tab ---
# ==========================================================================

func _fetch_market() -> void:
	if not StateManager.is_docked():
		_clear_container(market_list)
		market_list.add_child(_make_muted_label("Dock at a station to browse the ship market."))
		status_label.text = "Not docked"
		return

	status_label.text = "Loading ship market..."
	NetworkManager.send_command("browse_ships", {}, func(content: Dictionary) -> void:
		_market_listings = content.get("listings", [])
		_refresh_market()
		status_label.text = "%d listings" % _market_listings.size()
	)


func _refresh_market() -> void:
	_clear_container(market_list)

	# Header
	var header := _make_section_header("SHIP MARKETPLACE")
	market_list.add_child(header)

	if _market_listings.is_empty():
		market_list.add_child(_make_muted_label("No ships listed for sale."))
	else:
		for listing in _market_listings:
			var card := _build_market_listing_card(listing)
			market_list.add_child(card)

	# Separator
	var section_sep := HSeparator.new()
	section_sep.modulate = ThemeColors.PLASMA_CYAN
	market_list.add_child(section_sep)

	# Sell section
	var sell_header := _make_section_header("LIST YOUR SHIP")
	market_list.add_child(sell_header)

	var sell_btn := Button.new()
	sell_btn.text = "List a Ship for Sale..."
	sell_btn.add_theme_font_size_override("font_size", 10)
	sell_btn.custom_minimum_size.x = 130
	sell_btn.pressed.connect(_on_list_ship_for_sale_pressed)
	market_list.add_child(sell_btn)


func _build_market_listing_card(listing: Dictionary) -> VBoxContainer:
	var card := VBoxContainer.new()
	card.add_theme_constant_override("separation", 2)

	var listing_id: String = listing.get("listing_id", listing.get("id", ""))
	var ship_class_name: String = listing.get("ship_class_name", listing.get("class_name", "Unknown"))
	var seller: String = listing.get("seller", listing.get("seller_name", ""))
	var price: int = listing.get("price", 0)
	var is_own: bool = listing.get("is_own", false)

	# Name + price row
	var top_row := HBoxContainer.new()
	top_row.add_theme_constant_override("separation", 4)

	var name_lbl := Label.new()
	name_lbl.text = ship_class_name
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.add_theme_font_size_override("font_size", 12)
	top_row.add_child(name_lbl)

	var price_lbl := Label.new()
	price_lbl.text = "%d cr" % price if price > 0 else "--"
	price_lbl.custom_minimum_size.x = 65
	price_lbl.add_theme_font_size_override("font_size", 12)
	price_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	price_lbl.modulate = ThemeColors.SHELL_ORANGE
	top_row.add_child(price_lbl)

	card.add_child(top_row)

	# Seller row
	if not seller.is_empty():
		var seller_lbl := Label.new()
		seller_lbl.text = "Seller: %s" % seller
		seller_lbl.add_theme_font_size_override("font_size", 10)
		seller_lbl.modulate = ThemeColors.TEXT_MUTED
		card.add_child(seller_lbl)

	# Action buttons
	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 4)

	if is_own:
		var cancel_btn := Button.new()
		cancel_btn.text = "Cancel Listing"
		cancel_btn.add_theme_font_size_override("font_size", 10)
		cancel_btn.custom_minimum_size.x = 85
		cancel_btn.pressed.connect(_on_cancel_listing.bind(listing_id, ship_class_name))
		btn_row.add_child(cancel_btn)
	else:
		var buy_btn := Button.new()
		buy_btn.text = "Buy"
		buy_btn.add_theme_font_size_override("font_size", 10)
		buy_btn.custom_minimum_size.x = 40
		buy_btn.pressed.connect(_on_buy_listed_ship.bind(listing_id, ship_class_name, price))
		btn_row.add_child(buy_btn)

	if btn_row.get_child_count() > 0:
		card.add_child(btn_row)

	# Separator
	var sep := HSeparator.new()
	sep.modulate = ThemeColors.DIM_GREY
	card.add_child(sep)

	return card


func _on_buy_listed_ship(listing_id: String, ship_name: String, price: int) -> void:
	var dialog := AcceptDialog.new()
	dialog.title = "Buy Listed Ship"
	dialog.dialog_text = "Buy %s for %d cr from another player?" % [ship_name, price]
	dialog.size = Vector2i(300, 120)

	dialog.confirmed.connect(func():
		status_label.text = "Buying %s..." % ship_name
		NetworkManager.send_command("buy_listed_ship", {"listing_id": listing_id}, func(_content: Dictionary) -> void:
			status_label.text = "Bought %s!" % ship_name
			_fetch_market()
			NetworkManager.send_command("get_status", {})
		)
		dialog.queue_free()
	)
	dialog.canceled.connect(func(): dialog.queue_free())

	add_child(dialog)
	dialog.popup_centered()


func _on_cancel_listing(listing_id: String, ship_name: String) -> void:
	status_label.text = "Cancelling listing for %s..." % ship_name
	NetworkManager.send_command("cancel_ship_listing", {"listing_id": listing_id}, func(_content: Dictionary) -> void:
		status_label.text = "Listing cancelled."
		_fetch_market()
	)


func _on_list_ship_for_sale_pressed() -> void:
	var dialog := AcceptDialog.new()
	dialog.title = "List Ship for Sale"
	dialog.dialog_text = "Enter ship ID and asking price:"
	dialog.size = Vector2i(320, 200)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)

	var id_label := Label.new()
	id_label.text = "Ship ID:"
	id_label.add_theme_font_size_override("font_size", 10)
	vbox.add_child(id_label)

	var id_input := LineEdit.new()
	id_input.placeholder_text = "ship_id"
	id_input.add_theme_font_size_override("font_size", 12)
	vbox.add_child(id_input)

	var price_label := Label.new()
	price_label.text = "Price (credits):"
	price_label.add_theme_font_size_override("font_size", 10)
	vbox.add_child(price_label)

	var price_input := LineEdit.new()
	price_input.placeholder_text = "1000"
	price_input.add_theme_font_size_override("font_size", 12)
	vbox.add_child(price_input)

	dialog.add_child(vbox)

	dialog.confirmed.connect(func():
		var ship_id: String = id_input.text.strip_edges()
		var price_str: String = price_input.text.strip_edges()
		if ship_id.is_empty() or price_str.is_empty():
			dialog.queue_free()
			return
		var price: int = int(price_str)
		if price <= 0:
			dialog.queue_free()
			return
		_list_ship_for_sale(ship_id, price)
		dialog.queue_free()
	)
	dialog.canceled.connect(func(): dialog.queue_free())

	add_child(dialog)
	dialog.popup_centered()


func _list_ship_for_sale(ship_id: String, price: int) -> void:
	status_label.text = "Listing ship for sale..."
	NetworkManager.send_command("list_ship_for_sale", {"ship_id": ship_id, "price": price}, func(_content: Dictionary) -> void:
		status_label.text = "Ship listed for %d cr." % price
		_fetch_market()
	)


# ==========================================================================
# --- Shared helpers ---
# ==========================================================================

func _clear_container(container: VBoxContainer) -> void:
	for child in container.get_children():
		child.queue_free()


func _make_section_header(text: String) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 14)
	lbl.modulate = ThemeColors.PLASMA_CYAN
	return lbl


func _make_muted_label(text: String) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 12)
	lbl.modulate = ThemeColors.TEXT_MUTED
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return lbl


# --- UI lock/unlock ---

func _lock_ui() -> void:
	_set_buttons_disabled(true)


func _unlock_ui() -> void:
	_set_buttons_disabled(false)


func _set_buttons_disabled(disabled: bool) -> void:
	for container in [my_ships_list, shipyard_list, modules_list, commissions_list, market_list]:
		if not container:
			continue
		_set_buttons_in_tree(container, disabled)


func _set_buttons_in_tree(node: Node, disabled: bool) -> void:
	for child in node.get_children():
		if child is Button:
			child.disabled = disabled
		elif child.get_child_count() > 0:
			_set_buttons_in_tree(child, disabled)
