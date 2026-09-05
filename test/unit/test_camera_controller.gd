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


func test_face_direction_puts_camera_behind_the_target_along_that_direction() -> void:
	var camera: Camera3D = load("res://scripts/game/camera_controller.gd").new()
	var target := Node3D.new()
	add_child(camera)
	add_child(target)
	target.global_position = Vector3.ZERO
	camera.follow(target)
	camera.face_direction(Vector3(1.0, 0.0, 0.0))
	# Looking along +X means the camera sits on the -X side of the target
	assert_float(camera.global_position.x).is_less(-1.0)
	assert_float(absf(camera.global_position.z)).is_less(1.0)
	var forward := -camera.global_transform.basis.z
	assert_float(forward.x).is_greater(0.5)
	camera.face_direction(Vector3.ZERO)  # no-op, must not error
	camera.queue_free()
	target.queue_free()
