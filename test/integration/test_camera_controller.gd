extends GdUnitTestSuite

# Integration tests for camera_controller.gd
# Verifies position, rotation, zoom, orbit, and pitch via scene runner.

var _runner: GdUnitSceneRunner
var _camera: Camera3D
var _target: Node3D


func before_test() -> void:
	_runner = scene_runner("res://scenes/game/game_view.tscn")
	_camera = _runner.scene().find_child("Camera3D", true, false) as Camera3D
	# Create a dummy target at the origin
	_target = Node3D.new()
	_target.name = "TestTarget"
	_runner.scene().add_child(_target)
	_target.global_position = Vector3.ZERO


func after_test() -> void:
	_target = null
	_camera = null


## Helper: right-click drag from one position to another.
## Includes the "warm-up" move that gets skipped by the camera controller.
func _right_drag(from: Vector2, to: Vector2) -> void:
	_runner.simulate_mouse_move(from)
	await _runner.simulate_frames(1)
	_runner.simulate_mouse_button_press(MOUSE_BUTTON_RIGHT)
	# First move after press is skipped (resets relative baseline)
	_runner.simulate_mouse_move(from)
	await _runner.simulate_frames(1)
	# Now the actual drag
	_runner.simulate_mouse_move(to)
	await _runner.simulate_frames(1)
	_runner.simulate_mouse_button_release(MOUSE_BUTTON_RIGHT)
	await _runner.simulate_frames(1)


# --- Initial state ---

func test_camera_exists() -> void:
	assert_object(_camera).is_not_null()
	assert_bool(_camera.has_method("follow")).is_true()


func test_camera_snaps_on_first_follow() -> void:
	_target.global_position = Vector3(10.0, 0.0, 5.0)
	_camera.follow(_target)
	await _runner.simulate_frames(1)
	# Spherical coords: orbit=0, tilt=0.4, zoom=20
	# height = cos(0.4)*20 ≈ 18.4, horiz = sin(0.4)*20 ≈ 7.8
	# expected ~(10, 18.4, 5 + 7.8) = (10, 18.4, 12.8)
	assert_float(_camera.global_position.x).is_equal_approx(10.0, 1.0)
	assert_float(_camera.global_position.y).is_equal_approx(18.4, 1.0)
	assert_float(_camera.global_position.z).is_equal_approx(12.8, 1.0)


func test_camera_no_jump_when_target_at_default_offset() -> void:
	# Camera scene default is (0, 18.4, 7.8). Target at origin with default
	# tilt should produce ~(0, 18.42, 7.79). No visible jump.
	_target.global_position = Vector3.ZERO
	var pos_before := _camera.global_position
	_camera.follow(_target)
	await _runner.simulate_frames(1)
	var pos_after := _camera.global_position
	# Should be very close to the scene default — no visible jump
	assert_float(pos_after.distance_to(pos_before)).is_less(1.0)


func test_camera_follows_target_at_origin() -> void:
	_target.global_position = Vector3.ZERO
	_camera.follow(_target)
	await _runner.simulate_frames(10)
	# Spherical: height=cos(0.4)*20≈18.42, horiz=sin(0.4)*20≈7.79
	assert_float(_camera.global_position.x).is_equal_approx(0.0, 0.5)
	assert_float(_camera.global_position.y).is_equal_approx(18.4, 0.5)
	assert_float(_camera.global_position.z).is_equal_approx(7.8, 0.5)


func test_camera_height_always_positive() -> void:
	_target.global_position = Vector3.ZERO
	_camera.follow(_target)
	await _runner.simulate_frames(3)
	assert_float(_camera.global_position.y).is_greater(0.0)


# --- Zoom ---

func test_scroll_up_decreases_zoom() -> void:
	_camera.follow(_target)
	await _runner.simulate_frames(10)
	var y_before := _camera.global_position.y

	_runner.simulate_mouse_button_pressed(MOUSE_BUTTON_WHEEL_UP)
	await _runner.simulate_frames(30)

	assert_float(_camera.global_position.y).is_less(y_before)


func test_scroll_down_increases_zoom() -> void:
	_camera.follow(_target)
	await _runner.simulate_frames(10)
	var y_before := _camera.global_position.y

	_runner.simulate_mouse_button_pressed(MOUSE_BUTTON_WHEEL_DOWN)
	await _runner.simulate_frames(30)

	assert_float(_camera.global_position.y).is_greater(y_before)


func test_zoom_clamped_at_minimum() -> void:
	_camera.follow(_target)
	await _runner.simulate_frames(3)
	for i in 50:
		_runner.simulate_mouse_button_pressed(MOUSE_BUTTON_WHEEL_UP)
	await _runner.simulate_frames(30)
	# Spherical: min height = cos(tilt) * ZOOM_MIN ≈ cos(0.4) * 5 ≈ 4.6
	assert_float(_camera.global_position.y).is_greater_equal(4.0)


func test_zoom_clamped_at_maximum() -> void:
	_camera.follow(_target)
	await _runner.simulate_frames(3)
	for i in 50:
		_runner.simulate_mouse_button_pressed(MOUSE_BUTTON_WHEEL_DOWN)
	await _runner.simulate_frames(30)
	# Spherical: max height = cos(tilt) * ZOOM_MAX ≈ cos(0.4) * 80 ≈ 73.7
	assert_float(_camera.global_position.y).is_less_equal(75.0)


func test_zoom_is_smooth_not_instant() -> void:
	_camera.follow(_target)
	await _runner.simulate_frames(15)
	var y_before := _camera.global_position.y

	_runner.simulate_mouse_button_pressed(MOUSE_BUTTON_WHEEL_UP)
	await _runner.simulate_frames(1)
	var y_mid := _camera.global_position.y
	await _runner.simulate_frames(30)
	var y_after := _camera.global_position.y

	# Mid should be between before and after
	assert_float(y_mid).is_less(y_before)
	assert_float(y_mid).is_greater(y_after)


# --- Horizontal orbit ---

func test_right_drag_horizontal_orbits_camera() -> void:
	_camera.follow(_target)
	await _runner.simulate_frames(10)
	var x_before := _camera.global_position.x

	# Drag to the right
	await _right_drag(Vector2(400, 300), Vector2(600, 300))
	await _runner.simulate_frames(5)

	# Camera X should change (orbited)
	assert_float(_camera.global_position.x).is_not_equal(x_before)


func test_orbit_preserves_height() -> void:
	_camera.follow(_target)
	await _runner.simulate_frames(15)
	var y_before := _camera.global_position.y

	await _right_drag(Vector2(400, 300), Vector2(600, 300))
	await _runner.simulate_frames(5)

	assert_float(_camera.global_position.y).is_equal_approx(y_before, 0.5)


func test_orbit_preserves_distance_from_target() -> void:
	_camera.follow(_target)
	await _runner.simulate_frames(15)
	var dist_before := Vector2(_camera.global_position.x, _camera.global_position.z).length()

	await _right_drag(Vector2(400, 300), Vector2(600, 300))
	await _runner.simulate_frames(5)

	var dist_after := Vector2(_camera.global_position.x, _camera.global_position.z).length()
	# Horizontal distance from target should be approximately preserved
	assert_float(dist_after).is_equal_approx(dist_before, 1.0)


func test_small_drag_produces_small_orbit() -> void:
	_camera.follow(_target)
	await _runner.simulate_frames(15)
	var pos_before := _camera.global_position

	# Small drag: 20 pixels
	await _right_drag(Vector2(400, 300), Vector2(420, 300))
	await _runner.simulate_frames(5)

	# Camera should have moved, but only slightly
	var delta := _camera.global_position.distance_to(pos_before)
	assert_float(delta).is_less(5.0)
	assert_float(delta).is_greater(0.01)


# --- Vertical pitch ---

func test_drag_down_increases_horizontal_distance() -> void:
	_camera.follow(_target)
	await _runner.simulate_frames(15)
	var z_before := _camera.global_position.z

	# Drag downward — increases tilt = more horizontal = farther back
	await _right_drag(Vector2(400, 300), Vector2(400, 500))
	await _runner.simulate_frames(5)

	assert_float(_camera.global_position.z).is_greater(z_before)


func test_drag_up_decreases_horizontal_distance() -> void:
	_camera.follow(_target)
	await _runner.simulate_frames(15)
	var z_before := _camera.global_position.z

	# Drag upward — decreases tilt = more top-down = closer
	await _right_drag(Vector2(400, 300), Vector2(400, 100))
	await _runner.simulate_frames(5)

	assert_float(_camera.global_position.z).is_less(z_before)


# --- Camera looks downward at a meaningful angle ---

func test_camera_looks_downward() -> void:
	_camera.follow(_target)
	await _runner.simulate_frames(15)
	var forward := -_camera.global_transform.basis.z
	assert_float(forward.y).is_less(0.0)


func test_camera_looks_downward_after_orbit() -> void:
	_camera.follow(_target)
	await _runner.simulate_frames(10)

	await _right_drag(Vector2(400, 300), Vector2(600, 300))
	await _runner.simulate_frames(5)

	var forward := -_camera.global_transform.basis.z
	assert_float(forward.y).is_less(0.0)


func test_camera_has_meaningful_view_angle() -> void:
	# The camera should look toward the target at a significant angle,
	# not nearly straight down. With default tilt=0.4, the angle from
	# vertical should be ~22 degrees (forward has a horizontal component).
	_camera.follow(_target)
	await _runner.simulate_frames(15)
	var forward := -_camera.global_transform.basis.z
	var horiz_magnitude := Vector2(forward.x, forward.z).length()
	# At tilt=0.4, horiz_magnitude should be ~0.37 (sin(21.8°))
	# It should NOT be ~0.1 (which would be nearly straight down)
	assert_float(horiz_magnitude).is_greater(0.2)


# --- Home key ---

func test_home_key_resets_orbit() -> void:
	_camera.follow(_target)
	await _runner.simulate_frames(10)

	await _right_drag(Vector2(400, 300), Vector2(700, 300))
	await _runner.simulate_frames(5)

	_runner.simulate_key_pressed(KEY_HOME)
	await _runner.simulate_frames(60)

	assert_float(_camera.global_position.x).is_equal_approx(0.0, 0.5)


# --- No NaN ---

func test_no_nan_after_extreme_zoom() -> void:
	_camera.follow(_target)
	await _runner.simulate_frames(3)
	for i in 100:
		_runner.simulate_mouse_button_pressed(MOUSE_BUTTON_WHEEL_UP)
	await _runner.simulate_frames(10)
	assert_bool(is_nan(_camera.global_position.x)).is_false()
	assert_bool(is_nan(_camera.global_position.y)).is_false()
	assert_bool(is_nan(_camera.global_position.z)).is_false()


func test_no_nan_after_extreme_rotation() -> void:
	_camera.follow(_target)
	await _runner.simulate_frames(3)
	_runner.simulate_mouse_button_press(MOUSE_BUTTON_RIGHT)
	_runner.simulate_mouse_move(Vector2(400, 300))
	await _runner.simulate_frames(1)
	for i in 20:
		_runner.simulate_mouse_move(Vector2(400.0 + i * 50.0, 300))
		await _runner.simulate_frames(1)
	_runner.simulate_mouse_button_release(MOUSE_BUTTON_RIGHT)
	await _runner.simulate_frames(5)
	assert_bool(is_nan(_camera.global_position.x)).is_false()
	assert_bool(is_nan(_camera.global_position.y)).is_false()
	assert_bool(is_nan(_camera.global_position.z)).is_false()


func test_no_nan_after_extreme_tilt() -> void:
	_camera.follow(_target)
	await _runner.simulate_frames(3)
	# Max tilt
	await _right_drag(Vector2(400, 100), Vector2(400, 900))
	await _runner.simulate_frames(5)
	assert_bool(is_nan(_camera.global_position.x)).is_false()
	assert_bool(is_nan(_camera.global_position.y)).is_false()
	assert_bool(is_nan(_camera.global_position.z)).is_false()
	# Min tilt
	await _right_drag(Vector2(400, 900), Vector2(400, 0))
	await _runner.simulate_frames(5)
	assert_bool(is_nan(_camera.global_position.x)).is_false()
	assert_bool(is_nan(_camera.global_position.y)).is_false()
	assert_bool(is_nan(_camera.global_position.z)).is_false()
