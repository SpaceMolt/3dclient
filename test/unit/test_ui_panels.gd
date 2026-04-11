extends GdUnitTestSuite

# Verifies all UI panel scripts load successfully (catches compile/type errors).
# Individual panels with complex logic should get their own test files;
# this file ensures every UI script at least compiles.

func before_test() -> void:
	StateManager.player = {"id": "p1", "name": "Test"}
	StateManager.ship = {"hull": 100, "max_hull": 100}
	StateManager.location = {"poi_id": "poi_001", "docked_at": ""}
	StateManager.current_system = {"pois": []}
	StateManager.nearby_players = []
	StateManager.nearby_pirates = []
	StateManager.in_combat = false
	StateManager.battle = {}
	StateManager.cargo = []
	StateManager.missions = {}
	StateManager.set("is_traveling", false)


func after_test() -> void:
	StateManager.reset()


func test_hud_script_loads() -> void:
	var script: GDScript = load("res://scripts/ui/hud.gd")
	assert_that(script).is_not_null()
	assert_bool(script.can_instantiate()).is_true()


func test_battle_panel_script_loads() -> void:
	var script: GDScript = load("res://scripts/ui/battle_panel.gd")
	assert_that(script).is_not_null()
	assert_bool(script.can_instantiate()).is_true()


func test_chat_panel_script_loads() -> void:
	var script: GDScript = load("res://scripts/ui/chat_panel.gd")
	assert_that(script).is_not_null()
	assert_bool(script.can_instantiate()).is_true()


func test_crafting_panel_script_loads() -> void:
	var script: GDScript = load("res://scripts/ui/crafting_panel.gd")
	assert_that(script).is_not_null()
	assert_bool(script.can_instantiate()).is_true()


func test_event_log_script_loads() -> void:
	var script: GDScript = load("res://scripts/ui/event_log.gd")
	assert_that(script).is_not_null()
	assert_bool(script.can_instantiate()).is_true()


func test_galaxy_map_script_loads() -> void:
	var script: GDScript = load("res://scripts/ui/galaxy_map.gd")
	assert_that(script).is_not_null()
	assert_bool(script.can_instantiate()).is_true()


func test_market_panel_script_loads() -> void:
	var script: GDScript = load("res://scripts/ui/market_panel.gd")
	assert_that(script).is_not_null()
	assert_bool(script.can_instantiate()).is_true()


func test_minimap_script_loads() -> void:
	var script: GDScript = load("res://scripts/ui/minimap.gd")
	assert_that(script).is_not_null()
	assert_bool(script.can_instantiate()).is_true()


func test_missions_panel_script_loads() -> void:
	var script: GDScript = load("res://scripts/ui/missions_panel.gd")
	assert_that(script).is_not_null()
	assert_bool(script.can_instantiate()).is_true()


func test_settings_panel_script_loads() -> void:
	var script: GDScript = load("res://scripts/ui/settings_panel.gd")
	assert_that(script).is_not_null()
	assert_bool(script.can_instantiate()).is_true()


func test_ship_panel_script_loads() -> void:
	var script: GDScript = load("res://scripts/ui/ship_panel.gd")
	assert_that(script).is_not_null()
	assert_bool(script.can_instantiate()).is_true()


func test_storage_panel_script_loads() -> void:
	var script: GDScript = load("res://scripts/ui/storage_panel.gd")
	assert_that(script).is_not_null()
	assert_bool(script.can_instantiate()).is_true()


func test_action_log_panel_script_loads() -> void:
	var script: GDScript = load("res://scripts/ui/action_log_panel.gd")
	assert_that(script).is_not_null()
	assert_bool(script.can_instantiate()).is_true()


func test_facilities_panel_script_loads() -> void:
	var script: GDScript = load("res://scripts/ui/facilities_panel.gd")
	assert_that(script).is_not_null()
	assert_bool(script.can_instantiate()).is_true()


func test_info_panel_script_loads() -> void:
	var script: GDScript = load("res://scripts/ui/info_panel.gd")
	assert_that(script).is_not_null()
	assert_bool(script.can_instantiate()).is_true()


func test_faction_panel_script_loads() -> void:
	var script: GDScript = load("res://scripts/ui/faction_panel.gd")
	assert_that(script).is_not_null()
	assert_bool(script.can_instantiate()).is_true()


func test_skills_panel_script_loads() -> void:
	var script: GDScript = load("res://scripts/ui/skills_panel.gd")
	assert_that(script).is_not_null()
	assert_bool(script.can_instantiate()).is_true()


func test_wreck_panel_script_loads() -> void:
	var script: GDScript = load("res://scripts/ui/wreck_panel.gd")
	assert_that(script).is_not_null()
	assert_bool(script.can_instantiate()).is_true()


func test_trades_panel_script_loads() -> void:
	var script: GDScript = load("res://scripts/ui/trades_panel.gd")
	assert_that(script).is_not_null()
	assert_bool(script.can_instantiate()).is_true()


func test_route_banner_script_loads() -> void:
	var script: GDScript = load("res://scripts/ui/route_banner.gd")
	assert_that(script).is_not_null()
	assert_bool(script.can_instantiate()).is_true()
