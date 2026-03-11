extends GdUnitTestSuite


func test_resolve_ship_class_id_normalizes_theoria_class_name() -> void:
	assert_str(AssetLoader.resolve_ship_class_id("", "Theoria")).is_equal("theoria")
	assert_str(AssetLoader.resolve_ship_class_id("", "Theoria Class")).is_equal("theoria")


func test_get_ship_scene_loads_theoria_model() -> void:
	var scene: PackedScene = AssetLoader.get_ship_scene("theoria")
	assert_that(scene).is_instanceof(PackedScene)


func test_resolve_ship_class_from_data_supports_ship_class_field() -> void:
	var resolved := AssetLoader.resolve_ship_class_from_data({"ship_class": "Theoria"})
	assert_str(resolved).is_equal("theoria")


func test_resolve_ship_class_from_data_supports_nested_ship_dictionary() -> void:
	var resolved := AssetLoader.resolve_ship_class_from_data({
		"username": "Pilot",
		"ship": {
			"ship_class": {
				"id": "theorem",
				"name": "Theorem",
			}
		}
	})
	assert_str(resolved).is_equal("theorem")


func test_get_ship_scene_loads_prospector_model() -> void:
	var scene: PackedScene = AssetLoader.get_ship_scene("prospector")
	assert_that(scene).is_instanceof(PackedScene)


func test_get_ship_scene_loads_canonical_scene_aliases() -> void:
	for class_id in ["archimedes", "axiom", "caravan", "liminal"]:
		var scene: PackedScene = AssetLoader.get_ship_scene(class_id)
		assert_that(scene).is_instanceof(PackedScene)


func test_get_ship_definition_loads_scale_from_catalog() -> void:
	var definition := AssetLoader.get_ship_definition("theoria")
	assert_int(int(definition.get("scale", 0))).is_equal(1)


func test_get_ship_scale_uses_catalog_alias_for_prospector() -> void:
	assert_float(AssetLoader.get_ship_scale("prospector")).is_equal(1.0)


func test_get_ship_scale_uses_catalog_aliases_for_scene_mapped_ships() -> void:
	assert_float(AssetLoader.get_ship_scale("archimedes")).is_equal(1.0)
	assert_float(AssetLoader.get_ship_scale("axiom")).is_equal(1.0)
	assert_float(AssetLoader.get_ship_scale("caravan")).is_equal(2.0)
	assert_float(AssetLoader.get_ship_scale("liminal")).is_equal(1.0)


func test_get_ship_world_span_uses_class_bands() -> void:
	assert_float(AssetLoader.get_ship_world_span("theoria")).is_equal(4.0)
	assert_float(AssetLoader.get_ship_world_span("caravan")).is_equal(8.0)
