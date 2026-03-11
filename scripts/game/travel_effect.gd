extends CanvasLayer

## Screen-space warp-lines effect shown during travel/jump commands.
## Listens to StateManager.travel_started / travel_ended signals.

@onready var color_rect: ColorRect = $ColorRect

var _tween: Tween


func _ready() -> void:
	visible = false
	StateManager.travel_started.connect(_on_travel_started)
	StateManager.travel_ended.connect(_on_travel_ended)


func _on_travel_started(_dest_poi_id: String = "", _dest_poi_name: String = "") -> void:
	# Warp effect disabled while tuning travel animation
	pass


func _on_travel_ended() -> void:
	_animate_intensity(null, 0.0, 0.3, true)


func _animate_intensity(from, to: float, duration: float, hide_on_finish: bool = false) -> void:
	if _tween and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	var mat := color_rect.material as ShaderMaterial
	if from != null:
		mat.set_shader_parameter("intensity", from)
	_tween.tween_method(func(val: float): mat.set_shader_parameter("intensity", val),
		mat.get_shader_parameter("intensity") as float, to, duration)
	if hide_on_finish:
		_tween.tween_callback(func(): visible = false)
