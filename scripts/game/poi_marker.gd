extends Node3D

const FocusBubble := preload("res://scripts/game/focus_bubble.gd")

signal selected(marker: Node3D)

var poi_id: String = ""
var poi_name: String = ""
var poi_type: String = ""
var poi_class: String = ""  # type-specific classification (spectral class, composition, etc.)
var is_selected: bool = false
var _uses_custom_model: bool = false
var _beacon: Sprite3D = null

const BEACON_HIDE_RADII := 30.0  # hide the beacon dot once the camera is this many radii away or closer
const LABEL_HIDE_RADII := 3.0    # hide the name when the camera is right on top of the body

@onready var name_label: Label3D = $NameLabel
@onready var mesh_instance: MeshInstance3D = $MeshInstance3D
@onready var click_area: Area3D = $ClickArea


func _ready() -> void:
	if not poi_name.is_empty():
		name_label.text = poi_name
		_apply_appearance()
		_apply_cull_margin()


func setup(id: String, pname: String, ptype: String, pos: Vector3, pclass: String = "") -> void:
	poi_id = id
	poi_name = pname
	poi_type = ptype
	poi_class = pclass
	global_position = pos
	if name_label:
		name_label.text = poi_name
		_apply_appearance()
		_apply_cull_margin()
		_ensure_beacon()


func set_selected(val: bool) -> void:
	is_selected = val
	if is_selected:
		name_label.modulate = ThemeColors.WARNING_YELLOW
	else:
		name_label.modulate = ThemeColors.STAR_WHITE


func _process(_delta: float) -> void:
	if _beacon:
		var camera := get_viewport().get_camera_3d()
		if camera:
			var radius := FocusBubble.poi_radius(poi_type, poi_class)
			var distance := camera.global_position.distance_to(global_position)
			_beacon.visible = distance > radius * BEACON_HIDE_RADII
			name_label.visible = distance > radius * LABEL_HIDE_RADII
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
		if child == name_label or child == mesh_instance or child == click_area or child == _beacon:
			continue
		child.queue_free()


func _apply_cull_margin() -> void:
	var radius := FocusBubble.poi_radius(poi_type, poi_class)
	mesh_instance.extra_cull_margin = maxf(radius * 4.0, 2000.0)
	for child in get_children():
		if child is MeshInstance3D:
			(child as MeshInstance3D).extra_cull_margin = maxf(radius * 4.0, 2000.0)


func _apply_appearance() -> void:
	_clear_visual_children()
	_uses_custom_model = false
	mesh_instance.visible = true
	match poi_type:
		"sun", "star":
			_make_star()
		"planet", "moon":
			if not _make_celestial_model():
				_make_planet()
		"station":
			_make_station()
		"asteroid", "asteroid_field", "asteroid_belt":
			if not _make_celestial_field():
				_make_asteroid_cluster()
		"ice_field":
			if not _make_celestial_field():
				_make_ice_field()
		"gas_cloud", "nebula":
			_make_gas_cloud()
		"wormhole", "jump_gate":
			_make_wormhole()
		"relic":
			_make_relic()
		_:
			_make_default()
	# Labels keep one screen size at any distance so a far POI still reads.
	name_label.fixed_size = true
	name_label.no_depth_test = true
	name_label.font_size = 18
	name_label.outline_size = 5
	name_label.pixel_size = 0.0011  # with fixed_size this sets the on-screen size
	name_label.offset = Vector2(0.0, 16.0)  # sit above the beacon dot when far away


## A soft glow dot the size of a few pixels at any distance, so every POI in the
## system is findable from the ship. Hidden when the camera is close enough to see geometry.
func _ensure_beacon() -> void:
	if _beacon:
		_beacon.modulate = beacon_color()
		return
	_beacon = Sprite3D.new()
	_beacon.name = "Beacon"
	_beacon.texture = _glow_texture()
	_beacon.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_beacon.fixed_size = true
	_beacon.no_depth_test = true
	_beacon.pixel_size = 0.0012
	_beacon.modulate = beacon_color()
	add_child(_beacon)


## 32 px radial white-to-transparent gradient, tinted by the sprite's modulate.
static func _glow_texture() -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1.0, 1.0, 1.0, 1.0))
	gradient.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(0.5, 0.0)
	texture.width = 32
	texture.height = 32
	return texture


func beacon_color() -> Color:
	match poi_type:
		"sun", "star":
			return _star_color()
		"station":
			return ThemeColors.PLASMA_CYAN
		"planet", "moon":
			return ThemeColors.LASER_BLUE
		"asteroid", "asteroid_field", "asteroid_belt", "ice_field":
			return ThemeColors.CHROME_SILVER
		"gas_cloud", "nebula":
			return ThemeColors.VOID_PURPLE
		"relic":
			return ThemeColors.WARNING_YELLOW
		"wormhole", "wormhole_entrance", "wormhole_exit", "jump_gate":
			return ThemeColors.BIO_GREEN
		_:
			return ThemeColors.HULL_GREY


func _make_celestial_model() -> bool:
	var model_path := _celestial_model_path()
	if model_path.is_empty():
		return false
	if not ResourceLoader.exists(model_path):
		return false
	var model_scene := load(model_path) as PackedScene
	if model_scene == null:
		return false
	var model := model_scene.instantiate() as Node3D
	if model == null:
		return false
	_add_visual_child(model)
	_fit_model_to_radius(model, FocusBubble.poi_radius(poi_type, poi_class))
	mesh_instance.mesh = null
	mesh_instance.material_override = null
	mesh_instance.visible = false
	_uses_custom_model = true
	var radius := FocusBubble.poi_radius(poi_type, poi_class)
	name_label.position = Vector3(0, radius * 1.15, 0)
	name_label.font_size = 72
	return true


func _make_celestial_field() -> bool:
	var model_paths := _celestial_field_model_paths()
	if model_paths.is_empty():
		return false
	var field_radius := FocusBubble.poi_radius(poi_type, poi_class)
	var rng := RandomNumberGenerator.new()
	rng.seed = poi_name.hash()
	var instance_count := 10 if poi_type == "ice_field" else 14
	var created_any := false
	for index in instance_count:
		var model_path := model_paths[index % model_paths.size()]
		if not ResourceLoader.exists(model_path):
			continue
		var model_scene := load(model_path) as PackedScene
		if model_scene == null:
			continue
		var model := model_scene.instantiate() as Node3D
		if model == null:
			continue
		_add_visual_child(model)
		var piece_radius := field_radius * rng.randf_range(0.08, 0.22)
		_fit_model_to_radius(model, piece_radius)
		model.position = Vector3(
			rng.randf_range(-field_radius, field_radius),
			rng.randf_range(-field_radius * 0.18, field_radius * 0.18),
			rng.randf_range(-field_radius, field_radius)
		)
		model.rotation = Vector3(rng.randf() * TAU, rng.randf() * TAU, rng.randf() * TAU)
		created_any = true
	if not created_any:
		return false
	mesh_instance.mesh = null
	mesh_instance.material_override = null
	mesh_instance.visible = false
	_uses_custom_model = true
	name_label.position = Vector3(0, field_radius * 0.55, 0)
	name_label.font_size = 64
	return true


func _celestial_model_path() -> String:
	match poi_type:
		"planet", "moon":
			return "res://assets/celestial/%s.glb" % _planet_model_id()
		_:
			return ""


func _celestial_field_model_paths() -> Array[String]:
	match poi_type:
		"asteroid", "asteroid_field", "asteroid_belt":
			if poi_class == "metallic":
				return [
					"res://assets/celestial/asteroid_metallic.glb",
					"res://assets/celestial/asteroid_large.glb",
				]
			if poi_class == "icy":
				return [
					"res://assets/celestial/asteroid_icy.glb",
					"res://assets/celestial/asteroid_small.glb",
				]
			return [
				"res://assets/celestial/asteroid_large.glb",
				"res://assets/celestial/asteroid_small.glb",
				"res://assets/celestial/asteroid_metallic.glb",
			]
		"ice_field":
			return [
				"res://assets/celestial/ice_chunk_large.glb",
				"res://assets/celestial/ice_chunk_small.glb",
			]
		_:
			return []


func _planet_model_id() -> String:
	if poi_name.strip_edges().to_lower() == "earth":
		return "planet_earth"
	match poi_class:
		"jovian":
			return "gas_giant_orange"
		"hot_jupiter":
			return "gas_giant_ringed"
		"sub_neptune", "ice_giant":
			return "gas_giant_blue"
		"arid", "hothouse":
			return "planet_arid"
		"scorched", "lava_world", "chthonian", "carbon":
			return "planet_scorched"
		"tundra", "glacial", "ice_world":
			return "planet_ice"
		"terran", "super_terran":
			return "planet_earth"
		"oceanic":
			return "planet_terran"
		_:
			return "planet_terran"


func _asteroid_model_id() -> String:
	match poi_class:
		"metallic":
			return "asteroid_metallic"
		"icy":
			return "asteroid_icy"
		_:
			return "asteroid_large"


func _fit_model_to_radius(model: Node3D, target_radius: float) -> void:
	var model_aabb := _compute_model_aabb(model)
	if model_aabb.size.length_squared() <= 0.0001:
		return
	var longest_axis := maxf(model_aabb.size.x, maxf(model_aabb.size.y, model_aabb.size.z))
	var target_span := target_radius * 2.0
	var scale_factor := target_span / maxf(longest_axis, 0.001)
	var model_center := model_aabb.position + model_aabb.size * 0.5
	model.scale = Vector3.ONE * scale_factor
	model.position = -model_center * scale_factor


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
		var mesh_node := current as MeshInstance3D
		if mesh_node.mesh == null:
			continue
		var local_aabb := mesh_node.mesh.get_aabb()
		for corner in _aabb_corners(local_aabb):
			var world_corner := mesh_node.to_global(corner)
			var root_corner := root.to_local(world_corner)
			if not has_bounds:
				min_corner = root_corner
				max_corner = root_corner
				has_bounds = true
				continue
			min_corner = min_corner.min(root_corner)
			max_corner = max_corner.max(root_corner)

	if not has_bounds:
		return AABB()
	return AABB(min_corner, max_corner - min_corner)


func _aabb_corners(box: AABB) -> Array[Vector3]:
	var p := box.position
	var s := box.size
	return [
		p,
		p + Vector3(s.x, 0, 0),
		p + Vector3(0, s.y, 0),
		p + Vector3(0, 0, s.z),
		p + Vector3(s.x, s.y, 0),
		p + Vector3(s.x, 0, s.z),
		p + Vector3(0, s.y, s.z),
		p + s,
	]


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
	mat.emission_energy_multiplier = 6.0  # hot enough to bloom through the glow pass
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh_instance.mesh = mesh
	mesh_instance.material_override = mat
	# Corona: a soft billboard glow a few radii wide, so the star reads from across the system
	var corona := Sprite3D.new()
	corona.texture = _glow_texture()
	corona.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	corona.pixel_size = r * 3.5 / 32.0
	corona.modulate = Color(color, 0.55)
	corona.no_depth_test = true
	corona.render_priority = -1
	_add_visual_child(corona)
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
	var hull := _metal_material(Color(0.34, 0.38, 0.44))
	var trim := _metal_material(Color(0.17, 0.19, 0.24))
	var windows := _emissive_material(ThemeColors.PLASMA_CYAN, 2.5)
	var beacons := _emissive_material(ThemeColors.SHELL_ORANGE, 3.0)
	var panels := _metal_material(Color(0.08, 0.14, 0.32))
	panels.emission_enabled = true
	panels.emission = Color(0.1, 0.2, 0.5)
	panels.emission_energy_multiplier = 0.4

	# Central hub stays on mesh_instance (click target, tests)
	var hub := CylinderMesh.new()
	hub.top_radius = r * 0.16
	hub.bottom_radius = r * 0.2
	hub.height = r * 0.7
	mesh_instance.mesh = hub
	mesh_instance.material_override = hull

	# Spine through the hub
	_add_cylinder(r * 0.05, r * 1.6, Vector3.ZERO, trim)

	# Habitat ring with six spokes and a band of lit windows on its outer face
	_add_torus(r * 0.82, r * 0.94, Vector3.ZERO, hull)
	for i in 6:
		var angle := TAU * i / 6.0
		var spoke := _add_cylinder(r * 0.025, r * 0.84, Vector3(cos(angle) * r * 0.46, 0.0, sin(angle) * r * 0.46), trim)
		spoke.rotation = Vector3(PI / 2.0, 0.0, 0.0)
		spoke.rotate_y(angle + PI / 2.0)
	for i in 32:
		var angle := TAU * i / 32.0
		var window := _add_box(Vector3(r * 0.05, r * 0.02, r * 0.012), Vector3(cos(angle) * r * 0.945, 0.0, sin(angle) * r * 0.945), windows)
		window.rotation.y = -angle + PI / 2.0

	# Smaller service ring above the hub
	_add_torus(r * 0.42, r * 0.48, Vector3(0.0, r * 0.32, 0.0), trim)

	# Four docking pylons below the hub, tipped with orange approach beacons
	for i in 4:
		var angle := TAU * i / 4.0 + PI / 4.0
		var base := Vector3(cos(angle) * r * 0.28, -r * 0.45, sin(angle) * r * 0.28)
		_add_box(Vector3(r * 0.06, r * 0.3, r * 0.06), base, trim)
		var tip := MeshInstance3D.new()
		var tip_mesh := SphereMesh.new()
		tip_mesh.radius = r * 0.025
		tip_mesh.height = r * 0.05
		tip.mesh = tip_mesh
		tip.material_override = beacons
		tip.position = base + Vector3(0.0, -r * 0.17, 0.0)
		_add_visual_child(tip)

	# Solar arrays on arms at the top of the spine
	for side in [-1.0, 1.0]:
		_add_box(Vector3(r * 0.5, r * 0.012, r * 0.22), Vector3(side * r * 0.42, r * 0.7, 0.0), panels)
		_add_box(Vector3(r * 0.3, r * 0.02, r * 0.02), Vector3(side * r * 0.15, r * 0.7, 0.0), trim)

	# Nav lights: cyan on the ring, orange at the docks
	for i in 4:
		var angle := TAU * i / 4.0
		var light := OmniLight3D.new()
		light.light_color = ThemeColors.PLASMA_CYAN if i % 2 == 0 else ThemeColors.SHELL_ORANGE
		light.light_energy = 2.0
		light.omni_range = r * 0.6
		light.position = Vector3(cos(angle) * r * 0.9, r * 0.05, sin(angle) * r * 0.9)
		_add_visual_child(light)

	name_label.position = Vector3(0, r * 1.0, 0)


func _metal_material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.metallic = 0.85
	mat.roughness = 0.4
	return mat


func _emissive_material(color: Color, energy: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = energy
	return mat


func _add_box(size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	node.mesh = mesh
	node.material_override = mat
	node.position = pos
	_add_visual_child(node)
	return node


func _add_cylinder(radius: float, height: float, pos: Vector3, mat: Material) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	node.mesh = mesh
	node.material_override = mat
	node.position = pos
	_add_visual_child(node)
	return node


func _add_torus(inner: float, outer: float, pos: Vector3, mat: Material) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := TorusMesh.new()
	mesh.inner_radius = inner
	mesh.outer_radius = outer
	node.mesh = mesh
	node.material_override = mat
	node.position = pos
	_add_visual_child(node)
	return node


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


func _star_color() -> Color:
	return star_color_for(poi_class)


## Approximate color of a star from the first letter of its spectral class.
static func star_color_for(spectral_class: String) -> Color:
	var spectral := spectral_class.left(1).to_upper() if not spectral_class.is_empty() else ""
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
