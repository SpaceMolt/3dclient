extends Node
class_name AutoTravel

## Executes a multi-jump route through the galaxy, one jump at a time.
## Tracks progress, handles errors, and can be aborted mid-route.

signal route_started(total_jumps: int)
signal jump_completed(current: int, total: int, system_name: String)
signal route_completed
signal route_aborted(reason: String)
signal route_failed(reason: String)

var _route: Array = []  # Array of {system_id, name} dictionaries
var _current_step: int = 0
var _is_active: bool = false
var _abort_requested: bool = false


func start_route(route: Array) -> void:
	if route.is_empty():
		return
	_route = route
	_current_step = 0
	_is_active = true
	_abort_requested = false
	route_started.emit(route.size())
	_execute_next_jump()


func abort() -> void:
	if _is_active:
		_abort_requested = true
		_is_active = false
		route_aborted.emit("Aborted by player")


func is_active() -> bool:
	return _is_active


func get_progress() -> Dictionary:
	return {"current": _current_step, "total": _route.size(), "is_active": _is_active}


func get_current_target() -> Dictionary:
	if _current_step < _route.size():
		return _route[_current_step]
	return {}


func _execute_next_jump() -> void:
	if _abort_requested or _current_step >= _route.size():
		if not _abort_requested:
			_is_active = false
			route_completed.emit()
		return

	var target: Dictionary = _route[_current_step]
	var sys_id: String = target.get("system_id", "")
	var sys_name: String = target.get("name", "")

	Log.i("AutoTravel: jumping to %s (%d/%d)" % [sys_name, _current_step + 1, _route.size()])

	StateManager.is_jumping = true
	NetworkManager.execute_jump(sys_id, func(success: bool):
		StateManager.is_jumping = false
		if _abort_requested:
			return
		if not success:
			_is_active = false
			route_failed.emit("Jump to %s failed" % sys_name)
			return
		_current_step += 1
		jump_completed.emit(_current_step, _route.size(), sys_name)
		if _current_step >= _route.size():
			_is_active = false
			route_completed.emit()
			return
		# Small delay between jumps to let state settle
		get_tree().create_timer(1.0).timeout.connect(_execute_next_jump)
	)
