extends PanelContainer

## Facilities panel -- station services, owned facilities, and building options.
## Only shown when docked. Three tabs: Station (facilities here), Owned (your
## bases/facilities), Build (construct new facilities).

@onready var tab_container: TabContainer = %FacilityTabs
@onready var status_label: Label = %FacilityStatus
@onready var station_list: VBoxContainer = %StationList
@onready var owned_list: VBoxContainer = %OwnedList
@onready var build_list: VBoxContainer = %BuildList

var _station_facilities: Array = []
var _owned_facilities: Array = []
var _build_types: Array = []


func _ready() -> void:
	NetworkManager.request_started.connect(_lock_ui)
	NetworkManager.request_completed.connect(_unlock_ui)
	tab_container.tab_changed.connect(_on_tab_changed)
	_fetch_station_facilities()


func _on_tab_changed(tab: int) -> void:
	match tab:
		0: _fetch_station_facilities()
		1: _fetch_owned_facilities()
		2: _fetch_build_types()


# ---------------------------------------------------------------------------
# Station tab -- facilities at the current docked station
# ---------------------------------------------------------------------------

func _fetch_station_facilities() -> void:
	status_label.text = "Loading facilities..."
	NetworkManager.send_command("facility_list", {}, func(content: Dictionary) -> void:
		_station_facilities = content.get("facilities", [])
		_refresh_station()
		status_label.text = "%d facilities" % _station_facilities.size()
	)


func _refresh_station() -> void:
	for child in station_list.get_children():
		child.queue_free()

	if _station_facilities.is_empty():
		var empty := Label.new()
		empty.text = "No facilities at this station."
		empty.add_theme_font_size_override("font_size", 12)
		empty.modulate = ThemeColors.TEXT_MUTED
		station_list.add_child(empty)
		return

	station_list.add_child(_make_header(["FACILITY", "TYPE", "OWNER", ""]))

	for facility in _station_facilities:
		var fname: String = facility.get("name", "Unknown")
		var ftype: String = facility.get("type", "")
		var owner_name: String = facility.get("owner", "")
		var services: Array = facility.get("services", [])
		var facility_id: String = facility.get("id", "")

		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)

		var name_label := Label.new()
		name_label.text = fname
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.add_theme_font_size_override("font_size", 12)
		if not services.is_empty():
			name_label.tooltip_text = "Services: %s" % ", ".join(services)
		row.add_child(name_label)

		var type_label := Label.new()
		type_label.text = ftype
		type_label.custom_minimum_size.x = 60
		type_label.add_theme_font_size_override("font_size", 11)
		type_label.modulate = ThemeColors.CHROME_SILVER
		row.add_child(type_label)

		var owner_label := Label.new()
		owner_label.text = owner_name if not owner_name.is_empty() else "NPC"
		owner_label.custom_minimum_size.x = 60
		owner_label.add_theme_font_size_override("font_size", 11)
		owner_label.modulate = ThemeColors.HULL_GREY
		row.add_child(owner_label)

		var use_btn := Button.new()
		use_btn.text = "Use"
		use_btn.add_theme_font_size_override("font_size", 10)
		use_btn.custom_minimum_size.x = 40
		use_btn.pressed.connect(_on_use_facility.bind(facility_id, fname))
		row.add_child(use_btn)

		station_list.add_child(row)


func _on_use_facility(facility_id: String, facility_name: String) -> void:
	status_label.text = "Using %s..." % facility_name
	NetworkManager.send_command("facility_use", {"facility_id": facility_id}, func(content: Dictionary) -> void:
		var result_msg: String = content.get("message", "Done.")
		status_label.text = result_msg
		# Refresh state since using a facility may change cargo/credits
		NetworkManager.send_command("get_status", {}, func(_c): pass)
	)


# ---------------------------------------------------------------------------
# Owned tab -- player-owned facilities with upgrade options
# ---------------------------------------------------------------------------

func _fetch_owned_facilities() -> void:
	status_label.text = "Loading owned facilities..."
	NetworkManager.send_command("facility_owned", {}, func(content: Dictionary) -> void:
		_owned_facilities = content.get("facilities", [])
		_refresh_owned()
		status_label.text = "%d owned" % _owned_facilities.size()
	)


func _refresh_owned() -> void:
	for child in owned_list.get_children():
		child.queue_free()

	if _owned_facilities.is_empty():
		var empty := Label.new()
		empty.text = "You do not own any facilities."
		empty.add_theme_font_size_override("font_size", 12)
		empty.modulate = ThemeColors.TEXT_MUTED
		owned_list.add_child(empty)
		return

	owned_list.add_child(_make_header(["FACILITY", "TYPE", "LEVEL", ""]))

	for facility in _owned_facilities:
		var fname: String = facility.get("name", "Unknown")
		var ftype: String = facility.get("type", "")
		var level: int = facility.get("level", 1)
		var facility_id: String = facility.get("id", "")

		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)

		var name_label := Label.new()
		name_label.text = fname
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.add_theme_font_size_override("font_size", 12)
		row.add_child(name_label)

		var type_label := Label.new()
		type_label.text = ftype
		type_label.custom_minimum_size.x = 60
		type_label.add_theme_font_size_override("font_size", 11)
		type_label.modulate = ThemeColors.CHROME_SILVER
		row.add_child(type_label)

		var level_label := Label.new()
		level_label.text = "Lv %d" % level
		level_label.custom_minimum_size.x = 40
		level_label.add_theme_font_size_override("font_size", 11)
		level_label.modulate = ThemeColors.PLASMA_CYAN
		row.add_child(level_label)

		var upgrade_btn := Button.new()
		upgrade_btn.text = "Upgrade"
		upgrade_btn.add_theme_font_size_override("font_size", 10)
		upgrade_btn.custom_minimum_size.x = 55
		upgrade_btn.pressed.connect(_on_upgrade_pressed.bind(facility_id, fname))
		row.add_child(upgrade_btn)

		station_list_add_facility_details(row, facility)
		owned_list.add_child(row)


func station_list_add_facility_details(row: HBoxContainer, facility: Dictionary) -> void:
	# Add tooltip with details if available
	var services: Array = facility.get("services", [])
	var desc: String = facility.get("description", "")
	var parts := PackedStringArray()
	if not desc.is_empty():
		parts.append(desc)
	if not services.is_empty():
		parts.append("Services: %s" % ", ".join(services))
	if not parts.is_empty():
		# Apply tooltip to the name label (first child)
		var first_child = row.get_child(0)
		if first_child is Label:
			first_child.tooltip_text = "\n".join(parts)


func _on_upgrade_pressed(facility_id: String, facility_name: String) -> void:
	# Fetch upgrade options then show a dialog
	status_label.text = "Checking upgrades..."
	NetworkManager.send_command("facility_upgrades", {"facility_id": facility_id}, func(content: Dictionary) -> void:
		var upgrades: Array = content.get("upgrades", [])
		if upgrades.is_empty():
			status_label.text = "No upgrades available for %s." % facility_name
			return
		_show_upgrade_dialog(facility_id, facility_name, upgrades)
	)


func _show_upgrade_dialog(facility_id: String, facility_name: String, upgrades: Array) -> void:
	var dialog := AcceptDialog.new()
	dialog.title = "Upgrade: %s" % facility_name
	dialog.size = Vector2i(320, 200)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)

	for upgrade in upgrades:
		var utype: String = upgrade.get("upgrade_type", upgrade.get("type", "Unknown"))
		var cost: int = upgrade.get("cost", 0)
		var effects: String = upgrade.get("effects", "")

		var urow := HBoxContainer.new()
		urow.add_theme_constant_override("separation", 8)

		var desc_label := Label.new()
		desc_label.text = "%s  --  %s" % [utype, effects] if not effects.is_empty() else utype
		desc_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		desc_label.add_theme_font_size_override("font_size", 12)
		urow.add_child(desc_label)

		var cost_label := Label.new()
		cost_label.text = "%d cr" % cost
		cost_label.custom_minimum_size.x = 55
		cost_label.add_theme_font_size_override("font_size", 12)
		cost_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		cost_label.modulate = ThemeColors.SHELL_ORANGE
		urow.add_child(cost_label)

		var go_btn := Button.new()
		go_btn.text = "Buy"
		go_btn.add_theme_font_size_override("font_size", 10)
		go_btn.custom_minimum_size.x = 40
		var bound_type := utype
		go_btn.pressed.connect(func():
			dialog.queue_free()
			_execute_upgrade(facility_id, facility_name, bound_type)
		)
		urow.add_child(go_btn)

		vbox.add_child(urow)

	dialog.add_child(vbox)
	dialog.canceled.connect(func(): dialog.queue_free())
	add_child(dialog)
	dialog.popup_centered()


func _execute_upgrade(facility_id: String, facility_name: String, upgrade_type: String) -> void:
	status_label.text = "Upgrading %s..." % facility_name
	NetworkManager.send_command("facility_upgrade", {"facility_id": facility_id, "upgrade_type": upgrade_type}, func(content: Dictionary) -> void:
		var msg: String = content.get("message", "Upgrade complete.")
		status_label.text = msg
		_fetch_owned_facilities()
		NetworkManager.send_command("get_status", {}, func(_c): pass)
	)


# ---------------------------------------------------------------------------
# Build tab -- available facility types to construct
# ---------------------------------------------------------------------------

func _fetch_build_types() -> void:
	status_label.text = "Loading build options..."
	NetworkManager.send_command("facility_types", {}, func(content: Dictionary) -> void:
		_build_types = content.get("types", [])
		_refresh_build()
		status_label.text = "%d types available" % _build_types.size()
	)


func _refresh_build() -> void:
	for child in build_list.get_children():
		child.queue_free()

	if _build_types.is_empty():
		var empty := Label.new()
		empty.text = "No facility types available."
		empty.add_theme_font_size_override("font_size", 12)
		empty.modulate = ThemeColors.TEXT_MUTED
		build_list.add_child(empty)
		return

	build_list.add_child(_make_header(["TYPE", "COST", ""]))

	for ftype in _build_types:
		var type_id: String = ftype.get("type_id", ftype.get("id", ""))
		var fname: String = ftype.get("name", "Unknown")
		var desc: String = ftype.get("description", "")
		var cost: int = ftype.get("cost", 0)
		var requirements: String = ftype.get("requirements", "")

		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)

		var name_label := Label.new()
		name_label.text = fname
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.add_theme_font_size_override("font_size", 12)
		var tip_parts := PackedStringArray()
		if not desc.is_empty():
			tip_parts.append(desc)
		if not requirements.is_empty():
			tip_parts.append("Requires: %s" % requirements)
		if not tip_parts.is_empty():
			name_label.tooltip_text = "\n".join(tip_parts)
		row.add_child(name_label)

		var cost_label := Label.new()
		cost_label.text = "%d cr" % cost if cost > 0 else "Free"
		cost_label.custom_minimum_size.x = 55
		cost_label.add_theme_font_size_override("font_size", 12)
		cost_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		cost_label.modulate = ThemeColors.SHELL_ORANGE if cost > 0 else ThemeColors.BIO_GREEN
		row.add_child(cost_label)

		var build_btn := Button.new()
		build_btn.text = "Build"
		build_btn.add_theme_font_size_override("font_size", 10)
		build_btn.custom_minimum_size.x = 45
		build_btn.pressed.connect(_on_build_pressed.bind(type_id, fname, cost))
		row.add_child(build_btn)

		build_list.add_child(row)


func _on_build_pressed(type_id: String, type_name: String, cost: int) -> void:
	# Confirmation dialog before building
	var dialog := AcceptDialog.new()
	dialog.title = "Build: %s" % type_name
	dialog.size = Vector2i(300, 120)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)

	var info := Label.new()
	info.text = "Build %s for %d credits?" % [type_name, cost]
	info.add_theme_font_size_override("font_size", 12)
	vbox.add_child(info)

	var credits: int = StateManager.player.get("credits", 0)
	var balance := Label.new()
	balance.text = "Your balance: %d cr" % credits
	balance.add_theme_font_size_override("font_size", 11)
	balance.modulate = ThemeColors.BIO_GREEN if credits >= cost else ThemeColors.CLAW_RED
	vbox.add_child(balance)

	dialog.add_child(vbox)
	dialog.confirmed.connect(func():
		dialog.queue_free()
		_execute_build(type_id, type_name)
	)
	dialog.canceled.connect(func(): dialog.queue_free())
	add_child(dialog)
	dialog.popup_centered()


func _execute_build(type_id: String, type_name: String) -> void:
	status_label.text = "Building %s..." % type_name
	NetworkManager.send_command("facility_build", {"type_id": type_id}, func(content: Dictionary) -> void:
		var msg: String = content.get("message", "Facility built.")
		status_label.text = msg
		_fetch_build_types()
		NetworkManager.send_command("get_status", {}, func(_c): pass)
	)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _make_header(cols: Array) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	for i in cols.size():
		var lbl := Label.new()
		lbl.text = cols[i]
		lbl.add_theme_font_size_override("font_size", 10)
		lbl.modulate = ThemeColors.HULL_GREY
		if i == 0:
			lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		elif cols[i].is_empty():
			lbl.custom_minimum_size.x = 50
		else:
			lbl.custom_minimum_size.x = 55
		row.add_child(lbl)
	return row


func _lock_ui() -> void:
	_set_buttons_disabled(true)


func _unlock_ui() -> void:
	_set_buttons_disabled(false)


func _set_buttons_disabled(disabled: bool) -> void:
	for container in [station_list, owned_list, build_list]:
		if not container:
			continue
		for child in container.get_children():
			if child is HBoxContainer:
				for node in child.get_children():
					if node is Button:
						node.disabled = disabled
