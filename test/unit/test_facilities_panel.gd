extends GdUnitTestSuite

# Tests for the facilities panel -- script loading and docking prerequisites.


func before_test() -> void:
	StateManager.player = {"id": "p1", "name": "Test", "credits": 5000}
	StateManager.ship = {"hull": 100, "max_hull": 100}
	StateManager.location = {"docked_at": "base_001"}
	StateManager.cargo = []


func after_test() -> void:
	StateManager.reset()


func test_facilities_panel_script_loads() -> void:
	var script: GDScript = load("res://scripts/ui/facilities_panel.gd")
	assert_that(script).is_not_null()
	assert_bool(script.can_instantiate()).is_true()


func test_facilities_require_docking() -> void:
	# Facilities should only be accessible when docked
	StateManager.location = {}
	assert_bool(StateManager.is_docked()).is_false()

	StateManager.location = {"docked_at": "base_001"}
	assert_bool(StateManager.is_docked()).is_true()


func test_facilities_not_docked_with_empty_string() -> void:
	# An empty docked_at string means not docked
	StateManager.location = {"docked_at": ""}
	assert_bool(StateManager.is_docked()).is_false()


func test_facilities_docked_state_after_undock() -> void:
	# Verify state transitions correctly
	StateManager.location = {"docked_at": "base_001"}
	assert_bool(StateManager.is_docked()).is_true()

	# Simulate undocking
	StateManager.location = {"poi_id": "poi_001", "docked_at": ""}
	assert_bool(StateManager.is_docked()).is_false()
