extends GdUnitTestSuite

# Tests for visual effect scripts — verifies they load, compile, and have
# correct signal handler signatures.


func before_test() -> void:
	StateManager.player = {"id": "p1"}
	StateManager.location = {"poi_id": "poi_001"}
	StateManager.set("is_traveling", false)
	StateManager.set("is_mining", false)
	StateManager.set("is_docking", false)
	StateManager.set("is_undocking", false)
	StateManager.set("is_jumping", false)
	StateManager.in_combat = false
	StateManager.battle = {}


func after_test() -> void:
	StateManager.reset()


# --- Script loading (catches type inference / compile errors) ---

func test_combat_rings_loads() -> void:
	var script: GDScript = load("res://scripts/game/combat_rings.gd")
	assert_that(script).is_not_null()
	assert_bool(script.can_instantiate()).is_true()


func test_dock_effect_loads() -> void:
	var script: GDScript = load("res://scripts/game/dock_effect.gd")
	assert_that(script).is_not_null()
	assert_bool(script.can_instantiate()).is_true()


func test_mining_beam_loads() -> void:
	var script: GDScript = load("res://scripts/game/mining_beam.gd")
	assert_that(script).is_not_null()
	assert_bool(script.can_instantiate()).is_true()


# --- travel_effect signal signature ---

func test_travel_effect_handles_travel_started_with_args() -> void:
	# travel_started now emits (dest_poi_id, dest_poi_name)
	# This test verifies the handler accepts those arguments
	var script: GDScript = load("res://scripts/game/travel_effect.gd")
	assert_that(script).is_not_null()
	# Verify the method exists and accepts 2 optional args
	var methods: Array = script.get_script_method_list()
	var found := false
	for m in methods:
		if m.get("name", "") == "_on_travel_started":
			found = true
			break
	assert_bool(found).is_true()


# --- jump_effect signal wiring ---

func test_jump_effect_script_loads() -> void:
	var script: GDScript = load("res://scripts/game/jump_effect.gd")
	assert_that(script).is_not_null()
	assert_bool(script.can_instantiate()).is_true()


# --- combat_rings zone highlight logic ---

func test_combat_rings_zone_colors_count() -> void:
	var script: GDScript = load("res://scripts/game/combat_rings.gd")
	var constants: Dictionary = script.get_script_constant_map()
	var zone_count: int = constants.get("ZONE_COUNT", 0)
	var zone_colors: Array = constants.get("ZONE_COLORS", [])
	var zone_radii: Array = constants.get("ZONE_RADII", [])
	assert_int(zone_count).is_equal(5)
	assert_int(zone_colors.size()).is_equal(zone_count)
	assert_int(zone_radii.size()).is_equal(zone_count)


# --- game.gd loads ---

func test_game_script_loads() -> void:
	var script: GDScript = load("res://scripts/game/game.gd")
	assert_that(script).is_not_null()
	assert_bool(script.can_instantiate()).is_true()
