extends GdUnitTestSuite

# Tests for system_renderer.gd travel animation logic and coordinate transforms.

const SHIP_SCENE := preload("res://scenes/game/ship.tscn")

var _renderer: Node3D


func before_test() -> void:
	StateManager.player = {"id": "p1", "name": "TestPilot"}
	StateManager.ship = {"hull": 100, "max_hull": 100}
	StateManager.location = {"poi_id": "poi_001", "position": {"x": 1.0, "y": 2.0}}
	StateManager.current_system = {
		"id": "sys_001",
		"name": "Sol",
		"pois": [
			{"id": "poi_001", "name": "Earth", "type": "planet", "position": {"x": 1.0, "y": 2.0}},
			{"id": "poi_002", "name": "Mars", "type": "planet", "position": {"x": 5.0, "y": 8.0}},
		]
	}
	StateManager.nearby_players = []
	StateManager.nearby_pirates = []
	StateManager.travel_dest_poi_id = ""
	StateManager.travel_dest_poi_name = ""
	StateManager.travel_origin_poi_id = ""
	StateManager.set("is_traveling", false)
	_renderer = null


func after_test() -> void:
	if _renderer and is_instance_valid(_renderer):
		_renderer.queue_free()
	StateManager.reset()


func _make_renderer() -> Node3D:
	var r := Node3D.new()
	r.set_script(load("res://scripts/game/system_renderer.gd"))
	add_child(r)
	_renderer = r
	return r


func _add_player_ship(renderer: Node3D, pos: Vector3) -> Node3D:
	var ship: Node3D = SHIP_SCENE.instantiate()
	renderer.add_child(ship)
	ship.setup("p1", "TestPilot", pos, true)
	renderer._ships["p1"] = ship
	return ship


# --- Coordinate transform ---

func test_poi_position_to_world_scales_correctly() -> void:
	var renderer := _make_renderer()
	var result: Vector3 = renderer._poi_position_to_world({"x": 1.0, "y": 2.0})
	# SCALE = 30.0, x maps to x, y maps to z
	assert_float(result.x).is_equal_approx(30.0, 0.01)
	assert_float(result.y).is_equal_approx(0.0, 0.01)
	assert_float(result.z).is_equal_approx(60.0, 0.01)


func test_poi_position_to_world_empty_dict() -> void:
	var renderer := _make_renderer()
	var result: Vector3 = renderer._poi_position_to_world({})
	assert_float(result.x).is_equal_approx(0.0, 0.01)
	assert_float(result.z).is_equal_approx(0.0, 0.01)


# --- Travel animation state ---

func test_travel_started_sets_animation_state() -> void:
	var renderer := _make_renderer()
	var ship := _add_player_ship(renderer, Vector3(30.0, 0.0, 60.0))

	renderer._on_travel_started("poi_002", "Mars")

	assert_bool(renderer._is_animating_travel).is_true()
	assert_float(renderer._travel_elapsed).is_equal_approx(0.0, 0.001)
	# Origin should be ship's current position
	assert_float(renderer._travel_origin_pos.x).is_equal_approx(30.0, 0.1)
	# Dest should be Mars position (5.0 * 30 = 150, 8.0 * 30 = 240)
	assert_float(renderer._travel_dest_pos.x).is_equal_approx(150.0, 0.1)
	assert_float(renderer._travel_dest_pos.z).is_equal_approx(240.0, 0.1)
	# Path line should be created
	assert_that(renderer._travel_path_line).is_not_null()


func test_travel_started_skips_negligible_distance() -> void:
	var renderer := _make_renderer()
	_add_player_ship(renderer, Vector3(30.0, 0.0, 60.0))

	# Travel to same POI (poi_001) — distance < 1.0
	renderer._on_travel_started("poi_001", "Earth")

	assert_bool(renderer._is_animating_travel).is_false()


func test_travel_ended_clears_animation_state() -> void:
	var renderer := _make_renderer()
	_add_player_ship(renderer, Vector3(30.0, 0.0, 60.0))

	renderer._on_travel_started("poi_002", "Mars")
	assert_bool(renderer._is_animating_travel).is_true()

	# End travel — update location to Mars first
	StateManager.location = {"poi_id": "poi_002", "position": {"x": 5.0, "y": 8.0}}
	renderer._on_travel_ended()

	assert_bool(renderer._is_animating_travel).is_false()
	assert_that(renderer._travel_path_line).is_null()


func test_travel_aborted_snaps_back_to_origin() -> void:
	var renderer := _make_renderer()
	var ship := _add_player_ship(renderer, Vector3(30.0, 0.0, 60.0))

	renderer._on_travel_started("poi_002", "Mars")
	# Simulate some elapsed time by moving the ship
	ship.global_position = Vector3(80.0, 0.0, 120.0)

	renderer._on_travel_aborted("poi_001")

	assert_bool(renderer._is_animating_travel).is_false()
	# Ship should be back at origin position
	assert_float(ship.global_position.x).is_equal_approx(30.0, 0.1)
	assert_float(ship.global_position.z).is_equal_approx(60.0, 0.1)


# --- Guards ---

func test_update_player_ship_guarded_during_travel() -> void:
	var renderer := _make_renderer()
	var ship := _add_player_ship(renderer, Vector3(30.0, 0.0, 60.0))

	renderer._on_travel_started("poi_002", "Mars")
	ship.global_position = Vector3(80.0, 0.0, 120.0)

	# _update_player_ship should be guarded and NOT move the ship
	renderer._update_player_ship()
	assert_float(ship.global_position.x).is_equal_approx(80.0, 0.1)


func test_update_player_ship_works_when_not_traveling() -> void:
	var renderer := _make_renderer()
	var ship := _add_player_ship(renderer, Vector3(0.0, 0.0, 0.0))

	# Not traveling — _update_player_ship should move ship to player position
	renderer._update_player_ship()
	# Player location is poi_001 at (1.0, 2.0) → world (30.0, 0.0, 60.0)
	assert_float(ship.global_position.x).is_equal_approx(30.0, 1.0)
	assert_float(ship.global_position.z).is_equal_approx(60.0, 1.0)


# --- Asymptotic progress math ---

func test_asymptotic_progress_at_10s() -> void:
	var progress := 1.0 - exp(-0.08 * 10.0)
	assert_float(progress).is_greater(0.50)
	assert_float(progress).is_less(0.60)


func test_asymptotic_progress_at_30s() -> void:
	var progress := 1.0 - exp(-0.08 * 30.0)
	assert_float(progress).is_greater(0.88)
	assert_float(progress).is_less(0.95)


func test_asymptotic_progress_capped_at_95pct() -> void:
	var raw := 1.0 - exp(-0.08 * 120.0)
	var capped := minf(raw, 0.95)
	assert_float(capped).is_equal_approx(0.95, 0.001)


# --- Location changed guard ---

func test_location_changed_preserves_player_ship_during_travel() -> void:
	var renderer := _make_renderer()
	var ship := _add_player_ship(renderer, Vector3(80.0, 0.0, 120.0))

	# Add another ship
	var other_ship: Node3D = SHIP_SCENE.instantiate()
	renderer.add_child(other_ship)
	other_ship.setup("p2", "Other", Vector3(30.0, 0.0, 60.0), false)
	renderer._ships["p2"] = other_ship

	renderer._on_travel_started("poi_002", "Mars")

	# Location changes — other ship should be removed, player ship untouched
	renderer._on_location_changed("poi_001", "poi_002")

	assert_bool(renderer._ships.has("p1")).is_true()
	assert_bool(renderer._ships.has("p2")).is_false()
	assert_float(ship.global_position.x).is_equal_approx(80.0, 0.1)


# --- Click detection (raycast math) ---

func test_poi_selection_via_signal() -> void:
	var renderer := _make_renderer()
	# Manually create a POI marker
	var marker_scene := preload("res://scenes/game/poi_marker.tscn")
	var marker: Node3D = marker_scene.instantiate()
	renderer.add_child(marker)
	marker.setup("poi_002", "Mars", "planet", Vector3(150.0, 0.0, 240.0))
	renderer._poi_markers["poi_002"] = marker

	# Trigger selection directly (simulates what raycast does)
	renderer._on_poi_marker_selected(marker)

	assert_str(renderer._selected_poi_id).is_equal("poi_002")
	assert_bool(marker.is_selected).is_true()

	# Toggle off
	renderer._on_poi_marker_selected(marker)
	assert_str(renderer._selected_poi_id).is_equal("")
	assert_bool(marker.is_selected).is_false()
	marker.queue_free()
