extends Node

signal error_shown(message: String)
signal info_shown(message: String)
signal chat_received(data: Dictionary)
signal event_received(notif: Dictionary)

var _event_log: Node = null


func register_event_log(log_node: Node) -> void:
	_event_log = log_node


func show_error(message: String) -> void:
	Log.w(message)
	error_shown.emit(message)
	_dispatch("add_error", message)


func show_info(message: String) -> void:
	info_shown.emit(message)
	_dispatch("add_info", message)


func add_chat(data: Dictionary) -> void:
	chat_received.emit(data)
	_dispatch("add_chat", data)


func add_event(notif: Dictionary) -> void:
	event_received.emit(notif)
	_dispatch("add_raw", notif)


func _dispatch(method: String, payload) -> void:
	if _event_log and _event_log.has_method(method):
		_event_log.call(method, payload)
