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


func test_popup_position_prefers_above_button_when_space_available() -> void:
	var action_bar: PanelContainer = load("res://scripts/ui/action_bar.gd").new()
	var button_rect := Rect2(100, 560, 120, 32)
	var menu_size := Vector2i(200, 180)
	var visible_rect := Rect2(0, 0, 1280, 720)

	var popup_pos: Vector2i = action_bar._desired_popup_position(button_rect, menu_size, visible_rect)

	assert_int(popup_pos.x).is_equal(100)
	assert_int(popup_pos.y).is_equal(380)
	action_bar.free()


func test_popup_position_falls_below_when_not_enough_room_above() -> void:
	var action_bar: PanelContainer = load("res://scripts/ui/action_bar.gd").new()
	var button_rect := Rect2(100, 40, 120, 32)
	var menu_size := Vector2i(200, 180)
	var visible_rect := Rect2(0, 0, 1280, 720)

	var popup_pos: Vector2i = action_bar._desired_popup_position(button_rect, menu_size, visible_rect)

	assert_int(popup_pos.y).is_equal(72)
	action_bar.free()


func test_popup_position_clamps_within_viewport_width() -> void:
	var action_bar: PanelContainer = load("res://scripts/ui/action_bar.gd").new()
	var button_rect := Rect2(1180, 560, 120, 32)
	var menu_size := Vector2i(200, 180)
	var visible_rect := Rect2(0, 0, 1280, 720)

	var popup_pos: Vector2i = action_bar._desired_popup_position(button_rect, menu_size, visible_rect)

	assert_int(popup_pos.x).is_equal(1080)
	action_bar.free()


func test_system_jump_id_prefers_system_id_field() -> void:
	var action_bar_script: GDScript = load("res://scripts/ui/action_bar.gd")

	var jump_id: String = action_bar_script._system_jump_id({
		"system_id": "alpha_centauri",
		"id": "",
	})

	assert_str(jump_id).is_equal("alpha_centauri")
