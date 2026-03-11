extends Node3D

signal selected(ship: Node3D)

## Duration is read from NetworkManager.tick_duration at interpolation time.

var player_id: String = ""
var player_name: String = ""
var is_player_ship := false
var ship_class_id: String = ""
var ship_class_name: String = ""

var _prev_pos := Vector3.ZERO
var _next_pos := Vector3.ZERO
var _tick_t := 1.0  # Start at 1.0 (no interpolation needed until first update)
var _uses_custom_model := false
var _missing_model_logged := false
var _has_setup_data := false

@onready var name_label: Label3D = $NameLabel
@onready var mesh_instance: MeshInstance3D = $MeshInstance3D
@onready var wing_left: MeshInstance3D = $WingLeft
@onready var wing_right: MeshInstance3D = $WingRight
@onready var click_area: Area3D = $ClickArea
@onready var engine_glow: OmniLight3D = $EngineGlow
@onready var model_root: Node3D = $ModelRoot


func _ready() -> void:
	name_label.text = player_name
	name_label.visible = not player_name.is_empty()
	click_area.input_event.connect(_on_input_event)
	_refresh_visuals()

	if is_player_ship:
		# Player ship doesn't need to be clickable
		click_area.input_ray_pickable = false
		engine_glow.light_color = Color(0.4, 0.8, 1.0)


func setup(
	pid: String,
	pname: String,
	position: Vector3,
	is_own: bool = false,
	primary_color: String = "",
	secondary_color: String = "",
	class_id: String = "",
	ship_class_name: String = ""
) -> void:
	_has_setup_data = true
	player_id = pid
	player_name = pname
	is_player_ship = is_own
	self.ship_class_name = ship_class_name
	ship_class_id = AssetLoader.resolve_ship_class_id(class_id, ship_class_name)
	global_position = position
	_prev_pos = position
	_next_pos = position

	if is_node_ready():
		name_label.text = player_name
		name_label.visible = not player_name.is_empty()
		_refresh_visuals()

	if not is_own and not primary_color.is_empty():
		_apply_colors(primary_color, secondary_color)


var _travel_duration := 0.0  # When > 0, overrides tick_duration for interpolation


func update_ship_class(class_id: String, ship_class_name: String = "") -> void:
	var resolved_class_id := AssetLoader.resolve_ship_class_id(class_id, ship_class_name)
	if resolved_class_id == ship_class_id and ship_class_name == self.ship_class_name:
		return
	ship_class_id = resolved_class_id
	self.ship_class_name = ship_class_name
	_missing_model_logged = false
	if is_node_ready():
		_refresh_visuals()


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
	if not _uses_custom_model:
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


func _refresh_visuals() -> void:
	_mount_ship_model()
	if is_player_ship and not _uses_custom_model:
		var player_mat := StandardMaterial3D.new()
		player_mat.albedo_color = Color(0.4, 0.8, 1.0)
		mesh_instance.material_override = player_mat


func _mount_ship_model() -> void:
	for child in model_root.get_children():
		child.queue_free()
	_uses_custom_model = false

	var model_scene := _resolve_model_scene()
	if model_scene == null:
		if _has_setup_data:
			_log_missing_model()
		_set_placeholder_visible(true)
		return

	var model := model_scene.instantiate() as Node3D
	if model == null:
		if _has_setup_data:
			_log_missing_model()
		_set_placeholder_visible(true)
		return

	model_root.add_child(model)
	_normalize_model_transform(model)
	_set_placeholder_visible(false)
	_uses_custom_model = true


func _resolve_model_scene() -> PackedScene:
	var model_scene := AssetLoader.get_ship_scene(ship_class_id, ship_class_name)
	if model_scene != null:
		return model_scene
	if player_name == "Anonymous" and ship_class_id.is_empty():
		return AssetLoader.get_ship_scene("theoria")
	return null


func _set_placeholder_visible(visible: bool) -> void:
	mesh_instance.visible = visible
	wing_left.visible = visible
	wing_right.visible = visible


func _normalize_model_transform(model: Node3D) -> void:
	model.rotation_degrees = Vector3(0.0, -90.0, 0.0)

	var model_aabb := _compute_model_aabb(model)
	if model_aabb.size.length_squared() <= 0.0001:
		return

	var longest_axis := maxf(model_aabb.size.x, maxf(model_aabb.size.y, model_aabb.size.z))
	var target_span := AssetLoader.get_ship_world_span(ship_class_id)
	var scale_factor := target_span / maxf(longest_axis, 0.001)
	var model_center := model_aabb.position + model_aabb.size * 0.5
	model.scale = Vector3.ONE * scale_factor
	model.position = -model_center * scale_factor


func _log_missing_model() -> void:
	if _missing_model_logged:
		return
	_missing_model_logged = true
	var display_name := player_name if not player_name.is_empty() else player_id
	var class_summary := AssetLoader.describe_ship_class_from_data({
		"class_id": ship_class_id,
		"class_name": ship_class_name,
		"name": player_name,
	})
	NetworkManager.append_missing_model_log(
		"missing_model ship_name=%s ship_id=%s class_id=%s details=%s"
		% [display_name, player_id, ship_class_id, class_summary]
	)


func _compute_model_aabb(root: Node3D) -> AABB:
	var has_bounds := false
	var min_corner := Vector3.ZERO
	var max_corner := Vector3.ZERO
	var stack: Array[Node] = [root]

	while not stack.is_empty():
		var current: Node = stack.pop_back()
		for child in current.get_children():
			stack.append(child)
		if not (current is MeshInstance3D):
			continue
		var mesh_instance_3d := current as MeshInstance3D
		if mesh_instance_3d.mesh == null:
			continue
		var local_aabb := mesh_instance_3d.mesh.get_aabb()
		for corner in _aabb_corners(local_aabb):
			var world_corner := mesh_instance_3d.to_global(corner)
			var root_corner := root.to_local(world_corner)
			if not has_bounds:
				has_bounds = true
				min_corner = root_corner
				max_corner = root_corner
				continue
			min_corner = min_corner.min(root_corner)
			max_corner = max_corner.max(root_corner)

	if not has_bounds:
		return AABB()
	return AABB(min_corner, max_corner - min_corner)


func _aabb_corners(aabb: AABB) -> Array[Vector3]:
	var base: Vector3 = aabb.position
	var size: Vector3 = aabb.size
	return [
		base,
		base + Vector3(size.x, 0.0, 0.0),
		base + Vector3(0.0, size.y, 0.0),
		base + Vector3(0.0, 0.0, size.z),
		base + Vector3(size.x, size.y, 0.0),
		base + Vector3(size.x, 0.0, size.z),
		base + Vector3(0.0, size.y, size.z),
		base + size,
	]
