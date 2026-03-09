extends GdUnitTestSuite

# Diagnostic tests that print actual camera state to understand behavior

var _runner: GdUnitSceneRunner
var _camera: Camera3D
var _target: Node3D


func before_test() -> void:
	_runner = scene_runner("res://scenes/game/game_view.tscn")
	_camera = _runner.scene().find_child("Camera3D", true, false) as Camera3D
	_target = Node3D.new()
	_target.name = "TestTarget"
	_runner.scene().add_child(_target)
	_target.global_position = Vector3.ZERO
	_camera.follow(_target)
	await _runner.simulate_frames(10)


func after_test() -> void:
	_target = null
	_camera = null


func _log_camera(label: String) -> void:
	var pos := _camera.global_position
	var fwd := -_camera.global_transform.basis.z
	var orbit: float = _camera._orbit
	var tilt: float = _camera._tilt
	print("  [%s] pos=(%.2f, %.2f, %.2f) fwd=(%.2f, %.2f, %.2f) orbit=%.3f tilt=%.3f" % [
		label, pos.x, pos.y, pos.z, fwd.x, fwd.y, fwd.z, orbit, tilt
	])


func test_orbit_state_dump() -> void:
	print("\n--- ORBIT STATE DUMP ---")
	_log_camera("INITIAL")

	# Drag right 100px
	_runner.simulate_mouse_move(Vector2(400, 300))
	await _runner.simulate_frames(1)
	_runner.simulate_mouse_button_press(MOUSE_BUTTON_RIGHT)
	_runner.simulate_mouse_move(Vector2(400, 300))  # skip-first event
	await _runner.simulate_frames(1)
	_log_camera("AFTER SKIP")

	_runner.simulate_mouse_move(Vector2(500, 300))  # actual drag: +100px X
	await _runner.simulate_frames(1)
	_log_camera("AFTER DRAG +100X")

	_runner.simulate_mouse_move(Vector2(600, 300))  # another +100px
	await _runner.simulate_frames(1)
	_log_camera("AFTER DRAG +200X")

	_runner.simulate_mouse_button_release(MOUSE_BUTTON_RIGHT)
	await _runner.simulate_frames(5)
	_log_camera("AFTER RELEASE")

	# Verify orbit actually changed
	var orbit_val: float = _camera._orbit
	print("  Final orbit value: %.4f radians (%.1f degrees)" % [orbit_val, rad_to_deg(orbit_val)])
	assert_float(absf(orbit_val)).is_greater(0.01)

	# Verify camera forward vector has a horizontal component
	# (proving camera is looking in a new direction, not just translated)
	var fwd := -_camera.global_transform.basis.z
	print("  Forward X component: %.4f (should be non-zero after orbit)" % fwd.x)
	assert_float(absf(fwd.x)).is_greater(0.001)

	print("--- END ORBIT STATE DUMP ---\n")


func test_tilt_state_dump() -> void:
	print("\n--- TILT STATE DUMP ---")
	_log_camera("INITIAL")

	# Drag down 200px
	_runner.simulate_mouse_move(Vector2(400, 300))
	await _runner.simulate_frames(1)
	_runner.simulate_mouse_button_press(MOUSE_BUTTON_RIGHT)
	_runner.simulate_mouse_move(Vector2(400, 300))  # skip-first
	await _runner.simulate_frames(1)

	_runner.simulate_mouse_move(Vector2(400, 500))  # drag down 200px
	await _runner.simulate_frames(1)
	_log_camera("AFTER DRAG DOWN")

	_runner.simulate_mouse_button_release(MOUSE_BUTTON_RIGHT)
	await _runner.simulate_frames(5)
	_log_camera("AFTER RELEASE")

	var tilt_val: float = _camera._tilt
	print("  Final tilt value: %.4f (default=0.4, should be > 0.4)" % tilt_val)
	assert_float(tilt_val).is_greater(0.4)

	print("--- END TILT STATE DUMP ---\n")


func test_full_360_orbit() -> void:
	print("\n--- FULL 360 ORBIT ---")
	_log_camera("START")

	# Need to orbit 2π radians. orbit -= relative.x * 0.005
	# So need total relative.x of 2π / 0.005 = 1257 pixels
	# Do it in 12 steps of ~105px each
	_runner.simulate_mouse_move(Vector2(400, 300))
	await _runner.simulate_frames(1)
	_runner.simulate_mouse_button_press(MOUSE_BUTTON_RIGHT)
	_runner.simulate_mouse_move(Vector2(400, 300))  # skip-first
	await _runner.simulate_frames(1)

	for i in 12:
		var x_pos := 400.0 + (i + 1) * 105.0
		_runner.simulate_mouse_move(Vector2(x_pos, 300))
		await _runner.simulate_frames(1)
		if i % 3 == 2:
			_log_camera("STEP %d" % (i + 1))

	_runner.simulate_mouse_button_release(MOUSE_BUTTON_RIGHT)
	await _runner.simulate_frames(5)
	_log_camera("END")

	var orbit_val: float = _camera._orbit
	print("  Final orbit: %.4f radians (%.1f degrees)" % [orbit_val, rad_to_deg(orbit_val)])

	# Camera should have orbited significantly
	# Check that we ended up near the start position (full circle)
	assert_float(_camera.global_position.x).is_equal_approx(0.0, 2.0)
	assert_float(_camera.global_position.z).is_equal_approx(8.0, 2.0)

	print("--- END FULL 360 ---\n")


func test_camera_forward_direction_changes_with_orbit() -> void:
	# This is the KEY test: after orbiting, the camera should face
	# a DIFFERENT direction, not just be at a different position
	var fwd_before := -_camera.global_transform.basis.z
	print("\n--- FORWARD DIRECTION TEST ---")
	print("  Before orbit: fwd=(%.4f, %.4f, %.4f)" % [fwd_before.x, fwd_before.y, fwd_before.z])

	# Small orbit: 50px right = 50 * 0.005 = 0.25 radians ≈ 14 degrees
	await _runner.simulate_frames(5)
	_runner.simulate_mouse_move(Vector2(400, 300))
	await _runner.simulate_frames(1)
	_runner.simulate_mouse_button_press(MOUSE_BUTTON_RIGHT)
	_runner.simulate_mouse_move(Vector2(400, 300))
	await _runner.simulate_frames(1)
	_runner.simulate_mouse_move(Vector2(450, 300))
	await _runner.simulate_frames(3)
	_runner.simulate_mouse_button_release(MOUSE_BUTTON_RIGHT)
	await _runner.simulate_frames(10)

	var fwd_after := -_camera.global_transform.basis.z
	print("  After orbit:  fwd=(%.4f, %.4f, %.4f)" % [fwd_after.x, fwd_after.y, fwd_after.z])

	# The X component of forward should have changed
	var x_change := absf(fwd_after.x - fwd_before.x)
	print("  Forward X change: %.4f" % x_change)
	assert_float(x_change).is_greater(0.001)

	print("--- END FORWARD DIRECTION TEST ---\n")
