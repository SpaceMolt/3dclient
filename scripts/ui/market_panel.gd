extends PanelContainer

## Full market panel with order book, buy/sell order creation, and active orders.
## Replaces the simple trade_panel when docked at a station.

@onready var tab_container: TabContainer = %MarketTabs
@onready var status_label: Label = %MarketStatus

# Browse tab
@onready var browse_list: VBoxContainer = %BrowseList
@onready var category_filter: OptionButton = %CategoryFilter
@onready var search_field: LineEdit = %SearchField

# Orders tab
@onready var orders_list: VBoxContainer = %OrdersList

# Cargo tab
@onready var cargo_list: VBoxContainer = %CargoList

var _market_items: Array = []
var _categories: Array = []
var _my_orders: Array = []
var _selected_filter: String = ""


func _ready() -> void:
	NetworkManager.request_started.connect(_lock_ui)
	NetworkManager.request_completed.connect(_unlock_ui)
	StateManager.cargo_changed.connect(_refresh_cargo)

	category_filter.item_selected.connect(_on_category_selected)
	search_field.text_changed.connect(_on_search_changed)
	tab_container.tab_changed.connect(_on_tab_changed)

	_fetch_market()
	_refresh_cargo()


func _on_tab_changed(tab: int) -> void:
	match tab:
		0: _refresh_browse()
		1: _fetch_orders()
		2: _refresh_cargo()


# --- Browse tab ---

func _fetch_market() -> void:
	status_label.text = "Loading market..."
	NetworkManager.send_market_command("view_market", {}, func(content: Dictionary) -> void:
		_market_items = content.get("items", [])
		_categories = content.get("categories", [])
		_setup_category_filter()
		_refresh_browse()
		status_label.text = "%d items" % _market_items.size()
	)


func _setup_category_filter() -> void:
	category_filter.clear()
	category_filter.add_item("All Categories")
	for cat in _categories:
		category_filter.add_item(cat)


func _on_category_selected(idx: int) -> void:
	_selected_filter = "" if idx == 0 else category_filter.get_item_text(idx)
	_refresh_browse()


func _on_search_changed(text: String) -> void:
	_refresh_browse()


func _refresh_browse() -> void:
	for child in browse_list.get_children():
		child.queue_free()

	var search_text: String = search_field.text.to_lower() if search_field else ""

	# Header
	var header := _make_row("ITEM", "BUY", "SELL", "QTY", "", true)
	browse_list.add_child(header)

	var count := 0
	for item in _market_items:
		var iname: String = item.get("item_name", item.get("name", "Unknown"))
		var category: String = item.get("category", "")

		# Category filter
		if not _selected_filter.is_empty() and category != _selected_filter:
			continue

		# Search filter
		if not search_text.is_empty() and iname.to_lower().find(search_text) == -1:
			continue

		var buy_price: int = item.get("buy_price", 0)
		var sell_price: int = item.get("sell_price", 0)
		var qty: int = item.get("buy_quantity", item.get("quantity_available", 0))
		var item_id: String = item.get("item_id", "")

		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)

		# Name (with category hint)
		var name_label := Label.new()
		name_label.text = iname
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.add_theme_font_size_override("font_size", 12)
		name_label.tooltip_text = category
		row.add_child(name_label)

		# Buy price
		var buy_label := Label.new()
		buy_label.text = "¢%d" % buy_price if buy_price > 0 else "—"
		buy_label.custom_minimum_size.x = 55
		buy_label.add_theme_font_size_override("font_size", 12)
		buy_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(buy_label)

		# Sell price
		var sell_label := Label.new()
		sell_label.text = "¢%d" % sell_price if sell_price > 0 else "—"
		sell_label.custom_minimum_size.x = 55
		sell_label.add_theme_font_size_override("font_size", 12)
		sell_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(sell_label)

		# Quantity
		var qty_label := Label.new()
		qty_label.text = str(qty) if qty > 0 else "—"
		qty_label.custom_minimum_size.x = 35
		qty_label.add_theme_font_size_override("font_size", 12)
		qty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(qty_label)

		# Buy button
		var buy_btn := Button.new()
		buy_btn.text = "Buy"
		buy_btn.add_theme_font_size_override("font_size", 10)
		buy_btn.custom_minimum_size.x = 40
		buy_btn.pressed.connect(_on_buy_pressed.bind(item_id, iname, buy_price))
		buy_btn.disabled = buy_price <= 0
		row.add_child(buy_btn)

		browse_list.add_child(row)
		count += 1

	if count == 0:
		var empty := Label.new()
		empty.text = "No items match filter."
		empty.add_theme_font_size_override("font_size", 12)
		empty.modulate = ThemeColors.TEXT_MUTED
		browse_list.add_child(empty)


func _on_buy_pressed(item_id: String, item_name: String, price: int) -> void:
	# Show a quantity dialog
	_show_order_dialog("Buy", item_id, item_name, price, true)


# --- Orders tab ---

func _fetch_orders() -> void:
	status_label.text = "Loading orders..."
	NetworkManager.send_market_command("view_orders", {}, func(content: Dictionary) -> void:
		_my_orders = content.get("orders", [])
		_refresh_orders()
		status_label.text = "%d orders" % _my_orders.size()
	)


func _refresh_orders() -> void:
	for child in orders_list.get_children():
		child.queue_free()

	if _my_orders.is_empty():
		var empty := Label.new()
		empty.text = "No active orders."
		empty.add_theme_font_size_override("font_size", 12)
		empty.modulate = ThemeColors.TEXT_MUTED
		orders_list.add_child(empty)
		return

	# Header
	var header := _make_row("ITEM", "TYPE", "QTY", "PRICE", "", true)
	orders_list.add_child(header)

	for order in _my_orders:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)

		var name_label := Label.new()
		name_label.text = order.get("item_name", order.get("item", "Unknown"))
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.add_theme_font_size_override("font_size", 12)
		row.add_child(name_label)

		var type_label := Label.new()
		var order_type: String = order.get("type", order.get("order_type", "?"))
		type_label.text = order_type.to_upper()
		type_label.custom_minimum_size.x = 40
		type_label.add_theme_font_size_override("font_size", 11)
		type_label.modulate = ThemeColors.BUY_ORDER if order_type == "buy" else ThemeColors.SELL_ORDER
		row.add_child(type_label)

		var qty_label := Label.new()
		qty_label.text = str(order.get("quantity", 0))
		qty_label.custom_minimum_size.x = 35
		qty_label.add_theme_font_size_override("font_size", 12)
		qty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(qty_label)

		var price_label := Label.new()
		price_label.text = "¢%d" % order.get("price_each", 0)
		price_label.custom_minimum_size.x = 55
		price_label.add_theme_font_size_override("font_size", 12)
		price_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(price_label)

		var cancel_btn := Button.new()
		cancel_btn.text = "X"
		cancel_btn.add_theme_font_size_override("font_size", 10)
		cancel_btn.custom_minimum_size.x = 30
		var order_id: String = order.get("order_id", "")
		cancel_btn.pressed.connect(func():
			_cancel_order(order_id)
		)
		row.add_child(cancel_btn)

		orders_list.add_child(row)


func _cancel_order(order_id: String) -> void:
	status_label.text = "Canceling order..."
	NetworkManager.send_market_command("cancel_order", {"order_id": order_id}, func(content: Dictionary) -> void:
		status_label.text = "Order canceled."
		_fetch_orders()
		# Refresh state since credits/cargo may have changed
		NetworkManager.send_command("get_status", {})
	)


# --- Cargo tab ---

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

	var header := _make_row("ITEM", "QTY", "SIZE", "", "", true)
	cargo_list.add_child(header)

	for item in StateManager.cargo:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)

		var iname: String = item.get("item_name", item.get("name", "Unknown"))
		var name_label := Label.new()
		name_label.text = iname
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.add_theme_font_size_override("font_size", 12)
		row.add_child(name_label)

		var qty_label := Label.new()
		qty_label.text = "x%d" % item.get("quantity", 0)
		qty_label.custom_minimum_size.x = 40
		qty_label.add_theme_font_size_override("font_size", 12)
		row.add_child(qty_label)

		var size_label := Label.new()
		size_label.text = "%d" % item.get("size", 0)
		size_label.custom_minimum_size.x = 30
		size_label.add_theme_font_size_override("font_size", 12)
		size_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(size_label)

		# Sell button
		var item_id: String = item.get("item_id", item.get("id", ""))
		var qty: int = item.get("quantity", 1)

		var sell_btn := Button.new()
		sell_btn.text = "Sell"
		sell_btn.add_theme_font_size_override("font_size", 10)
		sell_btn.custom_minimum_size.x = 40
		sell_btn.pressed.connect(_on_sell_pressed.bind(item_id, iname, qty))
		row.add_child(sell_btn)

		# Store button (deposit to station storage)
		var store_btn := Button.new()
		store_btn.text = "Store"
		store_btn.add_theme_font_size_override("font_size", 10)
		store_btn.custom_minimum_size.x = 45
		store_btn.pressed.connect(_on_deposit_pressed.bind(item_id, iname, qty))
		row.add_child(store_btn)

		cargo_list.add_child(row)


func _on_sell_pressed(item_id: String, item_name: String, max_qty: int) -> void:
	_show_order_dialog("Sell", item_id, item_name, 0, false, max_qty)


func _on_deposit_pressed(item_id: String, item_name: String, max_qty: int) -> void:
	if max_qty == 1:
		_deposit_item(item_id, item_name, 1)
		return
	_show_deposit_dialog(item_id, item_name, max_qty)


func _show_deposit_dialog(item_id: String, item_name: String, max_qty: int) -> void:
	var dialog := AcceptDialog.new()
	dialog.title = "Deposit: %s" % item_name
	dialog.size = Vector2i(280, 120)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	var qty_row := HBoxContainer.new()
	qty_row.add_theme_constant_override("separation", 8)
	var qty_lbl := Label.new()
	qty_lbl.text = "Quantity:"
	qty_lbl.custom_minimum_size.x = 70
	qty_row.add_child(qty_lbl)
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
		_deposit_item(item_id, item_name, int(spin.value))
		dialog.queue_free()
	)
	dialog.canceled.connect(func(): dialog.queue_free())
	add_child(dialog)
	dialog.popup_centered()


func _deposit_item(item_id: String, item_name: String, quantity: int) -> void:
	status_label.text = "Storing %s..." % item_name
	NetworkManager.send_storage_command("deposit", {"item_id": item_id, "quantity": quantity}, func(content: Dictionary) -> void:
		var stored: int = content.get("quantity", quantity)
		status_label.text = "Stored %dx %s." % [stored, item_name]
		# Refresh cargo state since items left the ship
		NetworkManager.send_command("get_status", {}, func(_c): pass)
	)


# --- Order dialog ---

func _show_order_dialog(order_type: String, item_id: String, item_name: String, suggested_price: int, is_buy: bool, max_qty: int = 99) -> void:
	# Create a simple popup for quantity and price
	var dialog := AcceptDialog.new()
	dialog.title = "%s: %s" % [order_type, item_name]
	dialog.size = Vector2i(320, 180)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)

	# Quantity
	var qty_row := HBoxContainer.new()
	var qty_lbl := Label.new()
	qty_lbl.text = "Quantity:"
	qty_lbl.custom_minimum_size.x = 70
	qty_row.add_child(qty_lbl)
	var qty_spin := SpinBox.new()
	qty_spin.min_value = 1
	qty_spin.max_value = max_qty
	qty_spin.value = 1
	qty_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	qty_row.add_child(qty_spin)
	vbox.add_child(qty_row)

	# Price
	var price_row := HBoxContainer.new()
	var price_lbl := Label.new()
	price_lbl.text = "Price ea:"
	price_lbl.custom_minimum_size.x = 70
	price_row.add_child(price_lbl)
	var price_spin := SpinBox.new()
	price_spin.min_value = 1
	price_spin.max_value = 999999
	price_spin.value = suggested_price if suggested_price > 0 else 1
	price_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	price_row.add_child(price_spin)
	vbox.add_child(price_row)

	# Total preview
	var total_label := Label.new()
	total_label.text = "Total: ¢%d" % (int(qty_spin.value) * int(price_spin.value))
	total_label.add_theme_font_size_override("font_size", 13)
	vbox.add_child(total_label)

	var _update_total := func(_v = 0.0):
		total_label.text = "Total: ¢%d" % (int(qty_spin.value) * int(price_spin.value))
	qty_spin.value_changed.connect(_update_total)
	price_spin.value_changed.connect(_update_total)

	dialog.add_child(vbox)

	dialog.confirmed.connect(func():
		var qty := int(qty_spin.value)
		var price := int(price_spin.value)
		if is_buy:
			_create_buy_order(item_id, item_name, qty, price)
		else:
			_create_sell_order(item_id, item_name, qty, price)
		dialog.queue_free()
	)
	dialog.canceled.connect(func(): dialog.queue_free())

	add_child(dialog)
	dialog.popup_centered()


func _create_buy_order(item_id: String, item_name: String, quantity: int, price_each: int) -> void:
	status_label.text = "Creating buy order..."
	NetworkManager.send_market_command("create_buy_order",
		{"item_id": item_id, "quantity": quantity, "price_each": price_each},
		func(content: Dictionary) -> void:
			var filled: int = content.get("quantity_filled", 0)
			var listed: int = content.get("quantity_listed", quantity - filled)
			if filled > 0:
				status_label.text = "Bought %d %s (listed %d more)" % [filled, item_name, listed]
			else:
				status_label.text = "Buy order placed for %d %s @ ¢%d" % [quantity, item_name, price_each]
			NetworkManager.send_command("get_status", {})
			_fetch_market()
	)


func _create_sell_order(item_id: String, item_name: String, quantity: int, price_each: int) -> void:
	status_label.text = "Creating sell order..."
	NetworkManager.send_market_command("create_sell_order",
		{"item_id": item_id, "quantity": quantity, "price_each": price_each},
		func(content: Dictionary) -> void:
			var filled: int = content.get("quantity_filled", 0)
			var earned: int = content.get("total_earned", 0)
			if filled > 0:
				status_label.text = "Sold %d %s for ¢%d" % [filled, item_name, earned]
			else:
				status_label.text = "Sell order placed for %d %s @ ¢%d" % [quantity, item_name, price_each]
			NetworkManager.send_command("get_status", {})
			_fetch_market()
	)


# --- Helpers ---

func _make_row(col1: String, col2: String, col3: String, col4: String, col5: String, is_header: bool = false) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	var font_size := 10 if is_header else 12
	var color := ThemeColors.HULL_GREY if is_header else ThemeColors.TEXT_PRIMARY

	var l1 := Label.new()
	l1.text = col1
	l1.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l1.add_theme_font_size_override("font_size", font_size)
	l1.modulate = color
	row.add_child(l1)

	for col_text in [col2, col3, col4]:
		if col_text.is_empty():
			continue
		var lbl := Label.new()
		lbl.text = col_text
		lbl.custom_minimum_size.x = 55
		lbl.add_theme_font_size_override("font_size", font_size)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		lbl.modulate = color
		row.add_child(lbl)

	return row


func _lock_ui() -> void:
	_set_buttons_disabled(true)


func _unlock_ui() -> void:
	_set_buttons_disabled(false)


func _set_buttons_disabled(disabled: bool) -> void:
	for container in [browse_list, orders_list, cargo_list]:
		if not container:
			continue
		for child in container.get_children():
			if child is HBoxContainer:
				for btn in child.get_children():
					if btn is Button:
						btn.disabled = disabled
