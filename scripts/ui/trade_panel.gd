extends PanelContainer

@onready var market_list: VBoxContainer = %MarketList
@onready var cargo_list: VBoxContainer = %CargoList
@onready var status_label: Label = %TradeStatus

var _market_items: Array = []


func _ready() -> void:
	NetworkManager.request_started.connect(_lock_ui)
	NetworkManager.request_completed.connect(_unlock_ui)
	StateManager.state_updated.connect(_refresh_cargo)

	_refresh_cargo()
	_fetch_market()


func _fetch_market() -> void:
	status_label.text = "Loading market..."
	NetworkManager.send_market_command("list", {}, func(content: Dictionary) -> void:
		_market_items = content.get("items", [])
		_refresh_market()
		status_label.text = ""
	)


func _refresh_market() -> void:
	for child in market_list.get_children():
		child.queue_free()

	if _market_items.is_empty():
		var empty_label := Label.new()
		empty_label.text = "No items available."
		empty_label.add_theme_font_size_override("font_size", 12)
		empty_label.modulate = Color(0.5, 0.5, 0.5)
		market_list.add_child(empty_label)
		return

	for item in _market_items:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)

		var name_label := Label.new()
		name_label.text = item.get("name", "Unknown")
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.add_theme_font_size_override("font_size", 12)
		row.add_child(name_label)

		var price_label := Label.new()
		price_label.text = "¢%d" % item.get("price", 0)
		price_label.add_theme_font_size_override("font_size", 12)
		row.add_child(price_label)

		var buy_btn := Button.new()
		buy_btn.text = "Buy"
		buy_btn.add_theme_font_size_override("font_size", 11)
		var item_id: String = item.get("id", "")
		buy_btn.pressed.connect(func(): _buy_item(item_id, item.get("name", "?")))
		row.add_child(buy_btn)

		market_list.add_child(row)


func _refresh_cargo() -> void:
	for child in cargo_list.get_children():
		child.queue_free()

	if StateManager.cargo.is_empty():
		var empty_label := Label.new()
		empty_label.text = "Cargo hold empty."
		empty_label.add_theme_font_size_override("font_size", 12)
		empty_label.modulate = Color(0.5, 0.5, 0.5)
		cargo_list.add_child(empty_label)
		return

	for item in StateManager.cargo:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)

		var name_label := Label.new()
		name_label.text = "%s x%d" % [item.get("name", "Unknown"), item.get("quantity", 0)]
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.add_theme_font_size_override("font_size", 12)
		row.add_child(name_label)

		var value_label := Label.new()
		value_label.text = "¢%d" % item.get("value", 0)
		value_label.add_theme_font_size_override("font_size", 12)
		row.add_child(value_label)

		var sell_btn := Button.new()
		sell_btn.text = "Sell"
		sell_btn.add_theme_font_size_override("font_size", 11)
		var item_id: String = item.get("id", "")
		var qty: int = item.get("quantity", 1)
		sell_btn.pressed.connect(func(): _sell_item(item_id, item.get("name", "?"), qty))
		row.add_child(sell_btn)

		cargo_list.add_child(row)


func _buy_item(item_id: String, item_name: String) -> void:
	status_label.text = "Buying %s..." % item_name
	NetworkManager.send_market_command("buy", {"id": item_id, "quantity": 1}, func(content: Dictionary) -> void:
		status_label.text = "Bought %s." % item_name
		_refresh_state_after_trade()
	)


func _sell_item(item_id: String, item_name: String, quantity: int) -> void:
	status_label.text = "Selling %s..." % item_name
	NetworkManager.send_market_command("sell", {"id": item_id, "quantity": quantity}, func(content: Dictionary) -> void:
		status_label.text = "Sold %s." % item_name
		_refresh_state_after_trade()
	)


func _refresh_state_after_trade() -> void:
	# Refresh full game state so cargo/credits update in HUD
	NetworkManager.send_command("get_status", {}, func(_content: Dictionary) -> void:
		_fetch_market()
	)


func _lock_ui() -> void:
	_set_buttons_disabled(true)


func _unlock_ui() -> void:
	_set_buttons_disabled(false)


func _set_buttons_disabled(disabled: bool) -> void:
	for child in market_list.get_children():
		if child is HBoxContainer:
			for btn in child.get_children():
				if btn is Button:
					btn.disabled = disabled
	for child in cargo_list.get_children():
		if child is HBoxContainer:
			for btn in child.get_children():
				if btn is Button:
					btn.disabled = disabled
