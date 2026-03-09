extends Node3D

signal selected(marker: Node3D)

var poi_id: String = ""
var poi_name: String = ""
var poi_type: String = ""
var poi_class: String = ""  # type-specific classification (spectral class, composition, etc.)
var is_selected: bool = false

@onready var name_label: Label3D = $NameLabel
@onready var mesh_instance: MeshInstance3D = $MeshInstance3D
@onready var click_area: Area3D = $ClickArea


func _ready() -> void:
	click_area.input_event.connect(_on_input_event)
	if not poi_name.is_empty():
		name_label.text = poi_name
		_apply_appearance()


func setup(id: String, pname: String, ptype: String, pos: Vector3, pclass: String = "") -> void:
	poi_id = id
	poi_name = pname
	poi_type = ptype
	poi_class = pclass
	global_position = pos
	if name_label:
		name_label.text = poi_name
		_apply_appearance()


func set_selected(val: bool) -> void:
	is_selected = val
	if is_selected:
		name_label.modulate = Color(1.0, 1.0, 0.4, 1.0)
	else:
		name_label.modulate = Color(0.8, 0.9, 1.0, 1.0)


func _on_input_event(_camera: Node, event: InputEvent, _position: Vector3, _normal: Vector3, _shape_idx: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		selected.emit(self)


func _process(_delta: float) -> void:
	match poi_type:
		"wormhole", "jump_gate":
			rotate_y(_delta * 1.5)
		"gas_cloud", "nebula":
			rotate_y(_delta * 0.3)
		"station":
			rotate_y(_delta * 0.2)
		"relic":
			rotate_y(_delta * 0.4)


func _add_visual_child(node: Node3D) -> void:
	add_child(node)


func _apply_appearance() -> void:
	match poi_type:
		"sun", "star":
			_make_star()
		"planet", "moon":
			_make_planet()
		"station":
			_make_station()
		"asteroid", "asteroid_field", "asteroid_belt":
			_make_asteroid_cluster()
		"ice_field":
			_make_ice_field()
		"gas_cloud", "nebula":
			_make_gas_cloud()
		"wormhole", "jump_gate":
			_make_wormhole()
		"relic":
			_make_relic()
		_:
			_make_default()


func _make_star() -> void:
	var mesh := SphereMesh.new()
	mesh.radius = 2.5
	mesh.height = 5.0
	var mat := StandardMaterial3D.new()
	# Color based on spectral class (O/B=blue, A=white, F/G=yellow, K=orange, M=red)
	var spectral := poi_class.left(1).to_upper() if not poi_class.is_empty() else ""
	match spectral:
		"O":
			mat.albedo_color = Color(0.6, 0.7, 1.0)
			mat.emission = Color(0.4, 0.5, 1.0)
			mesh.radius = 3.5
			mesh.height = 7.0
		"B":
			mat.albedo_color = Color(0.7, 0.8, 1.0)
			mat.emission = Color(0.5, 0.6, 1.0)
			mesh.radius = 3.0
			mesh.height = 6.0
		"A":
			mat.albedo_color = Color(0.9, 0.92, 1.0)
			mat.emission = Color(0.8, 0.85, 1.0)
		"F":
			mat.albedo_color = Color(1.0, 0.97, 0.9)
			mat.emission = Color(1.0, 0.95, 0.8)
		"G":
			mat.albedo_color = Color(1.0, 0.95, 0.7)
			mat.emission = Color(1.0, 0.9, 0.5)
		"K":
			mat.albedo_color = Color(1.0, 0.7, 0.3)
			mat.emission = Color(1.0, 0.5, 0.1)
		"M":
			mat.albedo_color = Color(1.0, 0.4, 0.2)
			mat.emission = Color(1.0, 0.2, 0.05)
			mesh.radius = 2.0
			mesh.height = 4.0
		_:
			mat.albedo_color = Color(1.0, 0.95, 0.8)
			mat.emission = Color(1.0, 0.9, 0.6)
	mat.emission_enabled = true
	mat.emission_energy_multiplier = 3.0
	mesh_instance.mesh = mesh
	mesh_instance.material_override = mat
	var light := OmniLight3D.new()
	light.light_color = mat.emission
	light.light_energy = 2.0
	light.omni_range = 15.0
	light.omni_attenuation = 2.0
	_add_visual_child(light)


func _make_planet() -> void:
	var mesh := SphereMesh.new()
	mesh.radius = 1.8
	mesh.height = 3.6
	var mat := StandardMaterial3D.new()
	var is_moon := poi_type == "moon"
	if is_moon:
		mesh.radius = 1.0
		mesh.height = 2.0
	# Use class for planet appearance, fall back to name hash
	match poi_class:
		"ocean", "water":
			mat.albedo_color = Color(0.15, 0.4, 0.8)
		"terrestrial", "terran", "earth-like":
			mat.albedo_color = Color(0.25, 0.55, 0.3)
		"desert", "arid":
			mat.albedo_color = Color(0.8, 0.6, 0.3)
		"ice", "frozen", "tundra":
			mat.albedo_color = Color(0.75, 0.85, 0.95)
			mat.emission_enabled = true
			mat.emission = Color(0.3, 0.4, 0.5)
			mat.emission_energy_multiplier = 0.3
		"gas_giant", "jovian":
			mat.albedo_color = Color(0.85, 0.75, 0.55)
			mesh.radius = 2.5
			mesh.height = 5.0
		"volcanic", "lava":
			mat.albedo_color = Color(0.4, 0.2, 0.15)
			mat.emission_enabled = true
			mat.emission = Color(1.0, 0.3, 0.05)
			mat.emission_energy_multiplier = 0.8
		"barren", "rocky":
			mat.albedo_color = Color(0.55, 0.45, 0.4)
		_:
			# Fallback: vary by name hash
			var h := poi_name.hash() % 100
			if h < 25:
				mat.albedo_color = Color(0.2, 0.5, 0.8)
			elif h < 50:
				mat.albedo_color = Color(0.3, 0.6, 0.3)
			elif h < 75:
				mat.albedo_color = Color(0.8, 0.6, 0.3)
			else:
				mat.albedo_color = Color(0.7, 0.5, 0.4)
	mesh_instance.mesh = mesh
	mesh_instance.material_override = mat


func _make_station() -> void:
	# Central hub + ring
	var hub_mesh := BoxMesh.new()
	hub_mesh.size = Vector3(1.5, 1.5, 1.5)
	var hub_mat := StandardMaterial3D.new()
	hub_mat.albedo_color = Color(0.5, 0.6, 0.7)
	hub_mat.metallic = 0.8
	hub_mat.roughness = 0.3
	mesh_instance.mesh = hub_mesh
	mesh_instance.material_override = hub_mat
	# Docking ring
	var ring := MeshInstance3D.new()
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = 1.5
	ring_mesh.outer_radius = 2.0
	ring.mesh = ring_mesh
	var ring_mat := StandardMaterial3D.new()
	ring_mat.albedo_color = Color(0.3, 0.5, 0.8)
	ring_mat.metallic = 0.6
	ring_mat.emission_enabled = true
	ring_mat.emission = Color(0.1, 0.3, 0.6)
	ring_mat.emission_energy_multiplier = 0.5
	ring.material_override = ring_mat
	_add_visual_child(ring)
	# Blinking nav light
	var light := OmniLight3D.new()
	light.name = "NavLight"
	light.light_color = Color(0.2, 0.6, 1.0)
	light.light_energy = 1.5
	light.omni_range = 8.0
	light.position = Vector3(0, 2.0, 0)
	_add_visual_child(light)


func _make_asteroid_cluster() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = poi_name.hash()
	var base_mat := StandardMaterial3D.new()
	# Color based on composition class
	match poi_class:
		"metallic":
			base_mat.albedo_color = Color(0.6, 0.55, 0.5)
			base_mat.metallic = 0.7
			base_mat.roughness = 0.4
		"silicate", "rocky":
			base_mat.albedo_color = Color(0.5, 0.4, 0.3)
			base_mat.roughness = 0.9
		"carbonaceous":
			base_mat.albedo_color = Color(0.25, 0.22, 0.2)
			base_mat.roughness = 0.95
		"mixed":
			base_mat.albedo_color = Color(0.5, 0.45, 0.4)
			base_mat.roughness = 0.7
			base_mat.metallic = 0.3
		_:
			base_mat.albedo_color = Color(0.55, 0.45, 0.35)
			base_mat.roughness = 0.9

	for i in 5:
		var rock := MeshInstance3D.new()
		var mesh := SphereMesh.new()
		var r := rng.randf_range(0.3, 0.8)
		mesh.radius = r
		mesh.height = r * rng.randf_range(1.4, 2.2)  # squished/elongated
		rock.mesh = mesh
		var rock_mat := base_mat.duplicate() as StandardMaterial3D
		var shade := rng.randf_range(0.7, 1.0)
		rock_mat.albedo_color = Color(0.55 * shade, 0.45 * shade, 0.35 * shade)
		rock.material_override = rock_mat
		rock.position = Vector3(
			rng.randf_range(-1.5, 1.5),
			rng.randf_range(-0.5, 0.5),
			rng.randf_range(-1.5, 1.5)
		)
		rock.rotation = Vector3(
			rng.randf_range(0, TAU),
			rng.randf_range(0, TAU),
			rng.randf_range(0, TAU)
		)
		_add_visual_child(rock)

	# Use first rock as the main mesh
	var main_mesh := SphereMesh.new()
	main_mesh.radius = 0.6
	main_mesh.height = 1.0
	mesh_instance.mesh = main_mesh
	mesh_instance.material_override = base_mat


func _make_ice_field() -> void:
	# Crystalline blue-white clusters
	var rng := RandomNumberGenerator.new()
	rng.seed = poi_name.hash()
	var base_mat := StandardMaterial3D.new()
	base_mat.albedo_color = Color(0.7, 0.9, 1.0)
	base_mat.emission_enabled = true
	base_mat.emission = Color(0.3, 0.5, 0.7)
	base_mat.emission_energy_multiplier = 0.5
	base_mat.metallic = 0.3
	base_mat.roughness = 0.1

	for i in 4:
		var shard := MeshInstance3D.new()
		var mesh := PrismMesh.new()
		mesh.size = Vector3(
			rng.randf_range(0.3, 0.6),
			rng.randf_range(0.6, 1.5),
			rng.randf_range(0.3, 0.6)
		)
		shard.mesh = mesh
		shard.material_override = base_mat
		shard.position = Vector3(
			rng.randf_range(-1.2, 1.2),
			rng.randf_range(-0.3, 0.3),
			rng.randf_range(-1.2, 1.2)
		)
		shard.rotation = Vector3(
			rng.randf_range(0, TAU),
			rng.randf_range(0, TAU),
			rng.randf_range(0, TAU)
		)
		_add_visual_child(shard)

	var main_mesh := SphereMesh.new()
	main_mesh.radius = 0.5
	main_mesh.height = 1.0
	mesh_instance.mesh = main_mesh
	mesh_instance.material_override = base_mat


func _make_gas_cloud() -> void:
	# Semi-transparent layered spheres
	var rng := RandomNumberGenerator.new()
	rng.seed = poi_name.hash()

	var colors := [
		Color(0.8, 0.5, 0.2, 0.3),
		Color(0.9, 0.7, 0.3, 0.2),
		Color(0.6, 0.3, 0.1, 0.25),
	]

	for i in 3:
		var cloud := MeshInstance3D.new()
		var mesh := SphereMesh.new()
		mesh.radius = rng.randf_range(1.0, 2.0)
		mesh.height = mesh.radius * 2.0
		cloud.mesh = mesh
		var mat := StandardMaterial3D.new()
		mat.albedo_color = colors[i]
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.emission_enabled = true
		mat.emission = Color(colors[i].r, colors[i].g, colors[i].b)
		mat.emission_energy_multiplier = 0.6
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		cloud.material_override = mat
		cloud.position = Vector3(
			rng.randf_range(-0.5, 0.5),
			rng.randf_range(-0.3, 0.3),
			rng.randf_range(-0.5, 0.5)
		)
		_add_visual_child(cloud)

	# Main mesh — small inner core
	var main := SphereMesh.new()
	main.radius = 0.5
	main.height = 1.0
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.8, 0.4, 0.4)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled = true
	mat.emission = Color(0.8, 0.5, 0.2)
	mat.emission_energy_multiplier = 1.0
	mesh_instance.mesh = main
	mesh_instance.material_override = mat


func _make_wormhole() -> void:
	var mesh := TorusMesh.new()
	mesh.inner_radius = 0.6
	mesh.outer_radius = 1.2
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.8, 0.3, 1.0, 0.8)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled = true
	mat.emission = Color(0.5, 0.1, 0.8)
	mat.emission_energy_multiplier = 2.0
	mesh_instance.mesh = mesh
	mesh_instance.material_override = mat
	# Inner glow
	var light := OmniLight3D.new()
	light.light_color = Color(0.6, 0.2, 1.0)
	light.light_energy = 2.5
	light.omni_range = 10.0
	_add_visual_child(light)


func _make_relic() -> void:
	# Ancient structure — geometric, glowing
	var mat := StandardMaterial3D.new()
	mat.metallic = 0.9
	mat.roughness = 0.2
	match poi_class:
		"megastructure":
			# Large octahedron
			var mesh := SphereMesh.new()
			mesh.radius = 2.0
			mesh.height = 4.0
			mesh.radial_segments = 4
			mesh.rings = 2
			mesh_instance.mesh = mesh
			mat.albedo_color = Color(0.4, 0.5, 0.6)
			mat.emission_enabled = true
			mat.emission = Color(0.2, 0.6, 0.8)
			mat.emission_energy_multiplier = 1.5
		_:
			# Smaller artifact
			var mesh := BoxMesh.new()
			mesh.size = Vector3(1.0, 2.0, 1.0)
			mesh_instance.mesh = mesh
			mat.albedo_color = Color(0.5, 0.5, 0.6)
			mat.emission_enabled = true
			mat.emission = Color(0.3, 0.4, 0.8)
			mat.emission_energy_multiplier = 1.0
	mesh_instance.material_override = mat
	var light := OmniLight3D.new()
	light.light_color = Color(0.3, 0.6, 0.9)
	light.light_energy = 1.5
	light.omni_range = 8.0
	_add_visual_child(light)


func _make_default() -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.5
	mesh.bottom_radius = 0.5
	mesh.height = 1.5
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.5, 0.5, 0.5, 0.8)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh_instance.mesh = mesh
	mesh_instance.material_override = mat
