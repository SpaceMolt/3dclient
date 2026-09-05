extends PanelContainer

## Wreck panel -- lists wrecks at the current POI with loot, salvage, and tow
## actions. Only shown when undocked (wrecks are in space, not at stations).

@onready var wreck_list: VBoxContainer = %WreckList
@onready var status_label: Label = %WreckStatus

var _wrecks: Array = []


func _ready() -> void:
	NetworkManager.request_started.connect(_lock_ui)
	NetworkManager.request_completed.connect(_unlock_ui)
	_fetch_wrecks()


func _fetch_wrecks() -> void:
	status_label.text = "Scanning for wrecks..."
	NetworkManager.send_salvage_command("wrecks", {}, func(content: Dictionary) -> void:
		_wrecks = content.get("wrecks", [])
		_refresh()
		status_label.text = "%d wreck%s found" % [_wrecks.size(), "" if _wrecks.size() == 1 else "s"]
	)


func _refresh() -> void:
	for child in wreck_list.get_children():
		child.queue_free()

	if _wrecks.is_empty():
		var empty := Label.new()
		empty.text = "No wrecks at this location."
		empty.add_theme_font_size_override("font_size", 12)
		empty.modulate = ThemeColors.TEXT_MUTED
		wreck_list.add_child(empty)
		return

	for wreck in _wrecks:
		var card := _make_wreck_card(wreck)
		wreck_list.add_child(card)


func _make_wreck_card(wreck: Dictionary) -> VBoxContainer:
	var wreck_id: String = wreck.get("id", wreck.get("wreck_id", ""))
	var player_name: String = wreck.get("player_name", "Unknown")
	var ship_class: String = wreck.get("ship_class", "Unknown")
	var age_ticks: int = wreck.get("age_ticks", 0)
	var items: Array = wreck.get("items", [])

	var card := VBoxContainer.new()
	card.add_theme_constant_override("separation", 2)

	# Wreck header row: name, ship class, age, action buttons
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 4)

	var name_label := Label.new()
	name_label.text = "%s's %s" % [player_name, ship_class]
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.add_theme_font_size_override("font_size", 12)
	name_label.modulate = ThemeColors.CLAW_RED
	header.add_child(name_label)

	var age_label := Label.new()
	age_label.text = format_age(age_ticks)
	age_label.custom_minimum_size.x = 50
	age_label.add_theme_font_size_override("font_size", 10)
	age_label.modulate = ThemeColors.TEXT_MUTED
	age_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	header.add_child(age_label)

	card.add_child(header)

	# Action buttons row: Salvage and Tow
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 4)

	var salvage_btn := Button.new()
	salvage_btn.text = "Salvage"
	salvage_btn.add_theme_font_size_override("font_size", 10)
	salvage_btn.custom_minimum_size.x = 55
	salvage_btn.modulate = ThemeColors.WARNING_YELLOW
	salvage_btn.pressed.connect(_on_salvage_pressed.bind(wreck_id, player_name))
	actions.add_child(salvage_btn)

	var tow_btn := Button.new()
	tow_btn.text = "Tow"
	tow_btn.add_theme_font_size_override("font_size", 10)
	tow_btn.custom_minimum_size.x = 40
	tow_btn.modulate = ThemeColors.PLASMA_CYAN
	tow_btn.pressed.connect(_on_tow_pressed.bind(wreck_id, player_name))
	actions.add_child(tow_btn)

	card.add_child(actions)

	# Item list with loot buttons
	if items.is_empty():
		var empty_items := Label.new()
		empty_items.text = "  (empty)"
		empty_items.add_theme_font_size_override("font_size", 11)
		empty_items.modulate = ThemeColors.TEXT_MUTED
		card.add_child(empty_items)
	else:
		card.add_child(_make_item_header())
		for item in items:
			var item_row := _make_item_row(wreck_id, item)
			card.add_child(item_row)

	# Separator
	var sep := HSeparator.new()
	sep.modulate = ThemeColors.SEPARATOR
	card.add_child(sep)

	return card


func _make_item_header() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)

	var name_lbl := Label.new()
	name_lbl.text = "ITEM"
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.add_theme_font_size_override("font_size", 10)
	name_lbl.modulate = ThemeColors.HULL_GREY
	row.add_child(name_lbl)

	var qty_lbl := Label.new()
	qty_lbl.text = "QTY"
	qty_lbl.custom_minimum_size.x = 40
	qty_lbl.add_theme_font_size_override("font_size", 10)
	qty_lbl.modulate = ThemeColors.HULL_GREY
	row.add_child(qty_lbl)

	var spacer := Label.new()
	spacer.text = ""
	spacer.custom_minimum_size.x = 45
	spacer.add_theme_font_size_override("font_size", 10)
	row.add_child(spacer)

	return row


func _make_item_row(wreck_id: String, item: Dictionary) -> HBoxContainer:
	var item_id: String = item.get("item_id", "")
	var item_name: String = item.get("name", "Unknown")
	var quantity: int = item.get("quantity", 0)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)

	var name_label := Label.new()
	name_label.text = "  %s" % item_name
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.add_theme_font_size_override("font_size", 12)
	row.add_child(name_label)

	var qty_label := Label.new()
	qty_label.text = "x%d" % quantity
	qty_label.custom_minimum_size.x = 40
	qty_label.add_theme_font_size_override("font_size", 12)
	row.add_child(qty_label)

	var loot_btn := Button.new()
	loot_btn.text = "Loot"
	loot_btn.add_theme_font_size_override("font_size", 10)
	loot_btn.custom_minimum_size.x = 45
	loot_btn.modulate = ThemeColors.SHELL_ORANGE
	loot_btn.pressed.connect(_on_loot_pressed.bind(wreck_id, item_id, item_name))
	row.add_child(loot_btn)

	return row


# ---------------------------------------------------------------------------
# Actions
# ---------------------------------------------------------------------------

func _on_loot_pressed(wreck_id: String, item_id: String, item_name: String) -> void:
	status_label.text = "Looting %s..." % item_name
	NetworkManager.send_salvage_command("loot", {"id": wreck_id, "item_id": item_id}, func(content: Dictionary) -> void:
		var looted_name: String = content.get("item_name", item_name)
		var looted_qty: int = content.get("quantity", 1)
		status_label.text = "Looted %dx %s." % [looted_qty, looted_name]
		_fetch_wrecks()
		# Refresh cargo since items moved to ship
		NetworkManager.send_command("get_status", {}, func(_c): pass)
	)


func _on_salvage_pressed(wreck_id: String, owner_name: String) -> void:
	var dialog := AcceptDialog.new()
	dialog.title = "Salvage Wreck"
	dialog.size = Vector2i(300, 100)

	var info := Label.new()
	info.text = "Salvage %s's wreck for raw materials?\nThis will destroy the wreck." % owner_name
	info.add_theme_font_size_override("font_size", 12)
	dialog.add_child(info)

	dialog.confirmed.connect(func():
		dialog.queue_free()
		_execute_salvage(wreck_id, owner_name)
	)
	dialog.canceled.connect(func(): dialog.queue_free())
	add_child(dialog)
	dialog.popup_centered()


func _execute_salvage(wreck_id: String, owner_name: String) -> void:
	status_label.text = "Salvaging %s's wreck..." % owner_name
	NetworkManager.send_salvage_command("scrap", {}, func(content: Dictionary) -> void:
		var materials: Array = content.get("materials", [])
		if materials.is_empty():
			status_label.text = "Salvaged wreck (no materials)."
		else:
			var names := PackedStringArray()
			for mat in materials:
				names.append("%dx %s" % [mat.get("quantity", 1), mat.get("name", "?")])
			status_label.text = "Salvaged: %s" % ", ".join(names)
		_fetch_wrecks()
		NetworkManager.send_command("get_status", {}, func(_c): pass)
	)


func _on_tow_pressed(wreck_id: String, owner_name: String) -> void:
	status_label.text = "Towing %s's wreck..." % owner_name
	NetworkManager.send_salvage_command("tow", {"id": wreck_id}, func(content: Dictionary) -> void:
		var msg: String = content.get("message", "Wreck towed.")
		status_label.text = msg
		_fetch_wrecks()
		NetworkManager.send_command("get_status", {}, func(_c): pass)
	)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

static func format_age(age_ticks: int) -> String:
	var total_seconds: int = age_ticks * 10
	if total_seconds < 60:
		return "%ds ago" % total_seconds
	var minutes: int = total_seconds / 60
	if minutes < 60:
		return "%dm ago" % minutes
	var hours: int = minutes / 60
	return "%dh %dm ago" % [hours, minutes % 60]


static func age_to_minutes(age_ticks: int) -> int:
	return age_ticks * 10 / 60


func _lock_ui() -> void:
	_set_buttons_disabled(true)


func _unlock_ui() -> void:
	_set_buttons_disabled(false)


func _set_buttons_disabled(disabled: bool) -> void:
	for child in wreck_list.get_children():
		if child is VBoxContainer:
			_disable_buttons_recursive(child, disabled)


func _disable_buttons_recursive(node: Node, disabled: bool) -> void:
	for child in node.get_children():
		if child is Button:
			child.disabled = disabled
		elif child is HBoxContainer or child is VBoxContainer:
			_disable_buttons_recursive(child, disabled)
