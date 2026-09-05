extends GdUnitTestSuite

# Tests for system_renderer.gd continuous perspective, travel animation, and click detection.

const SHIP_SCENE := preload("res://scenes/game/ship.tscn")
const SystemRenderer := preload("res://scripts/game/system_renderer.gd")
var _renderer: Node3D


func before_test() -> void:
	StateManager.player = {"id": "p1", "name": "TestPilot"}
	StateManager.ship = {"hull": 100, "max_hull": 100}
	StateManager.location = {"poi_id": "poi_001", "position": {"x": 1.0, "y": 2.0}}
	StateManager.current_system = {
		"id": "sys_001",
		"name": "Sol",
		"pois": [
			{"id": "poi_001", "name": "Earth", "type": "planet", "class": "terran", "position": {"x": 1.0, "y": 2.0}},
			{"id": "poi_002", "name": "Mars", "type": "planet", "class": "arid", "position": {"x": 5.0, "y": 8.0}},
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


# --- Player ship placement ---

func test_world_recenters_on_the_player_ship() -> void:
	var renderer := _make_renderer()
	var ship := _add_player_ship(renderer, Vector3.ZERO)
	renderer._update_player_ship()
	# the ship keeps its true coordinates locally while the world shifts to put it at the origin
	var expected: Vector3 = renderer._ship_world_pos_for_poi("poi_001")
	assert_float(ship.position.distance_to(expected)).is_less(0.1)
	assert_float(ship.global_position.length()).is_less(0.01)
	assert_float(renderer.position.distance_to(-expected)).is_less(0.1)


func test_player_ship_placed_at_current_orbit() -> void:
	var renderer := _make_renderer()
	var ship := _add_player_ship(renderer, Vector3.ZERO)
	renderer._update_player_ship()
	var expected: Vector3 = renderer._ship_world_pos_for_poi("poi_001")
	assert_float(ship.position.x).is_equal_approx(expected.x, 0.1)
	assert_float(ship.position.y).is_equal_approx(expected.y, 0.1)
	assert_float(ship.position.z).is_equal_approx(expected.z, 0.1)


# --- POI positioning (stable world space) ---

func test_current_poi_stays_at_stable_world_position() -> void:
	var renderer := _make_renderer()
	_add_player_ship(renderer, Vector3.ZERO)
	renderer._sync_poi_markers()

	assert_bool(renderer._poi_markers.has("poi_001")).is_true()
	var marker: Node3D = renderer._poi_markers["poi_001"]
	var expected_pos: Vector3 = renderer._poi_world_pos(Vector2(1.0, 2.0))
	assert_float(marker.position.x).is_equal_approx(expected_pos.x, 0.1)
	assert_float(marker.position.y).is_equal_approx(expected_pos.y, 0.1)
	assert_float(marker.position.z).is_equal_approx(expected_pos.z, 0.1)
	assert_float(marker.scale.x).is_equal_approx(1.0, 0.01)


func test_distant_poi_keeps_stable_scale() -> void:
	var renderer := _make_renderer()
	_add_player_ship(renderer, Vector3.ZERO)
	renderer._sync_poi_markers()

	assert_bool(renderer._poi_markers.has("poi_002")).is_true()
	var marker: Node3D = renderer._poi_markers["poi_002"]

	assert_float(marker.scale.x).is_equal_approx(1.0, 0.01)
	var expected_pos: Vector3 = renderer._poi_world_pos(Vector2(5.0, 8.0))
	assert_float(marker.position.x).is_equal_approx(expected_pos.x, 0.1)
	assert_float(marker.position.z).is_equal_approx(expected_pos.z, 0.1)


func test_distant_poi_direction_correct() -> void:
	var renderer := _make_renderer()
	_add_player_ship(renderer, Vector3.ZERO)
	renderer._sync_poi_markers()

	var marker: Node3D = renderer._poi_markers["poi_002"]
	assert_float(marker.position.x).is_greater(0.0)
	assert_float(marker.position.z).is_greater(0.0)


# --- Travel animation state ---

func test_travel_started_sets_animation_state() -> void:
	var renderer := _make_renderer()
	var ship := _add_player_ship(renderer, Vector3.ZERO)
	renderer._sync_poi_markers()

	renderer._on_travel_started("poi_002", "Mars")

	assert_bool(renderer._is_animating_travel).is_true()
	assert_float(renderer._travel_elapsed).is_equal_approx(0.0, 0.001)
	assert_float(renderer._travel_origin_au.x).is_equal_approx(1.0, 0.01)
	assert_float(renderer._travel_origin_au.y).is_equal_approx(2.0, 0.01)
	assert_float(renderer._travel_dest_au.x).is_equal_approx(5.0, 0.01)
	assert_float(renderer._travel_dest_au.y).is_equal_approx(8.0, 0.01)
	assert_float(renderer._travel_ship_start_pos.distance_to(renderer._ship_world_pos_for_poi("poi_001"))).is_less(0.1)
	assert_float(renderer._travel_ship_end_pos.distance_to(renderer._ship_world_pos_for_poi("poi_002"))).is_less(0.1)
	assert_float(renderer._travel_align_duration).is_equal_approx(1.0, 0.001)
	assert_float(renderer._travel_move_duration).is_equal_approx(renderer._travel_duration - 1.0, 0.001)
	assert_float(renderer._travel_ship_start_basis.z.distance_to(ship.basis.z)).is_less(0.001)


func test_travel_started_skips_negligible_distance() -> void:
	var renderer := _make_renderer()
	_add_player_ship(renderer, Vector3.ZERO)
	renderer._sync_poi_markers()

	renderer._on_travel_started("poi_001", "Earth")

	assert_bool(renderer._is_animating_travel).is_false()


func test_travel_process_moves_ship_in_straight_line() -> void:
	var renderer := _make_renderer()
	var ship := _add_player_ship(renderer, Vector3.ZERO)
	renderer._sync_poi_markers()

	renderer._on_travel_started("poi_002", "Mars")
	var half_duration: float = renderer._travel_duration * 0.5
	renderer._process(half_duration)

	var expected_progress: float = SystemRenderer.travel_path_progress(
		half_duration, renderer._travel_duration, renderer._travel_align_duration)
	var expected_mid: Vector3 = renderer._travel_ship_start_pos.lerp(renderer._travel_ship_end_pos, expected_progress)
	assert_float(ship.position.x).is_equal_approx(expected_mid.x, 0.1)
	assert_float(ship.position.y).is_equal_approx(expected_mid.y, 0.1)
	assert_float(ship.position.z).is_equal_approx(expected_mid.z, 0.1)


func test_travel_holds_position_during_prelaunch_align() -> void:
	var renderer := _make_renderer()
	var ship := _add_player_ship(renderer, Vector3.ZERO)
	renderer._sync_poi_markers()
	renderer._on_travel_started("poi_002", "Mars")

	renderer._process(0.5)

	assert_float(ship.position.distance_to(renderer._travel_ship_start_pos)).is_less(0.1)


func test_travel_bends_around_primary_star() -> void:
	StateManager.location = {"poi_id": "poi_001", "position": {"x": 5.0, "y": 0.0}}
	StateManager.current_system = {
		"id": "sys_001",
		"name": "Sol",
		"pois": [
			{"id": "star_001", "name": "Sol", "type": "sun", "class": "G", "position": {"x": 0.0, "y": 0.0}},
			{"id": "poi_001", "name": "Earth", "type": "planet", "class": "terran", "position": {"x": 5.0, "y": 0.0}},
			{"id": "poi_002", "name": "Mars", "type": "planet", "class": "arid", "position": {"x": -5.0, "y": 0.0}},
		]
	}
	var renderer := _make_renderer()
	var ship := _add_player_ship(renderer, Vector3.ZERO)
	renderer._sync_poi_markers()
	renderer._on_travel_started("poi_002", "Mars")

	assert_bool(renderer._travel_uses_orbital_arc).is_true()

	var halfway_through_move: float = renderer._travel_align_duration + renderer._travel_move_duration * 0.5
	renderer._process(halfway_through_move)

	var star_world: Vector3 = renderer._poi_world_pos(Vector2.ZERO)
	assert_float(absf(ship.position.z)).is_greater(1000.0)
	assert_float(ship.position.distance_to(star_world)).is_greater(5500.0)
	assert_float(absf(ship.position.z)).is_less(20000.0)
	assert_float(renderer._travel_total_path_length).is_less(
		renderer._travel_ship_start_pos.distance_to(renderer._travel_ship_end_pos) * 1.2
	)


func test_travel_curve_accelerates_then_brakes() -> void:
	assert_float(SystemRenderer.travel_curve(0.0)).is_equal_approx(0.0, 0.001)
	assert_float(SystemRenderer.travel_curve(0.25)).is_equal_approx(0.125, 0.001)
	assert_float(SystemRenderer.travel_curve(0.5)).is_equal_approx(0.5, 0.001)
	assert_float(SystemRenderer.travel_curve(0.75)).is_equal_approx(0.875, 0.001)
	assert_float(SystemRenderer.travel_curve(1.0)).is_equal_approx(1.0, 0.001)


func test_travel_path_progress_waits_for_align_phase() -> void:
	assert_float(SystemRenderer.travel_path_progress(0.5, 10.0, 1.0)).is_equal_approx(0.0, 0.001)
	assert_float(SystemRenderer.travel_path_progress(1.0, 10.0, 1.0)).is_equal_approx(0.0, 0.001)
	assert_float(SystemRenderer.travel_path_progress(10.0, 10.0, 1.0)).is_equal_approx(1.0, 0.001)


func test_travel_progress_starts_slower_than_linear() -> void:
	var renderer := _make_renderer()
	var ship := _add_player_ship(renderer, Vector3.ZERO)
	renderer._sync_poi_markers()
	renderer._on_travel_started("poi_002", "Mars")

	var quarter_duration: float = renderer._travel_duration * 0.25
	renderer._process(quarter_duration)

	var linear_quarter: Vector3 = renderer._travel_ship_start_pos.lerp(renderer._travel_ship_end_pos, 0.25)
	assert_float(ship.position.distance_to(renderer._travel_ship_start_pos)).is_less(
		linear_quarter.distance_to(renderer._travel_ship_start_pos)
	)


func test_travel_keeps_destination_marker_fixed() -> void:
	var renderer := _make_renderer()
	_add_player_ship(renderer, Vector3.ZERO)
	renderer._sync_poi_markers()

	var mars_before: Vector3 = renderer._poi_markers["poi_002"].position

	renderer._on_travel_started("poi_002", "Mars")
	renderer._process(30.0)

	var mars_after: Vector3 = renderer._poi_markers["poi_002"].position
	assert_float(mars_before.x).is_equal_approx(mars_after.x, 0.01)
	assert_float(mars_before.y).is_equal_approx(mars_after.y, 0.01)
	assert_float(mars_before.z).is_equal_approx(mars_after.z, 0.01)


func test_travel_ended_snaps_ship_to_destination_orbit() -> void:
	var renderer := _make_renderer()
	var ship := _add_player_ship(renderer, Vector3.ZERO)
	renderer._sync_poi_markers()

	renderer._on_travel_started("poi_002", "Mars")
	renderer._process(renderer._travel_duration)

	StateManager.location = {"poi_id": "poi_002", "position": {"x": 5.0, "y": 8.0}}
	StateManager.travel_dest_poi_id = "poi_002"
	renderer._on_travel_ended()

	assert_bool(renderer._is_animating_travel).is_false()
	var expected_ship: Vector3 = renderer._ship_world_pos_for_poi("poi_002")
	assert_float(ship.position.distance_to(expected_ship)).is_less(0.1)
	var mars: Node3D = renderer._poi_markers["poi_002"]
	var expected: Vector3 = renderer._poi_world_pos(Vector2(5.0, 8.0))
	assert_float(mars.position.x).is_equal_approx(expected.x, 0.1)
	assert_float(mars.position.y).is_equal_approx(expected.y, 0.1)
	assert_float(mars.position.z).is_equal_approx(expected.z, 0.1)
	assert_float(mars.scale.x).is_equal_approx(1.0, 0.01)


func test_travel_aborted_snaps_to_origin() -> void:
	var renderer := _make_renderer()
	var ship := _add_player_ship(renderer, Vector3.ZERO)
	renderer._sync_poi_markers()

	renderer._on_travel_started("poi_002", "Mars")
	renderer._process(5.0)

	renderer._on_travel_aborted("poi_001")

	assert_bool(renderer._is_animating_travel).is_false()
	assert_float(ship.position.distance_to(renderer._ship_world_pos_for_poi("poi_001"))).is_less(0.1)


# --- Guards ---

func test_update_player_ship_guarded_during_travel() -> void:
	var renderer := _make_renderer()
	var ship := _add_player_ship(renderer, Vector3.ZERO)
	renderer._sync_poi_markers()

	renderer._on_travel_started("poi_002", "Mars")

	# _update_player_ship should be guarded during travel
	renderer._update_player_ship()
	assert_float(ship.position.distance_to(renderer._ship_world_pos_for_poi("poi_001"))).is_less(0.1)


func test_update_player_ship_works_when_not_traveling() -> void:
	var renderer := _make_renderer()
	var ship := _add_player_ship(renderer, Vector3(100.0, 0.0, 100.0))

	renderer._update_player_ship()
	assert_float(ship.position.distance_to(renderer._ship_world_pos_for_poi("poi_001"))).is_less(0.1)


# --- Travel duration formula ---

func test_travel_duration_computed_from_formula() -> void:
	var renderer := _make_renderer()
	_add_player_ship(renderer, Vector3.ZERO)
	renderer._sync_poi_markers()

	# Earth at (1,2), Mars at (5,8) — distance ~7.21 AU
	# Default ship speed = 1, tick_duration = 10s
	# ticks = ceil(7.21 / 1) = 8, duration = 8 * 10 = 80s
	renderer._on_travel_started("poi_002", "Mars")

	assert_float(renderer._travel_duration).is_greater(0.0)
	# Duration should be at least 1 tick of travel time
	assert_float(renderer._travel_duration).is_greater_equal(NetworkManager.tick_duration)


func test_travel_progress_advances_ship_toward_destination() -> void:
	var renderer := _make_renderer()
	var ship := _add_player_ship(renderer, Vector3.ZERO)
	renderer._sync_poi_markers()
	renderer._on_travel_started("poi_002", "Mars")

	var half_duration: float = renderer._travel_duration * 0.5
	renderer._process(half_duration)

	assert_float(ship.position.length()).is_greater(1.0)
	assert_float(ship.position.distance_to(renderer._travel_ship_end_pos)).is_greater(1.0)


func test_travel_progress_reaches_destination_orbit_before_confirmation() -> void:
	var renderer := _make_renderer()
	var ship := _add_player_ship(renderer, Vector3.ZERO)
	renderer._sync_poi_markers()
	renderer._on_travel_started("poi_002", "Mars")

	renderer._process(renderer._travel_duration)

	assert_float(ship.position.x).is_equal_approx(renderer._travel_ship_end_pos.x, 0.1)
	assert_float(ship.position.y).is_equal_approx(renderer._travel_ship_end_pos.y, 0.1)
	assert_float(ship.position.z).is_equal_approx(renderer._travel_ship_end_pos.z, 0.1)


# --- Location changed guard ---

func test_location_changed_preserves_player_ship_during_travel() -> void:
	var renderer := _make_renderer()
	_add_player_ship(renderer, Vector3.ZERO)
	renderer._sync_poi_markers()

	var other_ship: Node3D = SHIP_SCENE.instantiate()
	renderer.add_child(other_ship)
	other_ship.setup("p2", "Other", Vector3(5.0, 0.0, 5.0), false)
	renderer._ships["p2"] = other_ship

	renderer._on_travel_started("poi_002", "Mars")

	renderer._on_location_changed("poi_001", "poi_002")

	assert_bool(renderer._ships.has("p1")).is_true()
	assert_bool(renderer._ships.has("p2")).is_false()


func test_sync_poi_markers_ignored_during_travel() -> void:
	var renderer := _make_renderer()
	_add_player_ship(renderer, Vector3.ZERO)
	renderer._sync_poi_markers()
	renderer._on_travel_started("poi_002", "Mars")
	var mars_before: Vector3 = renderer._poi_markers["poi_002"].position

	StateManager.location = {"poi_id": "poi_002", "position": {"x": 5.0, "y": 8.0}}
	renderer._sync_poi_markers()

	var mars_after: Vector3 = renderer._poi_markers["poi_002"].position
	assert_float(mars_before.x).is_equal_approx(mars_after.x, 0.01)
	assert_float(mars_before.y).is_equal_approx(mars_after.y, 0.01)
	assert_float(mars_before.z).is_equal_approx(mars_after.z, 0.01)


# --- Click detection (raycast math) ---

var system_renderer_script: GDScript = load("res://scripts/game/system_renderer.gd")


func test_ray_point_distance_direct_hit() -> void:
	var origin := Vector3(0, 10, 0)
	var dir := Vector3(0, -1, 0)
	var point := Vector3(0, 0, 0)
	var result: Array = system_renderer_script.ray_point_distance(origin, dir, point)
	assert_float(result[0]).is_equal_approx(0.0, 0.01)
	assert_float(result[1]).is_equal_approx(10.0, 0.01)


func test_ray_point_distance_near_miss() -> void:
	var origin := Vector3(0, 10, 0)
	var dir := Vector3(0, -1, 0)
	var point := Vector3(2, 0, 0)
	var result: Array = system_renderer_script.ray_point_distance(origin, dir, point)
	assert_float(result[0]).is_equal_approx(2.0, 0.01)
	assert_float(result[1]).is_equal_approx(10.0, 0.01)


func test_ray_point_distance_behind_camera() -> void:
	var origin := Vector3(0, 10, 0)
	var dir := Vector3(0, -1, 0)
	var point := Vector3(0, 20, 0)
	var result: Array = system_renderer_script.ray_point_distance(origin, dir, point)
	assert_float(result[0]).is_less(0.0)


func test_ray_point_distance_angled_ray() -> void:
	var origin := Vector3(0, 20, 10)
	var dir := Vector3(0, -0.894, -0.447).normalized()
	var point := Vector3(0, 0, 0)
	var result: Array = system_renderer_script.ray_point_distance(origin, dir, point)
	assert_float(result[0]).is_less(1.0)
	assert_float(result[1]).is_greater(0.0)


func test_poi_selection_via_signal() -> void:
	var renderer := _make_renderer()
	var marker_scene := preload("res://scenes/game/poi_marker.tscn")
	var marker: Node3D = marker_scene.instantiate()
	renderer.add_child(marker)
	marker.setup("poi_002", "Mars", "planet", Vector3(3000.0, 0.0, 4000.0), "arid")
	renderer._poi_markers["poi_002"] = marker

	renderer._on_poi_marker_selected(marker)

	assert_str(renderer._selected_poi_id).is_equal("poi_002")
	assert_bool(marker.is_selected).is_true()

	renderer._on_poi_marker_selected(marker)
	assert_str(renderer._selected_poi_id).is_equal("")
	assert_bool(marker.is_selected).is_false()
	marker.queue_free()


# --- Nearby ship offset ---

func test_nearby_ship_offset_nonzero() -> void:
	var renderer := _make_renderer()
	var offset: Vector3 = renderer._nearby_ship_offset("player_abc")
	assert_float(offset.length()).is_greater(2.0)
	assert_float(offset.length()).is_less(15.0)
	assert_float(offset.y).is_equal_approx(0.0, 0.01)


func test_nearby_ship_offset_deterministic() -> void:
	var renderer := _make_renderer()
	var o1: Vector3 = renderer._nearby_ship_offset("player_xyz")
	var o2: Vector3 = renderer._nearby_ship_offset("player_xyz")
	assert_float(o1.x).is_equal_approx(o2.x, 0.001)
	assert_float(o1.z).is_equal_approx(o2.z, 0.001)


func test_station_ring_capacity_scales_with_circumference() -> void:
	assert_int(SystemRenderer._station_ring_capacity(50.0, 10.0)).is_equal(31)


func test_station_ring_layer_offsets_stack_above_and_below() -> void:
	assert_int(SystemRenderer._station_ring_layer_offset(0)).is_equal(0)
	assert_int(SystemRenderer._station_ring_layer_offset(1)).is_equal(1)
	assert_int(SystemRenderer._station_ring_layer_offset(2)).is_equal(-1)
	assert_int(SystemRenderer._station_ring_layer_offset(3)).is_equal(2)
	assert_int(SystemRenderer._station_ring_layer_offset(4)).is_equal(-2)


func test_station_ship_layout_uses_vertical_rings_when_capacity_exceeded() -> void:
	StateManager.location = {"poi_id": "poi_001", "poi_name": "Earth Station"}
	StateManager.current_system = {
		"pois": [
			{"id": "poi_001", "name": "Earth Station", "type": "station", "class": "", "position": {"x": 1.0, "y": 2.0}}
		]
	}
	var renderer := _make_renderer()
	var station_poi: Dictionary = StateManager.current_system["pois"][0]
	var ship_entries: Array[Dictionary] = []
	for i in range(120):
		ship_entries.append({
			"id": "ship_%03d" % i,
			"class_id": "theoria",
			"class_name": "Theoria",
		})

	var positions: Dictionary = renderer._station_ship_layout_positions(station_poi, ship_entries)
	var unique_y := {}
	for position_variant in positions.values():
		var position := position_variant as Vector3
		unique_y[str(position.y)] = true
	assert_int(positions.size()).is_equal(120)
	assert_int(unique_y.size()).is_greater(1)


func test_station_ship_layout_keeps_existing_berths_stable_when_ship_added() -> void:
	StateManager.location = {"poi_id": "poi_001", "poi_name": "Earth Station"}
	StateManager.current_system = {
		"pois": [
			{"id": "poi_001", "name": "Earth Station", "type": "station", "class": "", "position": {"x": 1.0, "y": 2.0}}
		]
	}
	var renderer := _make_renderer()
	var station_poi: Dictionary = StateManager.current_system["pois"][0]
	var initial_entries: Array[Dictionary] = [
		{"id": "ship_alpha", "class_id": "theoria", "class_name": "Theoria"},
		{"id": "ship_beta", "class_id": "theoria", "class_name": "Theoria"},
		{"id": "ship_gamma", "class_id": "theoria", "class_name": "Theoria"},
	]
	var expanded_entries: Array[Dictionary] = initial_entries.duplicate(true)
	expanded_entries.append({"id": "ship_delta", "class_id": "theoria", "class_name": "Theoria"})

	var initial_positions: Dictionary = renderer._station_ship_layout_positions(station_poi, initial_entries)
	var expanded_positions: Dictionary = renderer._station_ship_layout_positions(station_poi, expanded_entries)

	for ship_id in ["ship_alpha", "ship_beta", "ship_gamma"]:
		var initial_position: Vector3 = initial_positions[ship_id]
		var expanded_position: Vector3 = expanded_positions[ship_id]
		assert_float(initial_position.x).is_equal_approx(expanded_position.x, 0.001)
		assert_float(initial_position.y).is_equal_approx(expanded_position.y, 0.001)
		assert_float(initial_position.z).is_equal_approx(expanded_position.z, 0.001)


func test_belt_ship_layout_spreads_ships_around_field() -> void:
	StateManager.location = {"poi_id": "belt_001", "poi_name": "Main Belt"}
	StateManager.current_system = {
		"pois": [
			{"id": "belt_001", "name": "Main Belt", "type": "asteroid_belt", "class": "mixed", "position": {"x": 1.0, "y": 2.0}}
		]
	}
	StateManager.nearby_players = [
		{"player_id": "p2", "username": "PilotA"},
		{"player_id": "p3", "username": "PilotB"},
		{"player_id": "p4", "username": "PilotC"},
	]
	var renderer := _make_renderer()
	var positions: Dictionary = renderer._nearby_ship_layout_positions()
	assert_int(positions.size()).is_equal(3)
	var pos_a: Vector3 = positions["p2"]
	var pos_b: Vector3 = positions["p3"]
	var pos_c: Vector3 = positions["p4"]
	assert_float(pos_a.distance_to(pos_b)).is_greater(200.0)
	assert_float(pos_b.distance_to(pos_c)).is_greater(200.0)
	assert_float(pos_a.distance_to(pos_c)).is_greater(200.0)


# --- Player AU position resilience ---

func test_player_au_pos_without_location_position() -> void:
	StateManager.location = {"poi_id": "poi_001", "poi_name": "Earth"}
	var renderer := _make_renderer()
	_add_player_ship(renderer, Vector3.ZERO)
	renderer._sync_poi_markers()

	assert_bool(renderer._poi_markers.has("poi_002")).is_true()
	var marker: Node3D = renderer._poi_markers["poi_002"]
	assert_float(marker.position.x).is_equal_approx(renderer._poi_world_pos(Vector2(5.0, 8.0)).x, 0.1)


func test_co_located_poi_is_still_rendered() -> void:
	StateManager.current_system["pois"].append(
		{"id": "star_001", "name": "Sol", "type": "sun", "class": "G", "position": {"x": 1.0, "y": 2.0}}
	)
	var renderer := _make_renderer()
	_add_player_ship(renderer, Vector3.ZERO)
	renderer._sync_poi_markers()

	assert_bool(renderer._poi_markers.has("star_001")).is_true()


# --- HUD scene config: GameArea must not block 3D clicks ---

func test_game_area_has_mouse_filter_ignore() -> void:
	var hud_scene := load("res://scenes/ui/hud.tscn") as PackedScene
	var hud: Node = hud_scene.instantiate()
	var game_area: Control = hud.find_child("GameArea", true, false) as Control
	assert_that(game_area).is_not_null()
	assert_int(game_area.mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)
	hud.queue_free()


# --- Continuous perspective during travel ---

func test_recompute_positions_all_markers() -> void:
	var renderer := _make_renderer()
	_add_player_ship(renderer, Vector3.ZERO)
	renderer._sync_poi_markers()

	assert_bool(renderer._poi_markers["poi_001"].visible).is_true()
	assert_bool(renderer._poi_markers["poi_002"].visible).is_true()
	var earth: Node3D = renderer._poi_markers["poi_001"]
	var mars: Node3D = renderer._poi_markers["poi_002"]
	assert_float(earth.scale.x).is_equal_approx(1.0, 0.01)
	assert_float(mars.scale.x).is_equal_approx(1.0, 0.01)
	assert_float(earth.position.x).is_equal_approx(renderer._poi_world_pos(Vector2(1.0, 2.0)).x, 0.1)
	assert_float(mars.position.z).is_equal_approx(renderer._poi_world_pos(Vector2(5.0, 8.0)).z, 0.1)


# --- Sun light follows the system star ---

func test_sun_direction_is_normalized_and_zero_at_the_star() -> void:
	var d: Vector3 = SystemRenderer.sun_direction(Vector3.ZERO, Vector3(300.0, 0.0, 400.0))
	assert_float(d.length()).is_equal_approx(1.0, 0.001)
	assert_float(d.x).is_equal_approx(0.6, 0.001)
	assert_object(SystemRenderer.sun_direction(Vector3(5, 5, 5), Vector3(5, 5, 5))).is_equal(Vector3.ZERO)


func test_scene_sun_light_points_from_star_to_ship() -> void:
	var sun_light := DirectionalLight3D.new()
	sun_light.name = "SunLight"
	add_child(sun_light)
	StateManager.current_system["pois"].append({"id": "star", "name": "Sol", "type": "sun", "class": "K", "position": {"x": 0.0, "y": 0.0}})
	_renderer = _make_renderer()
	_renderer._sync_poi_markers()
	var star_pos := Vector3.ZERO
	var ship_pos: Vector3 = _renderer._current_ship_world_pos()
	var expected: Vector3 = SystemRenderer.sun_direction(star_pos, ship_pos)
	var light_dir: Vector3 = -sun_light.global_transform.basis.z
	assert_float(light_dir.dot(expected)).is_greater(0.999)
	assert_object(sun_light.light_color).is_equal(load("res://scripts/game/poi_marker.gd").star_color_for("K"))
	sun_light.queue_free()
