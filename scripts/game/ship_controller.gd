extends Node3D

signal selected(ship: Node3D)

## Duration is read from NetworkManager.tick_duration at interpolation time.

var player_id: String = ""
var player_name: String = ""
var is_player_ship := false

var _prev_pos := Vector3.ZERO
var _next_pos := Vector3.ZERO
var _tick_t := 1.0  # Start at 1.0 (no interpolation needed until first update)

@onready var name_label: Label3D = $NameLabel
@onready var mesh_instance: MeshInstance3D = $MeshInstance3D
@onready var click_area: Area3D = $ClickArea
@onready var engine_glow: OmniLight3D = $EngineGlow


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


func setup(pid: String, pname: String, position: Vector3, is_own: bool = false, primary_color: String = "", secondary_color: String = "") -> void:
	player_id = pid
	player_name = pname
	is_player_ship = is_own
	global_position = position
	_prev_pos = position
	_next_pos = position

	if not is_own and not primary_color.is_empty():
		_apply_colors(primary_color, secondary_color)


var _travel_duration := 0.0  # When > 0, overrides tick_duration for interpolation


func move_to(new_pos: Vector3) -> void:
	# Snap instead of interpolate on large jumps (login, first spawn)
	var dist := global_position.distance_to(new_pos)
	if dist > 20.0 and _travel_duration <= 0.0:
		# Large move without travel animation — snap
		global_position = new_pos
		_prev_pos = new_pos
		_next_pos = new_pos
		_tick_t = 1.0
		return
	if global_position.is_equal_approx(Vector3.ZERO) and dist > 1.0:
		# First placement — snap
		global_position = new_pos
		_prev_pos = new_pos
		_next_pos = new_pos
		_tick_t = 1.0
		return
	_prev_pos = global_position
	_next_pos = new_pos
	_tick_t = 0.0


func travel_to(new_pos: Vector3) -> void:
	# Smooth animated travel over 2 seconds regardless of distance
	_travel_duration = 2.0
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


func _apply_colors(primary: String, secondary: String) -> void:
	var primary_color := Color.from_string(primary, Color(0.7, 0.7, 0.7))
	var mat := StandardMaterial3D.new()
	mat.albedo_color = primary_color
	if not secondary.is_empty():
		mat.emission_enabled = true
		mat.emission = Color.from_string(secondary, Color.BLACK)
		mat.emission_energy_multiplier = 0.3
	mesh_instance.material_override = mat
	# Tint engine glow to match primary color
	engine_glow.light_color = primary_color.lightened(0.3)


func update_colors(primary: String, secondary: String) -> void:
	if is_player_ship:
		return
	_apply_colors(primary, secondary)


func set_pirate_aura(is_boss: bool, tier: String) -> void:
	if not is_boss and tier != "elite":
		return
	# Create a pulsing aura light for boss/elite pirates
	var aura := OmniLight3D.new()
	aura.name = "BossAura"
	if is_boss:
		aura.light_color = Color(1.0, 0.1, 0.1)
		aura.light_energy = 3.0
		aura.omni_range = 5.0
	else:  # elite
		aura.light_color = Color(1.0, 0.4, 0.0)
		aura.light_energy = 2.0
		aura.omni_range = 4.0
	aura.omni_attenuation = 1.5
	add_child(aura)


func _process(delta: float) -> void:
	if _tick_t < 1.0:
		var duration := _travel_duration if _travel_duration > 0.0 else NetworkManager.tick_duration
		_tick_t = minf(_tick_t + delta / duration, 1.0)
		global_position = _prev_pos.lerp(_next_pos, ease(_tick_t, -2.0))
		# Brighter engine glow while moving
		engine_glow.light_energy = lerpf(2.5, 1.0, _tick_t)
		# Clear travel duration when done
		if _tick_t >= 1.0 and _travel_duration > 0.0:
			_travel_duration = 0.0
	else:
		engine_glow.light_energy = lerpf(engine_glow.light_energy, 0.8, delta * 2.0)

	# Pulse boss/elite aura
	var aura := get_node_or_null("BossAura") as OmniLight3D
	if aura:
		var pulse := sin(Time.get_ticks_msec() * 0.003) * 0.5 + 0.5  # 0..1 oscillation
		aura.light_energy = lerpf(1.5, 3.5, pulse)
