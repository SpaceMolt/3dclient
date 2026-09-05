extends GdUnitTestSuite

# Tests for poi_marker.gd — setup, selection, appearance dispatch

const POI_MARKER_SCENE := preload("res://scenes/game/poi_marker.tscn")
const FocusBubble := preload("res://scripts/game/focus_bubble.gd")


func _make_marker(id: String, pname: String, ptype: String, pos: Vector3, pclass: String = "") -> Node3D:
	var marker: Node3D = POI_MARKER_SCENE.instantiate()
	add_child(marker)
	marker.setup(id, pname, ptype, pos, pclass)
	return marker


# --- setup ---

func test_setup_sets_fields() -> void:
	var m := _make_marker("poi_001", "Earth", "planet", Vector3(10.0, 0.0, 20.0), "terran")
	assert_str(m.poi_id).is_equal("poi_001")
	assert_str(m.poi_name).is_equal("Earth")
	assert_str(m.poi_type).is_equal("planet")
	assert_str(m.poi_class).is_equal("terran")
	assert_float(m.global_position.x).is_equal_approx(10.0, 0.1)
	m.queue_free()


func test_setup_sets_label_text() -> void:
	var m := _make_marker("poi_001", "Mars Base", "station", Vector3.ZERO)
	assert_str(m.name_label.text).is_equal("Mars Base")
	m.queue_free()


# --- set_selected ---

func test_set_selected_true_changes_label_color() -> void:
	var m := _make_marker("poi_001", "Earth", "planet", Vector3.ZERO)
	m.set_selected(true)
	assert_bool(m.is_selected).is_true()
	# Yellow highlight
	assert_float(m.name_label.modulate.b).is_less(0.5)
	m.queue_free()


func test_set_selected_false_restores_label_color() -> void:
	var m := _make_marker("poi_001", "Earth", "planet", Vector3.ZERO)
	m.set_selected(true)
	m.set_selected(false)
	assert_bool(m.is_selected).is_false()
	# Back to cool white
	assert_float(m.name_label.modulate.b).is_greater(0.8)
	m.queue_free()


# --- _apply_appearance dispatch ---

func test_star_gets_glowing_surface_shader() -> void:
	var m := _make_marker("s1", "Sol", "sun", Vector3.ZERO, "G")
	var mat: ShaderMaterial = m.mesh_instance.material_override
	assert_that(mat.shader).is_equal(m.STAR_SURFACE_SHADER)
	assert_object(mat.get_shader_parameter("star_color")).is_equal(m._star_color())
	assert_float(mat.get_shader_parameter("energy")).is_greater(1.0)
	assert_int(m.mesh_instance.cast_shadow).is_equal(GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
	m.queue_free()


func test_station_model_follows_the_empire() -> void:
	var marker_script: GDScript = load("res://scripts/game/poi_marker.gd")
	assert_str(marker_script.station_model_path("crimson")).is_equal("res://assets/stations/crimson.glb")
	assert_str(marker_script.station_model_path("")).is_equal("res://assets/stations/solarian.glb")
	assert_str(marker_script.station_model_path("pirates")).is_equal("res://assets/stations/solarian.glb")
	for path in marker_script.STATION_MODELS.values():
		assert_bool(ResourceLoader.exists(path)).is_true()


func test_station_uses_a_capital_station_model() -> void:
	var m := _make_marker("st1", "Hub", "station", Vector3.ZERO)
	assert_bool(m._uses_custom_model).is_true()
	assert_bool(m.mesh_instance.visible).is_false()
	assert_int(m.find_children("*", "MeshInstance3D", true, false).size()).is_greater(4)
	m.queue_free()


func test_planet_varies_by_class() -> void:
	var ocean := _make_marker("p1", "Ocean", "planet", Vector3.ZERO, "oceanic")
	var desert := _make_marker("p2", "Desert", "planet", Vector3(10, 0, 0), "arid")
	assert_bool(ocean._uses_custom_model).is_true()
	assert_bool(desert._uses_custom_model).is_true()
	assert_bool(ocean.mesh_instance.visible).is_false()
	assert_bool(desert.mesh_instance.visible).is_false()
	ocean.queue_free()
	desert.queue_free()


func test_wormhole_is_transparent() -> void:
	var m := _make_marker("w1", "Gate", "wormhole", Vector3.ZERO)
	var mat: StandardMaterial3D = m.mesh_instance.material_override
	assert_int(mat.transparency).is_equal(BaseMaterial3D.TRANSPARENCY_ALPHA)
	m.queue_free()


func test_mesh_instance_is_mesh() -> void:
	var m := _make_marker("poi_001", "Earth", "planet", Vector3.ZERO)
	# MeshInstance3D doesn't have input_ray_pickable — only CollisionObject3D does
	assert_that(m.mesh_instance).is_instanceof(MeshInstance3D)
	m.queue_free()


func test_asteroid_uses_custom_model() -> void:
	var m := _make_marker("a1", "Belt", "asteroid", Vector3.ZERO, "metallic")
	assert_bool(m._uses_custom_model).is_true()
	assert_bool(m.mesh_instance.visible).is_false()
	m.queue_free()


func test_station_has_approach_beacons_on_every_arm() -> void:
	var m := _make_marker("st1", "Hub", "station", Vector3.ZERO)
	var beacons := m.find_children("ApproachBeacon*", "MeshInstance3D", false, false)
	assert_int(beacons.size()).is_equal(4)
	var r: float = FocusBubble.poi_radius("station", "")
	for beacon in beacons:
		assert_bool((beacon.material_override as StandardMaterial3D).emission_enabled).is_true()
		# each beacon sits out on an arm, not at the hub
		assert_float(beacon.position.length()).is_greater(r * 0.5)
	assert_int(m.find_children("*", "OmniLight3D", false, false).size()).is_equal(5)
	m.queue_free()


func test_labels_keep_screen_size_at_any_distance() -> void:
	var m := _make_marker("p1", "Far Planet", "planet", Vector3(1e5, 0, 0), "terran")
	assert_bool(m.name_label.fixed_size).is_true()
	assert_bool(m.name_label.no_depth_test).is_true()
	m.queue_free()


func test_every_marker_gets_a_beacon_colored_by_type() -> void:
	var station := _make_marker("st1", "Hub", "station", Vector3.ZERO)
	var star := _make_marker("s1", "Sol", "sun", Vector3.ZERO, "G")
	assert_object(station.get_node_or_null("Beacon")).is_instanceof(Sprite3D)
	assert_bool((station.get_node("Beacon") as Sprite3D).fixed_size).is_true()
	assert_object(station.beacon_color()).is_equal(ThemeColors.PLASMA_CYAN)
	assert_object(star.beacon_color()).is_equal(star._star_color())
	station.queue_free()
	star.queue_free()


# --- atmosphere and beacons ---

func test_atmosphere_color_depends_on_class() -> void:
	var marker_script: GDScript = load("res://scripts/game/poi_marker.gd")
	assert_float(marker_script.atmosphere_color_for("planet", "terran").a).is_greater(0.0)
	assert_float(marker_script.atmosphere_color_for("moon", "").a).is_equal(0.0)
	assert_float(marker_script.atmosphere_color_for("planet", "carbon").a).is_equal(0.0)
	var scorched: float = marker_script.atmosphere_color_for("planet", "scorched").a
	var oceanic: float = marker_script.atmosphere_color_for("planet", "oceanic").a
	assert_float(scorched).is_less(oceanic)


func test_planet_gets_atmosphere_shell_and_moon_does_not() -> void:
	var planet := _make_marker("p1", "Home", "planet", Vector3.ZERO, "terran")
	var moon := _make_marker("m1", "Rock", "moon", Vector3(10, 0, 0))
	var shell := planet.find_child("Atmosphere", true, false) as MeshInstance3D
	assert_that(shell).is_not_null()
	assert_that(shell.material_override).is_instanceof(ShaderMaterial)
	assert_that(moon.find_child("Atmosphere", true, false)).is_null()
	planet.queue_free()
	moon.queue_free()


func test_atmosphere_faces_the_scene_sun() -> void:
	var sun := DirectionalLight3D.new()
	sun.name = "SunLight"
	add_child(sun)
	sun.global_transform = Transform3D(Basis.looking_at(Vector3(-1, 0, 0), Vector3.UP), Vector3.ZERO)
	var planet := _make_marker("p1", "Home", "planet", Vector3.ZERO, "terran")
	var shell := planet.find_child("Atmosphere", true, false) as MeshInstance3D
	var toward_star: Vector3 = (shell.material_override as ShaderMaterial).get_shader_parameter("sun_dir")
	# light travels -X, so the star lies towards +X
	assert_float(toward_star.x).is_greater(0.99)
	sun.free()
	assert_vector(planet.sun_direction_from_scene()).is_equal(Vector3.UP)
	planet.queue_free()


func test_station_beacons_blink() -> void:
	var marker_script: GDScript = load("res://scripts/game/poi_marker.gd")
	assert_float(marker_script.blink_energy(0.05)).is_greater(marker_script.blink_energy(0.8))
	assert_float(marker_script.blink_energy(marker_script.BLINK_PERIOD + 0.05)).is_greater(marker_script.blink_energy(0.8))
	var m := _make_marker("st1", "Hub", "station", Vector3.ZERO)
	assert_that(m._blink_material).is_not_null()
	m.queue_free()
