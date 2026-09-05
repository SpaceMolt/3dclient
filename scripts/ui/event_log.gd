extends PanelContainer

const MAX_ENTRIES := 200

@onready var log_text: RichTextLabel = %LogText


func _ready() -> void:
	UIManager.register_event_log(self)


func add_error(message: String) -> void:
	_append("[color=red][ERROR][/color] %s" % message)


func add_info(message: String) -> void:
	_append("[color=cyan][INFO][/color] %s" % message)


func add_chat(data: Dictionary) -> void:
	var sender: String = data.get("username", data.get("sender", "?"))
	var text: String = data.get("content", data.get("message", data.get("text", "")))
	var channel: String = data.get("channel", "local")
	_append("[color=yellow][%s][/color] [b]%s[/b]: %s" % [channel, sender, text])


func add_raw(notif: Dictionary) -> void:
	var msg_type: String = notif.get("msg_type", notif.get("type", "event"))
	var text: String = notif.get("message", notif.get("result", ""))
	if text.is_empty():
		text = JSON.stringify(notif.get("data", notif))
	_append("[color=gray][%s][/color] %s" % [msg_type, text])


func _append(bbcode: String) -> void:
	# Trim old entries to stay under MAX_ENTRIES
	var line_count := log_text.get_line_count()
	if line_count > MAX_ENTRIES:
		var text := log_text.text
		var newline_pos := text.find("\n")
		if newline_pos != -1:
			log_text.text = text.substr(newline_pos + 1)

	log_text.append_text("\n" + bbcode)
	log_text.scroll_to_line(log_text.get_line_count() - 1)
