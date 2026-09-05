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
const ATMOSPHERE_SHADER := preload("res://shaders/atmosphere.gdshader")
const STAR_SURFACE_SHADER := preload("res://shaders/star_surface.gdshader")
const STATION_MODEL := "res://assets/stations/sol_central.glb"  # Sol Central concept, Meshy image-to-3D
const ATMOSPHERE_SHELL := 1.05   # halo shell radius as a multiple of the planet radius
const BLINK_PERIOD := 1.6        # seconds between station approach-beacon flashes
const BLINK_ON := 0.12           # seconds each flash stays lit

var _blink_material: StandardMaterial3D = null
var _atmosphere: ShaderMaterial = null

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
	if _atmosphere:
		_atmosphere.set_shader_parameter("sun_dir", sun_direction_from_scene())
	match poi_type:
		"wormhole", "wormhole_entrance", "wormhole_exit", "jump_gate":
			rotate_y(_delta * 1.5)
		"gas_cloud", "nebula":
			rotate_y(_delta * 0.3)
		"station":
			rotate_y(_delta * 0.2)
			if _blink_material:
				_blink_material.emission_energy_multiplier = blink_energy(Time.get_ticks_msec() / 1000.0)
		"relic":
			rotate_y(_delta * 0.4)


## Direction towards the star, read from the nearest ancestor scene's SunLight. The live game
## view and the gallery scene both carry one; with none, light comes from straight above.
func sun_direction_from_scene() -> Vector3:
	var node := get_parent()
	while node:
		var sun := node.get_node_or_null("SunLight") as DirectionalLight3D
		if sun:
			return sun.global_transform.basis.z
		node = node.get_parent()
	return Vector3.UP


## Approach beacons flash briefly each period and sit dim in between.
static func blink_energy(time_s: float) -> float:
	return 4.0 if fmod(time_s, BLINK_PERIOD) < BLINK_ON else 0.5


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
	_beacon.pixel_size = 0.00015
	_beacon.modulate = beacon_color()
	add_child(_beacon)


## Radial white-to-transparent gradient, tinted by the sprite's modulate. 256 px so a
## corona scaled to thousands of units still has a smooth edge.
static func _glow_texture() -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1.0, 1.0, 1.0, 1.0))
	gradient.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(0.5, 0.0)
	texture.width = 256
	texture.height = 256
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
	var radius := FocusBubble.poi_radius(poi_type, poi_class)
	_fit_model_to_radius(model, radius)
	_matte_surfaces(model)
	_add_atmosphere(radius)
	mesh_instance.mesh = null
	mesh_instance.material_override = null
	mesh_instance.visible = false
	_uses_custom_model = true
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
	var color := _star_color()
	var mat := ShaderMaterial.new()
	mat.shader = STAR_SURFACE_SHADER
	mat.set_shader_parameter("star_color", color)
	mat.set_shader_parameter("energy", 1.3)  # granule peaks pass 1.0 and bloom; the limb stays readable
	mesh_instance.mesh = mesh
	mesh_instance.material_override = mat
	# The sun light is aimed from this very sphere, so as a caster it would eclipse the
	# whole system. Stars shed light; they never cast shadow.
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Corona: a soft billboard glow a few radii wide, so the star reads from across the system
	var corona := Sprite3D.new()
	corona.texture = _glow_texture()
	corona.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	corona.pixel_size = r * 3.5 / 256.0
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
	_add_atmosphere(r)
	# Label above the planet surface
	name_label.position = Vector3(0, r * 1.15, 0)
	name_label.font_size = 72


## Halo colour for a body; alpha carries the glow intensity and zero alpha means airless.
static func atmosphere_color_for(ptype: String, pclass: String) -> Color:
	if ptype == "moon":
		return Color(0, 0, 0, 0)
	match pclass:
		"oceanic", "terran", "super_terran":
			return Color(0.35, 0.6, 1.0, 1.6)
		"arid", "hothouse":
			return Color(0.9, 0.6, 0.35, 1.0)
		"tundra", "glacial", "ice_world":
			return Color(0.6, 0.8, 1.0, 1.0)
		"jovian", "hot_jupiter":
			return Color(0.85, 0.7, 0.5, 1.3)
		"sub_neptune", "ice_giant":
			return Color(0.4, 0.7, 1.0, 1.4)
		"lava_world", "scorched", "chthonian":
			return Color(1.0, 0.45, 0.15, 0.6)
		"carbon":
			return Color(0, 0, 0, 0)
		_:
			return Color(0.5, 0.65, 0.9, 0.8)


## Planet surfaces are rock, water, and cloud, not lacquer: a glossy material puts a
## star-shaped highlight on the disc, so every surface is made fully rough.
func _matte_surfaces(root: Node3D) -> void:
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var current: Node = stack.pop_back()
		stack.append_array(current.get_children())
		var mesh_node := current as MeshInstance3D
		if mesh_node == null or mesh_node.mesh == null:
			continue
		for i in mesh_node.mesh.get_surface_count():
			var mat := mesh_node.get_active_material(i) as BaseMaterial3D
			if mat:
				mat = mat.duplicate()
				# The scalar is a multiplier on the texture, so the texture has to go too
				mat.roughness_texture = null
				mat.metallic_texture = null
				mat.roughness = 1.0
				mat.metallic = 0.0
				mesh_node.set_surface_override_material(i, mat)


func _add_atmosphere(r: float) -> void:
	_atmosphere = null
	var tint := atmosphere_color_for(poi_type, poi_class)
	if tint.a <= 0.0:
		return
	var shell := MeshInstance3D.new()
	shell.name = "Atmosphere"
	var mesh := SphereMesh.new()
	mesh.radius = r * ATMOSPHERE_SHELL
	mesh.height = r * ATMOSPHERE_SHELL * 2.0
	mesh.radial_segments = 96
	mesh.rings = 48
	shell.mesh = mesh
	var mat := ShaderMaterial.new()
	mat.shader = ATMOSPHERE_SHADER
	mat.set_shader_parameter("atmo_color", Color(tint.r, tint.g, tint.b))
	mat.set_shader_parameter("intensity", tint.a)
	mat.set_shader_parameter("sun_dir", sun_direction_from_scene())
	shell.material_override = mat
	_atmosphere = mat
	_add_visual_child(shell)


func _make_station() -> void:
	var r: float = FocusBubble.poi_radius(poi_type, poi_class)
	var model := (load(STATION_MODEL) as PackedScene).instantiate() as Node3D
	_add_visual_child(model)
	_fit_model_to_radius(model, r)
	mesh_instance.mesh = null
	mesh_instance.material_override = null
	mesh_instance.visible = false
	_uses_custom_model = true

	# Approach beacons on the four arm tips, flashing orange, each with its own small light;
	# a cyan light over the hub picks out the sensor masts
	var half := _compute_model_aabb(model).size * 0.5 * model.scale.x
	var beacons := _emissive_material(ThemeColors.SHELL_ORANGE, 3.0)
	_blink_material = beacons
	var tips: Array[Vector3] = [Vector3(half.x, 0, 0), Vector3(-half.x, 0, 0), Vector3(0, 0, half.z), Vector3(0, 0, -half.z)]
	for i in tips.size():
		var tip := tips[i]
		var beacon := MeshInstance3D.new()
		beacon.name = "ApproachBeacon%d" % i
		var beacon_mesh := SphereMesh.new()
		beacon_mesh.radius = r * 0.02
		beacon_mesh.height = r * 0.04
		beacon.mesh = beacon_mesh
		beacon.material_override = beacons
		beacon.position = tip
		_add_visual_child(beacon)
		var light := OmniLight3D.new()
		light.light_color = ThemeColors.SHELL_ORANGE
		light.light_energy = 1.5
		light.omni_range = r * 0.5
		light.position = tip
		_add_visual_child(light)
	var hub_light := OmniLight3D.new()
	hub_light.light_color = ThemeColors.PLASMA_CYAN
	hub_light.light_energy = 2.0
	hub_light.omni_range = r * 0.9
	hub_light.position = Vector3(0, half.y * 1.5, 0)
	_add_visual_child(hub_light)

	name_label.position = Vector3(0, half.y * 1.4, 0)


## Painted hull plating: metallic enough to catch the star, rough enough to show a lit side
## and a shadow side instead of a mirror of the dark sky.
func _metal_material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.metallic = 0.55
	mat.roughness = 0.55
	return mat


func _emissive_material(color: Color, energy: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = energy
	return mat


func _add_box(size: Vector3, pos: Vector3, mat: Material, parent: Node3D = null) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	node.mesh = mesh
	node.material_override = mat
	node.position = pos
	if parent:
		parent.add_child(node)
	else:
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
	# A cluster of soft billboard puffs reads as a volume from every angle.
	var cloud_r: float = FocusBubble.poi_radius(poi_type, poi_class)
	var rng := RandomNumberGenerator.new()
	rng.seed = poi_name.hash()
	var palette: Array[Color] = [Color(0.55, 0.3, 0.9), Color(0.3, 0.45, 1.0), Color(0.8, 0.4, 0.9)]  # nebula: cool
	if poi_type == "gas_cloud":
		palette = [Color(1.0, 0.62, 0.25), Color(0.95, 0.45, 0.2), Color(1.0, 0.8, 0.45)]  # gas cloud: warm
	var texture := _glow_texture()
	for i in 36:
		var puff := Sprite3D.new()
		puff.texture = texture
		puff.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		puff.transparent = true
		var spread := sqrt(rng.randf())  # even fill of the disc, not a pile-up at the center
		var puff_r := cloud_r * lerpf(0.55, 0.2, spread)  # big soft puffs inside, small wisps at the rim
		puff.pixel_size = puff_r * 2.0 / 32.0
		var tint: Color = palette[i % palette.size()]
		puff.modulate = Color(tint, rng.randf_range(0.06, 0.16))
		# Flattened ellipsoid: wide and shallow
		var angle := rng.randf() * TAU
		puff.position = Vector3(cos(angle) * cloud_r * spread, rng.randf_range(-0.25, 0.25) * cloud_r * spread, sin(angle) * cloud_r * spread)
		_add_visual_child(puff)
	# Bright core so the cloud has a heart, and a light so ships inside pick up its color
	var core := SphereMesh.new()
	core.radius = cloud_r * 0.12
	core.height = cloud_r * 0.24
	var mat := _emissive_material(palette[0], 1.5)
	mat.albedo_color = Color(palette[0], 0.5)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh_instance.mesh = core
	mesh_instance.material_override = mat
	var light := OmniLight3D.new()
	light.light_color = palette[0]
	light.light_energy = 1.2
	light.omni_range = cloud_r * 1.5
	_add_visual_child(light)
	name_label.position = Vector3(0, cloud_r * 0.6, 0)


func _make_wormhole() -> void:
	# Two counter-tilted rings around a dark throat with a bright center: reads as a gate.
	var r: float = FocusBubble.poi_radius(poi_type, poi_class)
	var mesh := TorusMesh.new()
	mesh.inner_radius = r * 0.82
	mesh.outer_radius = r
	var mat := _emissive_material(ThemeColors.VOID_PURPLE, 2.5)
	mat.albedo_color = Color(ThemeColors.VOID_PURPLE, 0.85)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh_instance.mesh = mesh
	mesh_instance.material_override = mat
	var inner := _add_torus(r * 0.55, r * 0.66, Vector3.ZERO, _emissive_material(ThemeColors.BIO_GREEN, 2.0))
	inner.rotation = Vector3(0.35, 0.0, 0.2)
	var throat := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = r * 0.8
	disc.bottom_radius = r * 0.8
	disc.height = r * 0.02
	throat.mesh = disc
	var throat_mat := StandardMaterial3D.new()
	throat_mat.albedo_color = Color(0.02, 0.0, 0.06, 0.9)
	throat_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	throat_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	throat.material_override = throat_mat
	_add_visual_child(throat)
	var core := Sprite3D.new()
	core.texture = _glow_texture()
	core.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	core.pixel_size = r * 0.6 / 32.0
	core.modulate = Color(0.85, 0.95, 1.0, 0.7)
	core.render_priority = 2  # draw over the throat disc
	_add_visual_child(core)
	var light := OmniLight3D.new()
	light.light_color = ThemeColors.VOID_PURPLE
	light.light_energy = 2.5
	light.omni_range = r * 2.0
	_add_visual_child(light)
	name_label.position = Vector3(0, r * 1.1, 0)


func _make_relic() -> void:
	var r: float = FocusBubble.poi_radius(poi_type, poi_class)
	var hull := _metal_material(Color(0.28, 0.3, 0.36))
	hull.roughness = 0.3
	hull.emission_enabled = true
	hull.emission = Color(0.05, 0.25, 0.3)
	hull.emission_energy_multiplier = 0.35
	var runes := _emissive_material(ThemeColors.PLASMA_CYAN, 2.0)
	match poi_class:
		"megastructure":
			# A dark faceted core inside two great tilted rings etched with lit runes
			var core := SphereMesh.new()
			core.radius = r * 0.45
			core.height = r * 0.9
			core.radial_segments = 6
			core.rings = 3
			mesh_instance.mesh = core
			mesh_instance.material_override = hull
			for tilt in [0.0, 1.1]:
				var ring := _add_torus(r * 0.9, r, Vector3.ZERO, hull)
				ring.rotation = Vector3(tilt, 0.0, tilt * 0.5)
				for i in 16:
					var angle := TAU * i / 16.0
					var rune := _add_box(Vector3(r * 0.12, r * 0.05, r * 0.06), Vector3(cos(angle) * r * 0.95, 0.0, sin(angle) * r * 0.95), runes, ring)
					rune.rotation.y = -angle
		_:
			# A tumbling monolith with lit seams and a few fragments drifting around it
			var monolith := BoxMesh.new()
			monolith.size = Vector3(r * 0.35, r * 1.4, r * 0.35)
			mesh_instance.mesh = monolith
			mesh_instance.material_override = hull
			mesh_instance.rotation = Vector3(0.25, 0.0, 0.18)
			for y in [-0.45, 0.0, 0.45]:
				var seam := _add_box(Vector3(r * 0.37, r * 0.02, r * 0.37), Vector3(0.0, r * y, 0.0), runes)
				seam.rotation = mesh_instance.rotation
			var rng := RandomNumberGenerator.new()
			rng.seed = poi_name.hash()
			for i in 5:
				var angle := rng.randf() * TAU
				var dist := r * rng.randf_range(0.8, 1.3)
				var shard := _add_box(Vector3.ONE * r * rng.randf_range(0.05, 0.12), Vector3(cos(angle) * dist, rng.randf_range(-0.4, 0.4) * r, sin(angle) * dist), hull)
				shard.rotation = Vector3(rng.randf() * TAU, rng.randf() * TAU, 0.0)
	var light := OmniLight3D.new()
	light.light_color = ThemeColors.PLASMA_CYAN
	light.light_energy = 1.5
	light.omni_range = r * 2.0
	_add_visual_child(light)
	name_label.position = Vector3(0, r * 1.2, 0)


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
