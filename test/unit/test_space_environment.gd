extends GdUnitTestSuite

# The live scene and the offline POI gallery must render with the same environment,
# or the gallery stops being a preview of the game.

const ENV_PATH := "res://resources/space_environment.tres"


func test_game_and_gallery_scenes_share_the_space_environment() -> void:
	for scene_path in ["res://scenes/game/game_view.tscn", "res://scenes/test/visual_test.tscn"]:
		var scene: Node = (load(scene_path) as PackedScene).instantiate()
		var world_env := scene.get_node("WorldEnvironment") as WorldEnvironment
		assert_str(world_env.environment.resource_path).is_equal(ENV_PATH)
		# The renderer's floating origin keeps the camera near zero, which is what lets
		# directional shadow maps keep their precision at this world's scale.
		var sun := scene.get_node("SunLight") as DirectionalLight3D
		assert_bool(sun.shadow_enabled).is_true()
		scene.free()


func test_environment_lights_and_reflects_from_the_procedural_sky() -> void:
	var env: Environment = load(ENV_PATH)
	assert_int(env.ambient_light_source).is_equal(Environment.AMBIENT_SOURCE_SKY)
	assert_int(env.reflected_light_source).is_equal(Environment.REFLECTION_SOURCE_SKY)
	assert_that(env.sky.sky_material).is_instanceof(ShaderMaterial)
	assert_bool(env.glow_enabled).is_true()


func test_space_dust_lives_in_the_floating_world() -> void:
	# Dust must move with the world node, or every recenter step drags it along with the ship
	var scene: Node = (load("res://scenes/game/game_view.tscn") as PackedScene).instantiate()
	var dust := scene.get_node("Ships/SpaceDust") as GPUParticles3D
	assert_that(dust).is_not_null()
	assert_bool(dust.local_coords).is_true()
	scene.free()
