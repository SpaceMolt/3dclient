extends Camera3D

const ZOOM_MIN := 5.0
const ZOOM_MAX := 80.0
const ZOOM_SPEED := 0.15
const PAN_SPEED := 0.05
const FOLLOW_LERP := 4.0

var _target: Node3D = null
var _following: bool = true
var _drag_start: Vector2 = Vector2.ZERO
var _dragging: bool = false
var _zoom: float = 20.0


func _ready() -> void:
	_apply_zoom()


func follow(node: Node3D) -> void:
	_target = node
	_following = true


func stop_following() -> void:
	_following = false


func _process(delta: float) -> void:
	if _following and _target:
		var target_pos := Vector3(_target.global_position.x, _zoom, _target.global_position.z + _zoom * 0.4)
		global_position = global_position.lerp(target_pos, FOLLOW_LERP * delta)
		look_at(Vector3(global_position.x, 0.0, global_position.z - _zoom * 0.1), Vector3.UP)


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom = clampf(_zoom - _zoom * ZOOM_SPEED, ZOOM_MIN, ZOOM_MAX)
			_apply_zoom()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom = clampf(_zoom + _zoom * ZOOM_SPEED, ZOOM_MIN, ZOOM_MAX)
			_apply_zoom()
		elif event.button_index == MOUSE_BUTTON_MIDDLE:
			_dragging = event.pressed
			_drag_start = event.position
			if event.pressed:
				stop_following()

	elif event is InputEventMouseMotion and _dragging:
		var pan_delta: Vector2 = event.relative * PAN_SPEED * (_zoom / 20.0)
		global_position += Vector3(-pan_delta.x, 0.0, -pan_delta.y)


func _apply_zoom() -> void:
	position.y = _zoom
	position.z = _zoom * 0.4
