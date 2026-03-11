extends GdUnitTestSuite

# Tests for poi_marker.gd — setup, selection, appearance dispatch

const POI_MARKER_SCENE := preload("res://scenes/game/poi_marker.tscn")


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

func test_star_gets_emissive_material() -> void:
	var m := _make_marker("s1", "Sol", "sun", Vector3.ZERO, "G")
	# Stars should have emission enabled
	var mat: StandardMaterial3D = m.mesh_instance.material_override
	assert_bool(mat.emission_enabled).is_true()
	m.queue_free()


func test_station_gets_metallic_material() -> void:
	var m := _make_marker("st1", "Hub", "station", Vector3.ZERO)
	var mat: StandardMaterial3D = m.mesh_instance.material_override
	assert_float(mat.metallic).is_greater(0.5)
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
