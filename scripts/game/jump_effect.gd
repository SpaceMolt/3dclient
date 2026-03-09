extends CanvasLayer

## Full-screen white flash + camera shake played during inter-system jumps.
## Listens to StateManager.jump_started / jump_ended signals.

@onready var flash_rect: ColorRect = $FlashRect

const SHAKE_MAGNITUDE := 0.3
const SHAKE_DURATION := 1.0

var _flash_tween: Tween
var _shaking: bool = false
var _shake_elapsed: float = 0.0
var _camera: Camera3D = null
var _camera_original_offset: Vector3 = Vector3.ZERO


func _ready() -> void:
	flash_rect.modulate.a = 0.0
	StateManager.jump_started.connect(_on_jump_started)
	StateManager.jump_ended.connect(_on_jump_ended)


func _process(delta: float) -> void:
	if not _shaking:
		return

	_shake_elapsed += delta
	if _shake_elapsed >= SHAKE_DURATION:
		_stop_shake()
		return

	if not is_instance_valid(_camera):
		_stop_shake()
		return

	# Decay shake intensity over time
	var strength: float = SHAKE_MAGNITUDE * (1.0 - _shake_elapsed / SHAKE_DURATION)
	var offset := Vector3(
		randf_range(-strength, strength),
		randf_range(-strength * 0.3, strength * 0.3),
		randf_range(-strength, strength),
	)
	_camera.position = _camera_original_offset + offset


func _on_jump_started() -> void:
	# Departure flash: alpha 0 → 0.8 over 0.15s, hold for 0.1s
	_kill_flash_tween()
	_flash_tween = create_tween()
	flash_rect.modulate.a = 0.0
	_flash_tween.tween_property(flash_rect, "modulate:a", 0.8, 0.15)
	_flash_tween.tween_interval(0.1)

	# Start camera shake
	_start_shake()


func _on_jump_ended() -> void:
	# Arrival flash: alpha 0.6 → 0 over 0.4s
	_kill_flash_tween()
	_flash_tween = create_tween()
	flash_rect.modulate.a = 0.6
	_flash_tween.tween_property(flash_rect, "modulate:a", 0.0, 0.4)

	# Stop camera shake
	_stop_shake()


func _start_shake() -> void:
	_camera = get_viewport().get_camera_3d()
	if not _camera:
		return
	_camera_original_offset = _camera.position
	_shaking = true
	_shake_elapsed = 0.0


func _stop_shake() -> void:
	if _shaking and is_instance_valid(_camera):
		_camera.position = _camera_original_offset
	_shaking = false
	_shake_elapsed = 0.0
	_camera = null


func _kill_flash_tween() -> void:
	if _flash_tween and _flash_tween.is_valid():
		_flash_tween.kill()
