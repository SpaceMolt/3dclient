extends Node3D

signal selected(ship: Node3D)

const TICK_DURATION := 10.0

var player_id: String = ""
var player_name: String = ""
var is_player_ship := false

var _prev_pos := Vector3.ZERO
var _next_pos := Vector3.ZERO
var _tick_t := 1.0  # Start at 1.0 (no interpolation needed until first update)

@onready var name_label: Label3D = $NameLabel
@onready var mesh_instance: MeshInstance3D = $MeshInstance3D
@onready var click_area: Area3D = $ClickArea


func _ready() -> void:
	name_label.text = player_name
	name_label.visible = not player_name.is_empty()
	click_area.input_event.connect(_on_input_event)

	if is_player_ship:
		# Slightly different tint for the player's own ship
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.4, 0.8, 1.0)
		mesh_instance.material_override = mat
		# Player ship doesn't need to be clickable
		click_area.input_ray_pickable = false


func setup(pid: String, pname: String, position: Vector3, is_own: bool = false) -> void:
	player_id = pid
	player_name = pname
	is_player_ship = is_own
	global_position = position
	_prev_pos = position
	_next_pos = position


func move_to(new_pos: Vector3) -> void:
	_prev_pos = global_position
	_next_pos = new_pos
	_tick_t = 0.0


func set_selected(val: bool) -> void:
	if val:
		name_label.modulate = Color(1.0, 1.0, 0.4, 1.0)
	else:
		name_label.modulate = Color.WHITE


func _on_input_event(_camera: Node, event: InputEvent, _position: Vector3, _normal: Vector3, _shape_idx: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if not is_player_ship:
			selected.emit(self)


func _process(delta: float) -> void:
	if _tick_t < 1.0:
		_tick_t = minf(_tick_t + delta / TICK_DURATION, 1.0)
		global_position = _prev_pos.lerp(_next_pos, ease(_tick_t, -2.0))
