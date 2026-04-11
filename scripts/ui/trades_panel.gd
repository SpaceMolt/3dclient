extends PanelContainer

## Player-to-player trading panel -- incoming offers, outgoing offers, and
## new trade creation. Only functional when docked (trades require both
## players to be docked at the same POI).

@onready var tab_container: TabContainer = %TradeTabs
@onready var status_label: Label = %TradeStatus
@onready var incoming_list: VBoxContainer = %IncomingList
@onready var outgoing_list: VBoxContainer = %OutgoingList

var _incoming: Array = []
var _outgoing: Array = []


func _ready() -> void:
	NetworkManager.request_started.connect(_lock_ui)
	NetworkManager.request_completed.connect(_unlock_ui)
	tab_container.tab_changed.connect(_on_tab_changed)
	_fetch_trades()


func _on_tab_changed(tab: int) -> void:
	match tab:
		0: _refresh_incoming()
		1: _refresh_outgoing()


# ---------------------------------------------------------------------------
# Fetch trades from server
# ---------------------------------------------------------------------------

func _fetch_trades() -> void:
	status_label.text = "Loading trades..."
	NetworkManager.send_transfer_command("get_trades", {}, func(content: Dictionary) -> void:
		_incoming = content.get("incoming", [])
		_outgoing = content.get("outgoing", [])
		_refresh_incoming()
		_refresh_outgoing()
		var total := _incoming.size() + _outgoing.size()
		status_label.text = "%d trade%s" % [total, "" if total == 1 else "s"]
	)


# ---------------------------------------------------------------------------
# Incoming tab
# ---------------------------------------------------------------------------

func _refresh_incoming() -> void:
	for child in incoming_list.get_children():
		child.queue_free()

	if _incoming.is_empty():
		var empty := Label.new()
		empty.text = "No incoming trade offers."
		empty.add_theme_font_size_override("font_size", 12)
		empty.modulate = ThemeColors.TEXT_MUTED
		incoming_list.add_child(empty)
		return

	for trade in _incoming:
		var card := _build_trade_card(trade, true)
		incoming_list.add_child(card)


# ---------------------------------------------------------------------------
# Outgoing tab
# ---------------------------------------------------------------------------

func _refresh_outgoing() -> void:
	for child in outgoing_list.get_children():
		child.queue_free()

	if _outgoing.is_empty():
		var empty := Label.new()
		empty.text = "No outgoing trade offers."
		empty.add_theme_font_size_override("font_size", 12)
		empty.modulate = ThemeColors.TEXT_MUTED
		outgoing_list.add_child(empty)
		return

	for trade in _outgoing:
		var card := _build_trade_card(trade, false)
		outgoing_list.add_child(card)


# ---------------------------------------------------------------------------
# Trade card builder
# ---------------------------------------------------------------------------

func _build_trade_card(trade: Dictionary, is_incoming: bool) -> VBoxContainer:
	var card := VBoxContainer.new()
	card.add_theme_constant_override("separation", 2)

	# Separator bar above each card
	var sep := HSeparator.new()
	sep.modulate = ThemeColors.SEPARATOR
	card.add_child(sep)

	# Player name row
	var player_row := HBoxContainer.new()
	player_row.add_theme_constant_override("separation", 4)

	var direction_label := Label.new()
	if is_incoming:
		direction_label.text = "FROM:"
		direction_label.modulate = ThemeColors.PLASMA_CYAN
	else:
		direction_label.text = "TO:"
		direction_label.modulate = ThemeColors.HULL_GREY
	direction_label.add_theme_font_size_override("font_size", 10)
	direction_label.custom_minimum_size.x = 36
	player_row.add_child(direction_label)

	var player_name := Label.new()
	if is_incoming:
		player_name.text = trade.get("offerer_name", "Unknown")
	else:
		player_name.text = trade.get("target_name", "Unknown")
	player_name.add_theme_font_size_override("font_size", 12)
	player_name.modulate = ThemeColors.STAR_WHITE
	player_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	player_row.add_child(player_name)
	card.add_child(player_row)

	# Offering section
	var offer_items: Array = trade.get("offer_items", [])
	var offer_credits: int = trade.get("offer_credits", 0)
	if not offer_items.is_empty() or offer_credits > 0:
		var offer_header := Label.new()
		offer_header.text = "OFFERING"
		offer_header.add_theme_font_size_override("font_size", 10)
		offer_header.modulate = ThemeColors.HULL_GREY
		card.add_child(offer_header)
		_add_item_rows(card, offer_items, offer_credits)

	# Requesting section
	var request_items: Array = trade.get("request_items", [])
	var request_credits: int = trade.get("request_credits", 0)
	if not request_items.is_empty() or request_credits > 0:
		var request_header := Label.new()
		request_header.text = "REQUESTING"
		request_header.add_theme_font_size_override("font_size", 10)
		request_header.modulate = ThemeColors.HULL_GREY
		card.add_child(request_header)
		_add_item_rows(card, request_items, request_credits)

	# Action buttons
	var trade_id: String = trade.get("trade_id", "")
	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 4)

	if is_incoming:
		var accept_btn := Button.new()
		accept_btn.text = "Accept"
		accept_btn.add_theme_font_size_override("font_size", 10)
		accept_btn.custom_minimum_size.x = 55
		accept_btn.modulate = ThemeColors.BIO_GREEN
		accept_btn.pressed.connect(_on_accept_pressed.bind(trade_id))
		btn_row.add_child(accept_btn)

		var decline_btn := Button.new()
		decline_btn.text = "Decline"
		decline_btn.add_theme_font_size_override("font_size", 10)
		decline_btn.custom_minimum_size.x = 55
		decline_btn.modulate = ThemeColors.CLAW_RED
		decline_btn.pressed.connect(_on_decline_pressed.bind(trade_id))
		btn_row.add_child(decline_btn)
	else:
		var cancel_btn := Button.new()
		cancel_btn.text = "Cancel"
		cancel_btn.add_theme_font_size_override("font_size", 10)
		cancel_btn.custom_minimum_size.x = 55
		cancel_btn.modulate = ThemeColors.CLAW_RED
		cancel_btn.pressed.connect(_on_cancel_pressed.bind(trade_id))
		btn_row.add_child(cancel_btn)

	card.add_child(btn_row)
	return card


func _add_item_rows(container: VBoxContainer, items: Array, credits: int) -> void:
	for item in items:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)

		var item_label := Label.new()
		item_label.text = "  %s" % item.get("item_id", "Unknown")
		item_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		item_label.add_theme_font_size_override("font_size", 12)
		row.add_child(item_label)

		var qty_label := Label.new()
		qty_label.text = "x%d" % item.get("quantity", 0)
		qty_label.custom_minimum_size.x = 40
		qty_label.add_theme_font_size_override("font_size", 12)
		qty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(qty_label)

		container.add_child(row)

	if credits > 0:
		var credits_row := HBoxContainer.new()
		credits_row.add_theme_constant_override("separation", 4)

		var credits_label := Label.new()
		credits_label.text = "  Credits"
		credits_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		credits_label.add_theme_font_size_override("font_size", 12)
		credits_row.add_child(credits_label)

		var amount_label := Label.new()
		amount_label.text = "%d" % credits
		amount_label.custom_minimum_size.x = 55
		amount_label.add_theme_font_size_override("font_size", 12)
		amount_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		amount_label.modulate = ThemeColors.WARNING_YELLOW
		credits_row.add_child(amount_label)

		container.add_child(credits_row)


# ---------------------------------------------------------------------------
# Trade actions
# ---------------------------------------------------------------------------

func _on_accept_pressed(trade_id: String) -> void:
	status_label.text = "Accepting trade..."
	NetworkManager.send_transfer_command("trade_accept", {"trade_id": trade_id}, func(_content: Dictionary) -> void:
		status_label.text = "Trade accepted."
		_fetch_trades()
		NetworkManager.send_command("get_status", {}, func(_c): pass)
	)


func _on_decline_pressed(trade_id: String) -> void:
	status_label.text = "Declining trade..."
	NetworkManager.send_transfer_command("trade_decline", {"trade_id": trade_id}, func(_content: Dictionary) -> void:
		status_label.text = "Trade declined."
		_fetch_trades()
	)


func _on_cancel_pressed(trade_id: String) -> void:
	status_label.text = "Canceling trade..."
	NetworkManager.send_transfer_command("trade_cancel", {"trade_id": trade_id}, func(_content: Dictionary) -> void:
		status_label.text = "Trade canceled."
		_fetch_trades()
		NetworkManager.send_command("get_status", {}, func(_c): pass)
	)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

## Format a trade for use in tests and data processing. Returns
## a summary dictionary with normalized field names.
static func summarize_trade(trade: Dictionary, is_incoming: bool) -> Dictionary:
	var player_name: String
	if is_incoming:
		player_name = trade.get("offerer_name", "Unknown")
	else:
		player_name = trade.get("target_name", "Unknown")

	var offer_items: Array = trade.get("offer_items", [])
	var offer_credits: int = trade.get("offer_credits", 0)
	var request_items: Array = trade.get("request_items", [])
	var request_credits: int = trade.get("request_credits", 0)

	var total_items := offer_items.size() + request_items.size()
	var total_credits := offer_credits + request_credits

	return {
		"player": player_name,
		"direction": "incoming" if is_incoming else "outgoing",
		"offer_item_count": offer_items.size(),
		"request_item_count": request_items.size(),
		"total_items": total_items,
		"offer_credits": offer_credits,
		"request_credits": request_credits,
		"total_credits": total_credits,
		"trade_id": trade.get("trade_id", ""),
	}


func _lock_ui() -> void:
	_set_buttons_disabled(true)


func _unlock_ui() -> void:
	_set_buttons_disabled(false)


func _set_buttons_disabled(disabled: bool) -> void:
	for container in [incoming_list, outgoing_list]:
		if not container:
			continue
		for child in container.get_children():
			if child is VBoxContainer:
				for node in child.get_children():
					if node is HBoxContainer:
						for btn in node.get_children():
							if btn is Button:
								btn.disabled = disabled
			elif child is HBoxContainer:
				for btn in child.get_children():
					if btn is Button:
						btn.disabled = disabled
