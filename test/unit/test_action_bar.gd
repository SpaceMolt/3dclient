extends GdUnitTestSuite

# Tests for action_bar.gd — visibility logic, travel/attack menu

func before_test() -> void:
	StateManager.player = {"id": "p1"}
	StateManager.ship = {"hull": 100, "max_hull": 100}
	StateManager.location = {"poi_id": "poi_001", "poi_type": "planet", "docked_at": ""}
	StateManager.current_system = {
		"pois": [
			{"id": "poi_001", "name": "Earth", "type": "planet", "has_base": true},
			{"id": "poi_002", "name": "Mars", "type": "planet", "has_base": false},
		]
	}
	StateManager.nearby_players = []
	StateManager.nearby_pirates = []
	StateManager.in_combat = false
	StateManager.has_pending = false
	StateManager.set("is_traveling", false)


func after_test() -> void:
	StateManager.reset()


# Verify script loads (catches type inference / Variant errors)
func test_action_bar_script_loads() -> void:
	var script: GDScript = load("res://scripts/ui/action_bar.gd")
	assert_that(script).is_not_null()
	assert_bool(script.can_instantiate()).is_true()
