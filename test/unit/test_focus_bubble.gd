extends GdUnitTestSuite

## Tests for focus_bubble.gd — coordinate math for the cinematic scale system.

var FocusBubble: GDScript = load("res://scripts/game/focus_bubble.gd")


# --- poi_radius ---

func test_star_radius_by_spectral_class() -> void:
	# Giant stars (O, B) should be largest
	assert_float(FocusBubble.poi_radius("sun", "O")).is_equal(FocusBubble.SCALE_STAR_LARGE)
	assert_float(FocusBubble.poi_radius("sun", "B")).is_equal(FocusBubble.SCALE_STAR_LARGE)
	# Medium stars (G, K)
	assert_float(FocusBubble.poi_radius("sun", "G")).is_equal(FocusBubble.SCALE_STAR_MEDIUM)
	assert_float(FocusBubble.poi_radius("sun", "K")).is_equal(FocusBubble.SCALE_STAR_MEDIUM)
	# Small stars (M class)
	assert_float(FocusBubble.poi_radius("sun", "M")).is_equal(FocusBubble.SCALE_STAR_SMALL)
	# Black hole
	assert_float(FocusBubble.poi_radius("sun", "BH")).is_equal(FocusBubble.SCALE_STAR_BH)


func test_planet_radius_by_class() -> void:
	# Gas giants should be large
	assert_float(FocusBubble.poi_radius("planet", "jovian")).is_equal(FocusBubble.SCALE_GAS_GIANT)
	assert_float(FocusBubble.poi_radius("planet", "hot_jupiter")).is_equal(FocusBubble.SCALE_GAS_GIANT)
	# Super terran is medium-large
	assert_float(FocusBubble.poi_radius("planet", "super_terran")).is_equal(FocusBubble.SCALE_PLANET_LARGE)
	# Normal terrestrial
	assert_float(FocusBubble.poi_radius("planet", "terran")).is_equal(FocusBubble.SCALE_PLANET_SMALL)
	assert_float(FocusBubble.poi_radius("planet", "arid")).is_equal(FocusBubble.SCALE_PLANET_SMALL)


func test_moon_radius() -> void:
	assert_float(FocusBubble.poi_radius("moon", "")).is_equal(FocusBubble.SCALE_MOON)


func test_station_radius() -> void:
	assert_float(FocusBubble.poi_radius("station", "")).is_equal(FocusBubble.SCALE_STATION)


func test_all_poi_types_have_nonzero_radius() -> void:
	var types := [
		"sun", "planet", "moon", "station", "asteroid", "asteroid_belt",
		"ice_field", "nebula", "gas_cloud", "relic",
		"wormhole_entrance", "wormhole_exit", "wormhole_collapsed",
	]
	for t in types:
		assert_float(FocusBubble.poi_radius(t, "")).is_greater(0.0)


func test_unknown_type_returns_safe_fallback() -> void:
	assert_float(FocusBubble.poi_radius("unknown_thing", "")).is_greater(0.0)


# --- compress_distance ---

func test_compress_distance_zero() -> void:
	assert_float(FocusBubble.compress_distance(0.0)).is_equal(FocusBubble.SHELL_MIN)


func test_compress_distance_monotonically_increasing() -> void:
	var d1: float = FocusBubble.compress_distance(0.1)
	var d2: float = FocusBubble.compress_distance(1.0)
	var d3: float = FocusBubble.compress_distance(5.0)
	var d4: float = FocusBubble.compress_distance(8.0)
	assert_float(d1).is_greater(FocusBubble.SHELL_MIN)
	assert_float(d2).is_greater(d1)
	assert_float(d3).is_greater(d2)
	assert_float(d4).is_greater(d3)


func test_compress_distance_stays_within_shell() -> void:
	# Even at extreme distances, should not exceed SHELL_MAX
	var d: float = FocusBubble.compress_distance(100.0)
	assert_float(d).is_less_equal(FocusBubble.SHELL_MAX)
	assert_float(d).is_greater(FocusBubble.SHELL_MIN)


func test_compress_distance_typical_values() -> void:
	# 1 AU should be noticeably past SHELL_MIN
	var d1au: float = FocusBubble.compress_distance(1.0)
	assert_float(d1au).is_greater(FocusBubble.SHELL_MIN + 500.0)
	# 8 AU (max real range) should be close to SHELL_MAX
	var d8au: float = FocusBubble.compress_distance(8.0)
	assert_float(d8au).is_greater(FocusBubble.SHELL_MAX - 500.0)


# --- impostor_position ---

func test_impostor_position_direction_preserved() -> void:
	# POI due east of player (positive X in AU)
	var player := Vector2(0.0, 0.0)
	var poi := Vector2(3.0, 0.0)
	var pos: Vector3 = FocusBubble.impostor_position(player, poi)
	# Should be on the positive X axis
	assert_float(pos.x).is_greater(0.0)
	assert_float(absf(pos.z)).is_less(0.1)
	assert_float(pos.y).is_equal_approx(0.0, 0.01)


func test_impostor_position_direction_diagonal() -> void:
	var player := Vector2(1.0, 1.0)
	var poi := Vector2(4.0, 4.0)  # northeast
	var pos: Vector3 = FocusBubble.impostor_position(player, poi)
	# X and Z should be roughly equal (45 degree angle)
	assert_float(absf(pos.x - pos.z)).is_less(1.0)
	assert_float(pos.x).is_greater(0.0)
	assert_float(pos.z).is_greater(0.0)


func test_impostor_position_distance_in_shell() -> void:
	var player := Vector2(0.0, 0.0)
	var poi := Vector2(5.0, 0.0)
	var pos: Vector3 = FocusBubble.impostor_position(player, poi)
	var dist: float = pos.length()
	assert_float(dist).is_greater(FocusBubble.SHELL_MIN)
	assert_float(dist).is_less(FocusBubble.SHELL_MAX)


func test_impostor_position_same_location_returns_zero() -> void:
	var pos: Vector3 = FocusBubble.impostor_position(Vector2(3.0, 4.0), Vector2(3.0, 4.0))
	assert_float(pos.length()).is_less(0.01)


func test_impostor_position_negative_direction() -> void:
	# POI to the west and south
	var player := Vector2(5.0, 5.0)
	var poi := Vector2(2.0, 2.0)
	var pos: Vector3 = FocusBubble.impostor_position(player, poi)
	assert_float(pos.x).is_less(0.0)
	assert_float(pos.z).is_less(0.0)


# --- focused_poi_offset ---

func test_planet_offset_is_below_ship() -> void:
	var offset: Vector3 = FocusBubble.focused_poi_offset("planet", "terran")
	# Planet center should be below (negative Y)
	assert_float(offset.y).is_less(0.0)
	# The offset magnitude should be based on the planet radius
	var expected_dist: float = FocusBubble.SCALE_PLANET_SMALL * FocusBubble.ORBIT_MARGIN
	assert_float(absf(offset.y)).is_equal_approx(expected_dist, 1.0)


func test_star_offset_is_below_ship() -> void:
	var offset: Vector3 = FocusBubble.focused_poi_offset("sun", "G")
	assert_float(offset.y).is_less(0.0)
	# Should be large — star radius * margin
	assert_float(absf(offset.y)).is_greater(1000.0)


func test_station_offset_is_in_front() -> void:
	var offset: Vector3 = FocusBubble.focused_poi_offset("station", "")
	# Station should be offset on Z, not Y
	assert_float(offset.z).is_less(0.0)
	assert_float(absf(offset.y)).is_less(1.0)


func test_asteroid_offset_is_in_front() -> void:
	var offset: Vector3 = FocusBubble.focused_poi_offset("asteroid", "metallic")
	assert_float(offset.z).is_less(0.0)


# --- poi_au_pos ---

func test_poi_au_pos_extracts_correctly() -> void:
	var data := {"position": {"x": 3.5, "y": -2.1}, "name": "Test"}
	var pos: Vector2 = FocusBubble.poi_au_pos(data)
	assert_float(pos.x).is_equal_approx(3.5, 0.001)
	assert_float(pos.y).is_equal_approx(-2.1, 0.001)


func test_poi_au_pos_missing_position() -> void:
	var data := {"name": "NoPos"}
	var pos: Vector2 = FocusBubble.poi_au_pos(data)
	assert_float(pos.x).is_equal_approx(0.0, 0.001)
	assert_float(pos.y).is_equal_approx(0.0, 0.001)


# --- perspective_scale ---

func test_perspective_scale_at_zero_distance() -> void:
	assert_float(FocusBubble.perspective_scale(0.0)).is_equal_approx(1.0, 0.001)


func test_perspective_scale_decreases_with_distance() -> void:
	var s1: float = FocusBubble.perspective_scale(1.0)
	var s2: float = FocusBubble.perspective_scale(3.0)
	var s3: float = FocusBubble.perspective_scale(8.0)
	assert_float(s1).is_less(1.0)
	assert_float(s2).is_less(s1)
	assert_float(s3).is_less(s2)


func test_perspective_scale_never_zero() -> void:
	var s: float = FocusBubble.perspective_scale(100.0)
	assert_float(s).is_greater(0.0)
	assert_float(s).is_greater_equal(FocusBubble.MIN_PERSPECTIVE_SCALE)


# --- hit_radius ---

func test_hit_radius_scales_with_poi() -> void:
	var r_station: float = FocusBubble.hit_radius("station", "", 1.0)
	var r_planet: float = FocusBubble.hit_radius("planet", "terran", 1.0)
	assert_float(r_planet).is_greater(r_station)


func test_hit_radius_capped() -> void:
	var r: float = FocusBubble.hit_radius("sun", "O", 1.0)
	assert_float(r).is_less_equal(500.0)


func test_hit_radius_has_minimum() -> void:
	var r: float = FocusBubble.hit_radius("station", "", 0.01)
	assert_float(r).is_greater_equal(20.0)


# --- continuous_poi_position ---

func test_continuous_at_zero_distance_returns_focused_offset() -> void:
	var player := Vector2(3.0, 4.0)
	var pos: Vector3 = FocusBubble.continuous_poi_position(player, player, "planet", "terran")
	var expected: Vector3 = FocusBubble.focused_poi_offset("planet", "terran")
	assert_float(pos.x).is_equal_approx(expected.x, 0.1)
	assert_float(pos.y).is_equal_approx(expected.y, 0.1)
	assert_float(pos.z).is_equal_approx(expected.z, 0.1)


func test_continuous_beyond_blend_au_returns_background_position() -> void:
	var player := Vector2(0.0, 0.0)
	var poi := Vector2(2.0, 0.0)  # 2 AU away, well beyond BLEND_AU
	var pos: Vector3 = FocusBubble.continuous_poi_position(player, poi, "planet", "terran")
	var expected: Vector3 = FocusBubble.impostor_position(player, poi)
	assert_float(pos.x).is_equal_approx(expected.x, 0.1)
	assert_float(pos.y).is_equal_approx(expected.y, 0.1)
	assert_float(pos.z).is_equal_approx(expected.z, 0.1)


func test_continuous_in_blend_zone_is_between_focused_and_background() -> void:
	var player := Vector2(0.0, 0.0)
	var poi := Vector2(FocusBubble.BLEND_AU * 0.5, 0.0)  # halfway into blend zone
	var pos: Vector3 = FocusBubble.continuous_poi_position(player, poi, "planet", "terran")
	var focused: Vector3 = FocusBubble.focused_poi_offset("planet", "terran")
	var background: Vector3 = FocusBubble.impostor_position(player, poi)
	# Position should be between focused and background — not at either extreme
	assert_float(pos.y).is_greater(focused.y)
	assert_float(pos.y).is_less(0.0)
	assert_float(pos.x).is_greater(focused.x)
	assert_float(pos.x).is_less(background.x)


func test_continuous_direction_preserved_through_blend() -> void:
	var player := Vector2(0.0, 0.0)
	# POI to the northeast at 0.5 * BLEND_AU
	var poi := Vector2(FocusBubble.BLEND_AU * 0.35, FocusBubble.BLEND_AU * 0.35)
	var pos: Vector3 = FocusBubble.continuous_poi_position(player, poi, "planet", "terran")
	# XZ components should both be positive (northeast direction preserved)
	assert_float(pos.x).is_greater(0.0)
	assert_float(pos.z).is_greater(0.0)
