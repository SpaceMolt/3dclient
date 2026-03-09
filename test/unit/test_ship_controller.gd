extends GdUnitTestSuite

# Tests for ship_controller.gd — movement, interpolation, travel

const SHIP_SCENE := preload("res://scenes/game/ship.tscn")


func _make_ship(pos: Vector3, is_own: bool = true) -> Node3D:
	var ship: Node3D = SHIP_SCENE.instantiate()
	add_child(ship)
	ship.setup("p1", "TestPilot", pos, is_own)
	return ship


# --- setup ---

func test_setup_sets_position_and_id() -> void:
	var ship := _make_ship(Vector3(10.0, 0.0, 20.0))
	assert_str(ship.player_id).is_equal("p1")
	assert_str(ship.player_name).is_equal("TestPilot")
	assert_bool(ship.is_player_ship).is_true()
	assert_float(ship.global_position.x).is_equal_approx(10.0, 0.1)
	assert_float(ship.global_position.z).is_equal_approx(20.0, 0.1)
	ship.queue_free()


func test_setup_initializes_prev_next_pos() -> void:
	var ship := _make_ship(Vector3(5.0, 0.0, 10.0))
	assert_float(ship._prev_pos.x).is_equal_approx(5.0, 0.1)
	assert_float(ship._next_pos.x).is_equal_approx(5.0, 0.1)
	assert_float(ship._tick_t).is_equal_approx(1.0, 0.01)
	ship.queue_free()


# --- move_to ---

func test_move_to_snaps_on_large_distance() -> void:
	var ship := _make_ship(Vector3(0.0, 0.0, 0.0))
	ship.move_to(Vector3(100.0, 0.0, 100.0))
	# Distance > 20 with no travel duration — should snap
	assert_float(ship.global_position.x).is_equal_approx(100.0, 0.1)
	assert_float(ship._tick_t).is_equal_approx(1.0, 0.01)
	ship.queue_free()


func test_move_to_snaps_from_zero_position() -> void:
	var ship := _make_ship(Vector3.ZERO)
	ship.move_to(Vector3(5.0, 0.0, 5.0))
	# From zero position with dist > 1.0 — should snap
	assert_float(ship.global_position.x).is_equal_approx(5.0, 0.1)
	assert_float(ship._tick_t).is_equal_approx(1.0, 0.01)
	ship.queue_free()


func test_move_to_interpolates_on_small_distance() -> void:
	var ship := _make_ship(Vector3(10.0, 0.0, 10.0))
	ship.move_to(Vector3(12.0, 0.0, 12.0))
	# Small distance — should set up interpolation
	assert_float(ship._tick_t).is_equal_approx(0.0, 0.01)
	assert_float(ship._prev_pos.x).is_equal_approx(10.0, 0.1)
	assert_float(ship._next_pos.x).is_equal_approx(12.0, 0.1)
	ship.queue_free()


# --- travel_to ---

func test_travel_to_sets_travel_duration() -> void:
	var ship := _make_ship(Vector3(10.0, 0.0, 10.0))
	ship.travel_to(Vector3(100.0, 0.0, 100.0))
	assert_float(ship._travel_duration).is_equal_approx(2.0, 0.01)
	assert_float(ship._tick_t).is_equal_approx(0.0, 0.01)
	assert_float(ship._next_pos.x).is_equal_approx(100.0, 0.1)
	ship.queue_free()


# --- set_selected ---

func test_set_selected_changes_label_color() -> void:
	var ship := _make_ship(Vector3.ZERO, false)
	ship.set_selected(true)
	assert_float(ship.name_label.modulate.r).is_equal_approx(1.0, 0.1)
	assert_float(ship.name_label.modulate.g).is_equal_approx(1.0, 0.1)
	# Yellow highlight
	assert_float(ship.name_label.modulate.b).is_less(0.5)
	ship.set_selected(false)
	# White
	assert_float(ship.name_label.modulate.b).is_equal_approx(1.0, 0.1)
	ship.queue_free()
