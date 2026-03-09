extends PanelContainer

## Chat panel — send/receive messages. Shows local and system chat.

@onready var chat_log: RichTextLabel = %ChatLog
@onready var chat_input: LineEdit = %ChatInput
@onready var send_button: Button = %SendButton
@onready var channel_selector: OptionButton = %ChannelSelector

var _current_channel: String = "local"


func _ready() -> void:
	send_button.pressed.connect(_send_message)
	chat_input.text_submitted.connect(func(_t): _send_message())
	channel_selector.item_selected.connect(_on_channel_selected)

	# Set up channels
	channel_selector.add_item("Local")
	channel_selector.add_item("System")
	channel_selector.add_item("Global")

	# Listen for incoming chat from notifications
	UIManager.chat_received.connect(_on_chat_received)

	# Fetch history
	_fetch_history()


func _on_channel_selected(idx: int) -> void:
	match idx:
		0: _current_channel = "local"
		1: _current_channel = "system"
		2: _current_channel = "global"
	_fetch_history()


func _fetch_history() -> void:
	NetworkManager.send_social_command("get_chat_history",
		{"target": _current_channel}, func(content: Dictionary) -> void:
			var messages: Array = content.get("messages", [])
			chat_log.clear()
			chat_log.append_text("[color=gray]— %s Chat —[/color]\n" % _current_channel.capitalize())
			for msg in messages:
				_append_message(msg)
	)


func _send_message() -> void:
	var text: String = chat_input.text.strip_edges()
	if text.is_empty():
		return
	chat_input.text = ""

	NetworkManager.send_social_command("chat",
		{"content": text, "target": _current_channel}, func(content: Dictionary) -> void:
			# Message will appear via notification or we add it locally
			var warning: String = content.get("warning", "")
			if not warning.is_empty():
				_append_system_msg(warning)
	)


func _on_chat_received(data: Dictionary) -> void:
	_append_message(data)


func _append_message(msg: Dictionary) -> void:
	var sender: String = msg.get("sender", msg.get("username", "Unknown"))
	var text: String = msg.get("message", msg.get("text", ""))
	var channel: String = msg.get("channel", "")

	# Color by sender type
	var sender_color := "cyan"
	if sender == StateManager.player.get("username", StateManager.player.get("name", "")):
		sender_color = "white"

	if channel and channel != _current_channel:
		# Different channel — show with prefix
		chat_log.append_text("[color=gray][%s][/color] " % channel)

	chat_log.append_text("[color=%s]%s:[/color] %s\n" % [sender_color, sender, text])


func _append_system_msg(text: String) -> void:
	chat_log.append_text("[color=yellow]* %s[/color]\n" % text)
