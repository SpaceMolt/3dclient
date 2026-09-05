extends GdUnitTestSuite

# Tests for camera_controller.gd


func before_test() -> void:
	StateManager.player = {}
	StateManager.set("is_traveling", false)


func after_test() -> void:
	StateManager.reset()


func test_script_loads_successfully() -> void:
	var script: GDScript = load("res://scripts/game/camera_controller.gd")
	assert_that(script).is_not_null()
	assert_bool(script.can_instantiate()).is_true()


func test_snap_to_target_updates_camera_immediately() -> void:
	var camera: Camera3D = load("res://scripts/game/camera_controller.gd").new()
	var target := Node3D.new()
	add_child(camera)
	add_child(target)

	target.global_position = Vector3(100.0, 20.0, -50.0)
	camera.follow(target)
	camera.global_position = Vector3.ZERO

	camera.snap_to_target()

	assert_float(camera.global_position.distance_to(target.global_position)).is_equal_approx(camera.DEFAULT_ZOOM, 1.0)
	camera.queue_free()
	target.queue_free()
