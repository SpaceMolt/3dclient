extends GdUnitTestSuite

# Tests for camera_controller.gd


func before_test() -> void:
	StateManager.player = {}
	StateManager.set("is_traveling", false)


func after_test() -> void:
	StateManager.reset()


func test_script_loads_successfully() -> void:
	var script: GDScript = load("res://scripts/game/camera_controller.gd")
	assert_that(script).is_not_null()
	assert_bool(script.can_instantiate()).is_true()
