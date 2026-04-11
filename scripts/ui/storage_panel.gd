extends PanelContainer

## Station storage panel — two tabs: Vault (stored items) and Cargo (ship hold).
## Vault items can be withdrawn; cargo items can be deposited. Both support
## partial quantities via a spinner dialog.

@onready var tab_container: TabContainer = %StorageTabs
@onready var storage_list: VBoxContainer = %StorageList
@onready var cargo_list: VBoxContainer = %CargoList
@onready var status_label: Label = %StorageStatus

var _storage_items: Array = []
var _vault_credits: int = 0


func _ready() -> void:
	NetworkManager.request_started.connect(func(): _set_buttons_disabled(true))
	NetworkManager.request_completed.connect(func(): _set_buttons_disabled(false))
	StateManager.cargo_changed.connect(_refresh_cargo)
	tab_container.tab_changed.connect(_on_tab_changed)
	_fetch_storage()
	_refresh_cargo()


func _on_tab_changed(tab: int) -> void:
	match tab:
		0: _refresh_storage()
		1: _refresh_cargo()


# ---------------------------------------------------------------------------
# Vault tab
# ---------------------------------------------------------------------------

func _fetch_storage() -> void:
	status_label.text = "Loading..."
	NetworkManager.send_storage_command("view", {}, func(content: Dictionary) -> void:
		_storage_items = content.get("items", [])
		_vault_credits = content.get("credits", 0)
		_refresh_storage()
		status_label.text = "%d items  ¢%d vault" % [_storage_items.size(), _vault_credits]
	)


func _refresh_storage() -> void:
	for child in storage_list.get_children():
		child.queue_free()

	if _storage_items.is_empty():
		var empty := Label.new()
		empty.text = "Storage empty."
		empty.add_theme_font_size_override("font_size", 12)
		empty.modulate = ThemeColors.TEXT_MUTED
		storage_list.add_child(empty)
		return

	# Header row
	storage_list.add_child(_make_header(["ITEM", "QTY", ""]))

	for item in _storage_items:
		var iname: String = item.get("item_name", item.get("name", "Unknown"))
		var item_id: String = item.get("item_id", item.get("id", ""))
		var qty: int = item.get("quantity", 0)

		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)

		var name_lbl := Label.new()
		name_lbl.text = iname
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_lbl.add_theme_font_size_override("font_size", 12)
		row.add_child(name_lbl)

		var qty_lbl := Label.new()
		qty_lbl.text = "x%d" % qty
		qty_lbl.custom_minimum_size.x = 40
		qty_lbl.add_theme_font_size_override("font_size", 12)
		row.add_child(qty_lbl)

		var btn := Button.new()
		btn.text = "Take"
		btn.add_theme_font_size_override("font_size", 10)
		btn.custom_minimum_size.x = 50
		btn.pressed.connect(_on_withdraw_pressed.bind(item_id, iname, qty))
		row.add_child(btn)

		storage_list.add_child(row)


func _on_withdraw_pressed(item_id: String, item_name: String, max_qty: int) -> void:
	if max_qty == 1:
		_withdraw(item_id, item_name, 1)
		return
	_show_quantity_dialog("Withdraw", item_name, max_qty, func(qty: int):
		_withdraw(item_id, item_name, qty)
	)


func _withdraw(item_id: String, item_name: String, quantity: int) -> void:
	status_label.text = "Withdrawing %s..." % item_name
	NetworkManager.send_storage_command("withdraw", {"item_id": item_id, "quantity": quantity}, func(content: Dictionary) -> void:
		var taken: int = content.get("quantity", quantity)
		status_label.text = "Withdrew %dx %s." % [taken, item_name]
		_fetch_storage()
		# Update cargo since items moved to ship
		NetworkManager.send_command("get_status", {}, func(_c): pass)
	)


# ---------------------------------------------------------------------------
# Cargo tab (ship hold — deposit items into storage)
# ---------------------------------------------------------------------------

func _refresh_cargo() -> void:
	for child in cargo_list.get_children():
		child.queue_free()

	if StateManager.cargo.is_empty():
		var empty := Label.new()
		empty.text = "Cargo hold empty."
		empty.add_theme_font_size_override("font_size", 12)
		empty.modulate = ThemeColors.TEXT_MUTED
		cargo_list.add_child(empty)
		return

	var is_docked := StateManager.is_docked()
	cargo_list.add_child(_make_header(["ITEM", "QTY", "", ""]))

	for item in StateManager.cargo:
		var iname: String = item.get("item_name", item.get("name", "Unknown"))
		var item_id: String = item.get("item_id", item.get("id", ""))
		var qty: int = item.get("quantity", 0)

		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)

		var name_lbl := Label.new()
		name_lbl.text = iname
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_lbl.add_theme_font_size_override("font_size", 12)
		row.add_child(name_lbl)

		var qty_lbl := Label.new()
		qty_lbl.text = "x%d" % qty
		qty_lbl.custom_minimum_size.x = 40
		qty_lbl.add_theme_font_size_override("font_size", 12)
		row.add_child(qty_lbl)

		if is_docked:
			var store_btn := Button.new()
			store_btn.text = "Store"
			store_btn.add_theme_font_size_override("font_size", 10)
			store_btn.custom_minimum_size.x = 50
			store_btn.pressed.connect(_on_deposit_pressed.bind(item_id, iname, qty))
			row.add_child(store_btn)

		var dump_btn := Button.new()
		dump_btn.text = "Dump"
		dump_btn.add_theme_font_size_override("font_size", 10)
		dump_btn.custom_minimum_size.x = 50
		dump_btn.modulate = ThemeColors.CLAW_RED
		dump_btn.pressed.connect(_on_jettison_pressed.bind(item_id, iname, qty))
		row.add_child(dump_btn)

		cargo_list.add_child(row)


func _on_deposit_pressed(item_id: String, item_name: String, max_qty: int) -> void:
	if max_qty == 1:
		_deposit(item_id, item_name, 1)
		return
	_show_quantity_dialog("Deposit", item_name, max_qty, func(qty: int):
		_deposit(item_id, item_name, qty)
	)


func _deposit(item_id: String, item_name: String, quantity: int) -> void:
	status_label.text = "Storing %s..." % item_name
	NetworkManager.send_storage_command("deposit", {"item_id": item_id, "quantity": quantity}, func(content: Dictionary) -> void:
		var stored: int = content.get("quantity", quantity)
		status_label.text = "Stored %dx %s." % [stored, item_name]
		_fetch_storage()
		# Update cargo since items moved from ship
		NetworkManager.send_command("get_status", {}, func(_c): pass)
	)


# ---------------------------------------------------------------------------
# Jettison (dump cargo into space)
# ---------------------------------------------------------------------------

func _on_jettison_pressed(item_id: String, item_name: String, max_qty: int) -> void:
	if max_qty == 1:
		_jettison(item_id, item_name, 1)
		return
	_show_quantity_dialog("Jettison", item_name, max_qty, func(qty: int):
		_jettison(item_id, item_name, qty)
	)


func _jettison(item_id: String, item_name: String, quantity: int) -> void:
	status_label.text = "Jettisoning %s..." % item_name
	NetworkManager.send_command("jettison", {"item_id": item_id, "quantity": quantity}, func(content: Dictionary) -> void:
		var dumped: int = content.get("quantity", quantity)
		status_label.text = "Jettisoned %dx %s." % [dumped, item_name]
		# State refresh happens automatically via send_command
	)


# ---------------------------------------------------------------------------
# Quantity dialog
# ---------------------------------------------------------------------------

func _show_quantity_dialog(action: String, item_name: String, max_qty: int, on_confirm: Callable) -> void:
	var dialog := AcceptDialog.new()
	dialog.title = "%s: %s" % [action, item_name]
	dialog.size = Vector2i(280, 120)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)

	var qty_row := HBoxContainer.new()
	qty_row.add_theme_constant_override("separation", 8)

	var qty_label := Label.new()
	qty_label.text = "Quantity:"
	qty_label.custom_minimum_size.x = 70
	qty_row.add_child(qty_label)

	var spin := SpinBox.new()
	spin.min_value = 1
	spin.max_value = max_qty
	spin.value = max_qty
	spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	qty_row.add_child(spin)

	var all_btn := Button.new()
	all_btn.text = "All"
	all_btn.add_theme_font_size_override("font_size", 10)
	all_btn.pressed.connect(func(): spin.value = max_qty)
	qty_row.add_child(all_btn)

	vbox.add_child(qty_row)

	var hint := Label.new()
	hint.text = "Available: %d" % max_qty
	hint.add_theme_font_size_override("font_size", 11)
	hint.modulate = ThemeColors.TEXT_MUTED
	vbox.add_child(hint)

	dialog.add_child(vbox)

	dialog.confirmed.connect(func():
		on_confirm.call(int(spin.value))
		dialog.queue_free()
	)
	dialog.canceled.connect(func(): dialog.queue_free())

	add_child(dialog)
	dialog.popup_centered()


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
			lbl.custom_minimum_size.x = 40
		row.add_child(lbl)
	return row


func _set_buttons_disabled(disabled: bool) -> void:
	for container in [storage_list, cargo_list]:
		if not container:
			continue
		for child in container.get_children():
			if child is HBoxContainer:
				for node in child.get_children():
					if node is Button:
						node.disabled = disabled
