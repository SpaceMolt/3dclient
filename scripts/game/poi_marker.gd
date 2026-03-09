extends Node3D

const FocusBubble := preload("res://scripts/game/focus_bubble.gd")

signal selected(marker: Node3D)

var poi_id: String = ""
var poi_name: String = ""
var poi_type: String = ""
var poi_class: String = ""  # type-specific classification (spectral class, composition, etc.)
var is_selected: bool = false
var is_impostor: bool = false  # true = distant billboard dot, false = full geometry

@onready var name_label: Label3D = $NameLabel
@onready var mesh_instance: MeshInstance3D = $MeshInstance3D
@onready var click_area: Area3D = $ClickArea


func _ready() -> void:
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


func set_mode(impostor: bool) -> void:
	if impostor == is_impostor:
		return
	is_impostor = impostor
	_clear_visual_children()
	if name_label:
		_apply_appearance()


func set_selected(val: bool) -> void:
	is_selected = val
	if is_selected:
		name_label.modulate = Color(1.0, 1.0, 0.4, 1.0)
	else:
		name_label.modulate = Color(0.8, 0.9, 1.0, 1.0)


func _process(_delta: float) -> void:
	if is_impostor:
		# Impostors: billboard label faces camera, no rotation needed
		return
	match poi_type:
		"wormhole", "wormhole_entrance", "wormhole_exit", "jump_gate":
			rotate_y(_delta * 1.5)
		"gas_cloud", "nebula":
			rotate_y(_delta * 0.3)
		"station":
			rotate_y(_delta * 0.2)
		"relic":
			rotate_y(_delta * 0.4)


func _add_visual_child(node: Node3D) -> void:
	add_child(node)


func _clear_visual_children() -> void:
	# Remove all dynamically added children (lights, extra meshes) but keep scene nodes
	for child in get_children():
		if child == name_label or child == mesh_instance or child == click_area:
			continue
		child.queue_free()


func _apply_appearance() -> void:
	if is_impostor:
		_make_impostor()
		return
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
	var r: float = FocusBubble.poi_radius(poi_type, poi_class)
	var mesh := SphereMesh.new()
	mesh.radius = r
	mesh.height = r * 2.0
	var mat := StandardMaterial3D.new()
	var color := _star_color()
	mat.albedo_color = color
	mat.emission = color
	mat.emission_enabled = true
	mat.emission_energy_multiplier = 3.0
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh_instance.mesh = mesh
	mesh_instance.material_override = mat
	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = 4.0
	light.omni_range = r * 2.0
	light.omni_attenuation = 1.5
	_add_visual_child(light)
	# Label above the star surface
	name_label.position = Vector3(0, r * 1.2, 0)
	name_label.font_size = 96


func _make_planet() -> void:
	var r: float = FocusBubble.poi_radius(poi_type, poi_class)
	var mesh := SphereMesh.new()
	mesh.radius = r
	mesh.height = r * 2.0
	var mat := StandardMaterial3D.new()
	# Use class for planet appearance, fall back to name hash
	match poi_class:
		"oceanic":
			mat.albedo_color = Color(0.15, 0.4, 0.8)
		"terran":
			mat.albedo_color = Color(0.25, 0.55, 0.3)
		"arid", "scorched":
			mat.albedo_color = Color(0.8, 0.6, 0.3)
		"tundra", "glacial", "ice_world":
			mat.albedo_color = Color(0.75, 0.85, 0.95)
			mat.emission_enabled = true
			mat.emission = Color(0.3, 0.4, 0.5)
			mat.emission_energy_multiplier = 0.3
		"jovian", "hot_jupiter":
			mat.albedo_color = Color(0.85, 0.75, 0.55)
		"sub_neptune", "ice_giant":
			mat.albedo_color = Color(0.4, 0.6, 0.85)
		"lava_world", "chthonian":
			mat.albedo_color = Color(0.4, 0.2, 0.15)
			mat.emission_enabled = true
			mat.emission = Color(1.0, 0.3, 0.05)
			mat.emission_energy_multiplier = 0.8
		"carbon":
			mat.albedo_color = Color(0.25, 0.22, 0.2)
		"super_terran":
			mat.albedo_color = Color(0.3, 0.55, 0.4)
		"hothouse":
			mat.albedo_color = Color(0.7, 0.5, 0.3)
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
	# Label above the planet surface
	name_label.position = Vector3(0, r * 1.15, 0)
	name_label.font_size = 72


func _make_station() -> void:
	var r: float = FocusBubble.poi_radius(poi_type, poi_class)
	# Central hub
	var hub_mesh := BoxMesh.new()
	hub_mesh.size = Vector3(r * 0.4, r * 0.6, r * 0.4)
	var hub_mat := StandardMaterial3D.new()
	hub_mat.albedo_color = Color(0.5, 0.6, 0.7)
	hub_mat.metallic = 0.8
	hub_mat.roughness = 0.3
	mesh_instance.mesh = hub_mesh
	mesh_instance.material_override = hub_mat
	# Docking ring
	var ring := MeshInstance3D.new()
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = r * 0.7
	ring_mesh.outer_radius = r
	ring.mesh = ring_mesh
	var ring_mat := StandardMaterial3D.new()
	ring_mat.albedo_color = Color(0.3, 0.5, 0.8)
	ring_mat.metallic = 0.6
	ring_mat.emission_enabled = true
	ring_mat.emission = Color(0.1, 0.3, 0.6)
	ring_mat.emission_energy_multiplier = 0.5
	ring.material_override = ring_mat
	_add_visual_child(ring)
	# Nav lights
	for i in 4:
		var light := OmniLight3D.new()
		light.light_color = Color(0.2, 0.6, 1.0)
		light.light_energy = 2.0
		light.omni_range = r * 0.5
		var angle := TAU * i / 4.0
		light.position = Vector3(cos(angle) * r * 0.8, r * 0.3, sin(angle) * r * 0.8)
		_add_visual_child(light)
	# Label above station
	name_label.position = Vector3(0, r * 0.8, 0)
	name_label.font_size = 64


func _make_asteroid_cluster() -> void:
	var cluster_r: float = FocusBubble.poi_radius(poi_type, poi_class)
	var rng := RandomNumberGenerator.new()
	rng.seed = poi_name.hash()
	var base_mat := StandardMaterial3D.new()
	match poi_class:
		"metallic":
			base_mat.albedo_color = Color(0.6, 0.55, 0.5)
			base_mat.metallic = 0.7
			base_mat.roughness = 0.4
		"silicate":
			base_mat.albedo_color = Color(0.5, 0.4, 0.3)
			base_mat.roughness = 0.9
		"carbonaceous":
			base_mat.albedo_color = Color(0.25, 0.22, 0.2)
			base_mat.roughness = 0.95
		"icy":
			base_mat.albedo_color = Color(0.7, 0.8, 0.9)
			base_mat.roughness = 0.3
		"mixed":
			base_mat.albedo_color = Color(0.5, 0.45, 0.4)
			base_mat.roughness = 0.7
			base_mat.metallic = 0.3
		_:
			base_mat.albedo_color = Color(0.55, 0.45, 0.35)
			base_mat.roughness = 0.9

	for i in 8:
		var rock := MeshInstance3D.new()
		var mesh := SphereMesh.new()
		var r := rng.randf_range(cluster_r * 0.05, cluster_r * 0.2)
		mesh.radius = r
		mesh.height = r * rng.randf_range(1.4, 2.2)
		rock.mesh = mesh
		var rock_mat := base_mat.duplicate() as StandardMaterial3D
		var shade := rng.randf_range(0.7, 1.0)
		rock_mat.albedo_color = base_mat.albedo_color * shade
		rock.material_override = rock_mat
		rock.position = Vector3(
			rng.randf_range(-cluster_r, cluster_r),
			rng.randf_range(-cluster_r * 0.3, cluster_r * 0.3),
			rng.randf_range(-cluster_r, cluster_r)
		)
		rock.rotation = Vector3(rng.randf() * TAU, rng.randf() * TAU, rng.randf() * TAU)
		_add_visual_child(rock)

	var main_mesh := SphereMesh.new()
	main_mesh.radius = cluster_r * 0.15
	main_mesh.height = cluster_r * 0.25
	mesh_instance.mesh = main_mesh
	mesh_instance.material_override = base_mat
	name_label.position = Vector3(0, cluster_r * 0.5, 0)


func _make_ice_field() -> void:
	var field_r: float = FocusBubble.poi_radius(poi_type, poi_class)
	var rng := RandomNumberGenerator.new()
	rng.seed = poi_name.hash()
	var base_mat := StandardMaterial3D.new()
	base_mat.albedo_color = Color(0.7, 0.9, 1.0)
	base_mat.emission_enabled = true
	base_mat.emission = Color(0.3, 0.5, 0.7)
	base_mat.emission_energy_multiplier = 0.5
	base_mat.metallic = 0.3
	base_mat.roughness = 0.1

	for i in 6:
		var shard := MeshInstance3D.new()
		var mesh := PrismMesh.new()
		var s := field_r * rng.randf_range(0.05, 0.15)
		mesh.size = Vector3(s, s * rng.randf_range(1.5, 3.0), s)
		shard.mesh = mesh
		shard.material_override = base_mat
		shard.position = Vector3(
			rng.randf_range(-field_r, field_r),
			rng.randf_range(-field_r * 0.2, field_r * 0.2),
			rng.randf_range(-field_r, field_r)
		)
		shard.rotation = Vector3(rng.randf() * TAU, rng.randf() * TAU, rng.randf() * TAU)
		_add_visual_child(shard)

	var main_mesh := SphereMesh.new()
	main_mesh.radius = field_r * 0.1
	main_mesh.height = field_r * 0.15
	mesh_instance.mesh = main_mesh
	mesh_instance.material_override = base_mat
	name_label.position = Vector3(0, field_r * 0.5, 0)


func _make_gas_cloud() -> void:
	var cloud_r: float = FocusBubble.poi_radius(poi_type, poi_class)
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
		mesh.radius = rng.randf_range(cloud_r * 0.4, cloud_r * 0.8)
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
			rng.randf_range(-cloud_r * 0.3, cloud_r * 0.3),
			rng.randf_range(-cloud_r * 0.15, cloud_r * 0.15),
			rng.randf_range(-cloud_r * 0.3, cloud_r * 0.3)
		)
		_add_visual_child(cloud)

	# Main mesh — inner core
	var main := SphereMesh.new()
	main.radius = cloud_r * 0.25
	main.height = cloud_r * 0.5
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.8, 0.4, 0.4)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled = true
	mat.emission = Color(0.8, 0.5, 0.2)
	mat.emission_energy_multiplier = 1.0
	mesh_instance.mesh = main
	mesh_instance.material_override = mat
	name_label.position = Vector3(0, cloud_r * 0.6, 0)
	name_label.font_size = 48


func _make_wormhole() -> void:
	var r: float = FocusBubble.poi_radius(poi_type, poi_class)
	var mesh := TorusMesh.new()
	mesh.inner_radius = r * 0.5
	mesh.outer_radius = r
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
	light.omni_range = r * 1.5
	_add_visual_child(light)
	name_label.position = Vector3(0, r * 0.8, 0)
	name_label.font_size = 48


func _make_relic() -> void:
	var r: float = FocusBubble.poi_radius(poi_type, poi_class)
	var mat := StandardMaterial3D.new()
	mat.metallic = 0.9
	mat.roughness = 0.2
	match poi_class:
		"megastructure":
			var mesh := SphereMesh.new()
			mesh.radius = r
			mesh.height = r * 2.0
			mesh.radial_segments = 4
			mesh.rings = 2
			mesh_instance.mesh = mesh
			mat.albedo_color = Color(0.4, 0.5, 0.6)
			mat.emission_enabled = true
			mat.emission = Color(0.2, 0.6, 0.8)
			mat.emission_energy_multiplier = 1.5
		_:
			var mesh := BoxMesh.new()
			mesh.size = Vector3(r * 0.5, r, r * 0.5)
			mesh_instance.mesh = mesh
			mat.albedo_color = Color(0.5, 0.5, 0.6)
			mat.emission_enabled = true
			mat.emission = Color(0.3, 0.4, 0.8)
			mat.emission_energy_multiplier = 1.0
	mesh_instance.material_override = mat
	var light := OmniLight3D.new()
	light.light_color = Color(0.3, 0.6, 0.9)
	light.light_energy = 1.5
	light.omni_range = r * 1.5
	_add_visual_child(light)
	name_label.position = Vector3(0, r * 0.8, 0)
	name_label.font_size = 48


func _make_default() -> void:
	var r: float = FocusBubble.poi_radius(poi_type, poi_class)
	var mesh := CylinderMesh.new()
	mesh.top_radius = r * 0.3
	mesh.bottom_radius = r * 0.3
	mesh.height = r * 0.8
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.5, 0.5, 0.5, 0.8)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh_instance.mesh = mesh
	mesh_instance.material_override = mat


func _make_impostor() -> void:
	# Small glowing sphere + name label for distant POIs
	var color := _impostor_color()
	var mesh := SphereMesh.new()
	mesh.radius = 8.0
	mesh.height = 16.0
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 2.0
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh_instance.mesh = mesh
	mesh_instance.material_override = mat
	# Make label larger for distance readability
	name_label.font_size = 64
	name_label.position = Vector3(0, 14.0, 0)
	# Update collision shape for impostor hit detection
	var shape_node := click_area.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if shape_node and shape_node.shape is SphereShape3D:
		(shape_node.shape as SphereShape3D).radius = 12.0


func _impostor_color() -> Color:
	match poi_type:
		"sun", "star":
			return _star_color()
		"planet":
			return Color(0.4, 0.6, 0.9)  # blue-white
		"moon":
			return Color(0.7, 0.7, 0.7)
		"station":
			return Color(0.3, 0.8, 1.0)  # cyan
		"asteroid", "asteroid_belt":
			return Color(0.6, 0.5, 0.4)  # brown
		"ice_field":
			return Color(0.7, 0.9, 1.0)  # ice blue
		"nebula", "gas_cloud":
			return Color(0.8, 0.5, 0.2)  # orange
		"relic":
			return Color(0.3, 0.6, 0.9)  # blue glow
		"wormhole_entrance", "wormhole_exit", "wormhole_collapsed":
			return Color(0.7, 0.2, 1.0)  # purple
		_:
			return Color(0.5, 0.5, 0.5)


func _star_color() -> Color:
	var spectral := poi_class.left(1).to_upper() if not poi_class.is_empty() else ""
	match spectral:
		"O", "B":
			return Color(0.6, 0.7, 1.0)
		"A":
			return Color(0.9, 0.92, 1.0)
		"F":
			return Color(1.0, 0.97, 0.9)
		"G":
			return Color(1.0, 0.95, 0.7)
		"K":
			return Color(1.0, 0.7, 0.3)
		"M", "L", "T", "Y":
			return Color(1.0, 0.4, 0.2)
		_:
			return Color(1.0, 0.95, 0.8)
