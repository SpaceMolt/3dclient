extends Node

## Smoothly zooms the camera in when docking and back out when undocking.
## Tweens the camera's position.y and position.z directly.

const ZOOM_DURATION := 0.8
const DOCK_ZOOM_FACTOR := 0.6

var _original_y: float = 0.0
var _original_z: float = 0.0
var _tween: Tween = null


func _ready() -> void:
	StateManager.docking_started.connect(_on_docking_started)
	StateManager.undocking_started.connect(_on_undocking_started)


func _on_docking_started() -> void:
	var camera := get_viewport().get_camera_3d()
	if not camera:
		return

	_original_y = camera.position.y
	_original_z = camera.position.z

	_kill_tween()
	_tween = create_tween().set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_CUBIC)
	_tween.set_parallel(true)
	_tween.tween_property(camera, "position:y", _original_y * DOCK_ZOOM_FACTOR, ZOOM_DURATION)
	_tween.tween_property(camera, "position:z", _original_z * DOCK_ZOOM_FACTOR, ZOOM_DURATION)


func _on_undocking_started() -> void:
	var camera := get_viewport().get_camera_3d()
	if not camera:
		return

	_kill_tween()
	_tween = create_tween().set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_CUBIC)
	_tween.set_parallel(true)
	_tween.tween_property(camera, "position:y", _original_y, ZOOM_DURATION)
	_tween.tween_property(camera, "position:z", _original_z, ZOOM_DURATION)


func _kill_tween() -> void:
	if _tween and _tween.is_valid():
		_tween.kill()
	_tween = null
