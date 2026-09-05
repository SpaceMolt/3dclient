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


func test_fallback_model_by_role_and_empire() -> void:
	assert_str(AssetLoader.fallback_model_id({"class": "Freighter", "empire": "nebula"})).is_equal("nebula_caravan")
	assert_str(AssetLoader.fallback_model_id({"class": "Fighter", "empire": "crimson"})).is_equal("solarian_axiom")
	assert_str(AssetLoader.fallback_model_id({"class": "Miner", "empire": "crimson"})).is_equal("shard")
	assert_str(AssetLoader.fallback_model_id({"class": "Ice Harvester", "empire": "unknown"})).is_equal("deeprock_harvester")
	assert_str(AssetLoader.fallback_model_id({})).is_empty()


func test_get_ship_scene_falls_back_for_catalog_ship_without_model() -> void:
	# A real catalog hull with no .glb of its own borrows a look-alike instead of the box placeholder
	var without_model := ""
	for ship_id in AssetLoader._ship_data_by_id:
		if not ResourceLoader.exists("res://assets/ships/%s.glb" % ship_id) and AssetLoader._ship_data_by_id[ship_id].get("class", "") == "Freighter":
			without_model = ship_id
			break
	assert_str(without_model).is_not_empty()
	var scene := AssetLoader.get_ship_scene(without_model)
	assert_object(scene).is_not_null()
	assert_str(scene.resource_path).ends_with("nebula_caravan.glb")
