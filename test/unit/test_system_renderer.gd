extends GdUnitTestSuite

# Tests for system_renderer.gd focus bubble integration, travel animation, and click detection.

const SHIP_SCENE := preload("res://scenes/game/ship.tscn")
const FocusBubble := preload("res://scripts/game/focus_bubble.gd")

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


# --- Player ship at origin ---

func test_player_ship_placed_at_origin() -> void:
	var renderer := _make_renderer()
	var ship := _add_player_ship(renderer, Vector3.ZERO)
	renderer._update_player_ship()
	# Ship should stay at origin in focus bubble
	assert_float(ship.global_position.x).is_equal_approx(0.0, 0.1)
	assert_float(ship.global_position.y).is_equal_approx(0.0, 0.1)
	assert_float(ship.global_position.z).is_equal_approx(0.0, 0.1)


# --- POI positioning (focus bubble) ---

func test_focused_poi_at_cinematic_offset() -> void:
	var renderer := _make_renderer()
	_add_player_ship(renderer, Vector3.ZERO)
	renderer._sync_poi_markers()

	# poi_001 is where the player is — should be rendered at focused offset
	assert_bool(renderer._poi_markers.has("poi_001")).is_true()
	var marker: Node3D = renderer._poi_markers["poi_001"]
	var expected_offset: Vector3 = FocusBubble.focused_poi_offset("planet", "terran")
	assert_float(marker.global_position.x).is_equal_approx(expected_offset.x, 1.0)
	assert_float(marker.global_position.y).is_equal_approx(expected_offset.y, 1.0)
	assert_float(marker.global_position.z).is_equal_approx(expected_offset.z, 1.0)
	assert_bool(marker.is_impostor).is_false()


func test_other_poi_is_impostor() -> void:
	var renderer := _make_renderer()
	_add_player_ship(renderer, Vector3.ZERO)
	renderer._sync_poi_markers()

	# poi_002 (Mars) is not the focused POI — should be an impostor
	assert_bool(renderer._poi_markers.has("poi_002")).is_true()
	var marker: Node3D = renderer._poi_markers["poi_002"]
	assert_bool(marker.is_impostor).is_true()

	# Should be at a compressed distance in the correct direction
	var dist: float = marker.global_position.length()
	assert_float(dist).is_greater(FocusBubble.SHELL_MIN)
	assert_float(dist).is_less_equal(FocusBubble.SHELL_MAX)


func test_impostor_direction_correct() -> void:
	var renderer := _make_renderer()
	_add_player_ship(renderer, Vector3.ZERO)
	renderer._sync_poi_markers()

	# Mars is at (5,8), player at (1,2), so delta is (4,6) — positive X and Z
	var marker: Node3D = renderer._poi_markers["poi_002"]
	assert_float(marker.global_position.x).is_greater(0.0)
	assert_float(marker.global_position.z).is_greater(0.0)


# --- Travel animation state ---

func test_travel_started_sets_animation_state() -> void:
	var renderer := _make_renderer()
	_add_player_ship(renderer, Vector3.ZERO)
	renderer._sync_poi_markers()

	renderer._on_travel_started("poi_002", "Mars")

	assert_bool(renderer._is_animating_travel).is_true()
	assert_float(renderer._travel_elapsed).is_equal_approx(0.0, 0.001)
	# Origin should be ship's position (origin)
	assert_float(renderer._travel_origin_pos.length()).is_less(1.0)
	# Dest should be Mars impostor position (compressed distance, positive X and Z)
	assert_float(renderer._travel_dest_pos.x).is_greater(0.0)
	assert_float(renderer._travel_dest_pos.z).is_greater(0.0)
	var dest_dist: float = renderer._travel_dest_pos.length()
	assert_float(dest_dist).is_greater(FocusBubble.SHELL_MIN)
	assert_float(dest_dist).is_less_equal(FocusBubble.SHELL_MAX)
	# Path line should be created
	assert_that(renderer._travel_path_line).is_not_null()


func test_travel_started_skips_negligible_distance() -> void:
	var renderer := _make_renderer()
	_add_player_ship(renderer, Vector3.ZERO)
	renderer._sync_poi_markers()

	# Travel to same POI (poi_001) — impostor position is ZERO (same location)
	renderer._on_travel_started("poi_001", "Earth")

	assert_bool(renderer._is_animating_travel).is_false()


func test_travel_ended_snaps_to_origin() -> void:
	var renderer := _make_renderer()
	var ship := _add_player_ship(renderer, Vector3.ZERO)
	renderer._sync_poi_markers()

	renderer._on_travel_started("poi_002", "Mars")
	assert_bool(renderer._is_animating_travel).is_true()

	# End travel — update location to Mars first
	StateManager.location = {"poi_id": "poi_002", "position": {"x": 5.0, "y": 8.0}}
	renderer._on_travel_ended()

	assert_bool(renderer._is_animating_travel).is_false()
	assert_that(renderer._travel_path_line).is_null()
	# Ship should be back at origin
	assert_float(ship.global_position.length()).is_less(1.0)


func test_travel_aborted_snaps_to_origin() -> void:
	var renderer := _make_renderer()
	var ship := _add_player_ship(renderer, Vector3.ZERO)
	renderer._sync_poi_markers()

	renderer._on_travel_started("poi_002", "Mars")
	# Simulate some elapsed time by moving the ship
	ship.global_position = Vector3(500.0, 0.0, 700.0)

	renderer._on_travel_aborted("poi_001")

	assert_bool(renderer._is_animating_travel).is_false()
	# Ship should be back at origin
	assert_float(ship.global_position.length()).is_less(1.0)


# --- Guards ---

func test_update_player_ship_guarded_during_travel() -> void:
	var renderer := _make_renderer()
	var ship := _add_player_ship(renderer, Vector3.ZERO)
	renderer._sync_poi_markers()

	renderer._on_travel_started("poi_002", "Mars")
	ship.global_position = Vector3(500.0, 0.0, 700.0)

	# _update_player_ship should be guarded and NOT move the ship
	renderer._update_player_ship()
	assert_float(ship.global_position.x).is_equal_approx(500.0, 0.1)


func test_update_player_ship_works_when_not_traveling() -> void:
	var renderer := _make_renderer()
	var ship := _add_player_ship(renderer, Vector3(100.0, 0.0, 100.0))

	# Not traveling — _update_player_ship should move ship to origin
	renderer._update_player_ship()
	assert_float(ship.global_position.length()).is_less(1.0)


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
	var ship := _add_player_ship(renderer, Vector3.ZERO)
	renderer._sync_poi_markers()

	# Add another ship
	var other_ship: Node3D = SHIP_SCENE.instantiate()
	renderer.add_child(other_ship)
	other_ship.setup("p2", "Other", Vector3(5.0, 0.0, 5.0), false)
	renderer._ships["p2"] = other_ship

	renderer._on_travel_started("poi_002", "Mars")
	ship.global_position = Vector3(500.0, 0.0, 700.0)

	# Location changes — other ship should be removed, player ship untouched
	renderer._on_location_changed("poi_001", "poi_002")

	assert_bool(renderer._ships.has("p1")).is_true()
	assert_bool(renderer._ships.has("p2")).is_false()
	assert_float(ship.global_position.x).is_equal_approx(500.0, 0.1)


# --- Click detection (raycast math) ---

var SystemRenderer: GDScript = load("res://scripts/game/system_renderer.gd")


func test_ray_point_distance_direct_hit() -> void:
	# Ray from (0,10,0) pointing straight down at a point at origin
	var origin := Vector3(0, 10, 0)
	var dir := Vector3(0, -1, 0)
	var point := Vector3(0, 0, 0)
	var result: Array = SystemRenderer.ray_point_distance(origin, dir, point)
	assert_float(result[0]).is_equal_approx(0.0, 0.01)  # distance = 0 (direct hit)
	assert_float(result[1]).is_equal_approx(10.0, 0.01)  # t = 10 (distance along ray)


func test_ray_point_distance_near_miss() -> void:
	# Ray from (0,10,0) pointing down, point offset by 2 on X
	var origin := Vector3(0, 10, 0)
	var dir := Vector3(0, -1, 0)
	var point := Vector3(2, 0, 0)
	var result: Array = SystemRenderer.ray_point_distance(origin, dir, point)
	assert_float(result[0]).is_equal_approx(2.0, 0.01)  # distance = 2
	assert_float(result[1]).is_equal_approx(10.0, 0.01)  # t = 10


func test_ray_point_distance_behind_camera() -> void:
	# Point behind the ray origin
	var origin := Vector3(0, 10, 0)
	var dir := Vector3(0, -1, 0)
	var point := Vector3(0, 20, 0)  # above origin, behind downward ray
	var result: Array = SystemRenderer.ray_point_distance(origin, dir, point)
	assert_float(result[0]).is_less(0.0)  # negative = behind camera


func test_ray_point_distance_angled_ray() -> void:
	# Angled ray — typical top-down camera at an angle
	var origin := Vector3(0, 20, 10)
	var dir := Vector3(0, -0.894, -0.447).normalized()  # ~63 degrees from horizontal
	var point := Vector3(0, 0, 0)
	var result: Array = SystemRenderer.ray_point_distance(origin, dir, point)
	# Should be a near hit (small distance)
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

	# Toggle off
	renderer._on_poi_marker_selected(marker)
	assert_str(renderer._selected_poi_id).is_equal("")
	assert_bool(marker.is_selected).is_false()
	marker.queue_free()


# --- Nearby ship offset ---

func test_nearby_ship_offset_nonzero() -> void:
	var renderer := _make_renderer()
	var offset: Vector3 = renderer._nearby_ship_offset("player_abc")
	# Should be a small distance from origin, not at origin
	assert_float(offset.length()).is_greater(2.0)
	assert_float(offset.length()).is_less(15.0)
	# Should be on the XZ plane
	assert_float(offset.y).is_equal_approx(0.0, 0.01)


func test_nearby_ship_offset_deterministic() -> void:
	var renderer := _make_renderer()
	var o1: Vector3 = renderer._nearby_ship_offset("player_xyz")
	var o2: Vector3 = renderer._nearby_ship_offset("player_xyz")
	assert_float(o1.x).is_equal_approx(o2.x, 0.001)
	assert_float(o1.z).is_equal_approx(o2.z, 0.001)


# --- HUD scene config: GameArea must not block 3D clicks ---

func test_game_area_has_mouse_filter_ignore() -> void:
	var hud_scene := load("res://scenes/ui/hud.tscn") as PackedScene
	var hud: Node = hud_scene.instantiate()
	# GameArea is at Layout/MidRow/GameArea — use find_child
	var game_area: Control = hud.find_child("GameArea", true, false) as Control
	assert_that(game_area).is_not_null()
	# MOUSE_FILTER_IGNORE = 2 — required so clicks pass through to 3D raycast
	assert_int(game_area.mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)
	hud.queue_free()
