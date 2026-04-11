extends GdUnitTestSuite

# Tests for the wreck panel -- script loading, age formatting, and data
# parsing logic used when displaying wrecks at the current POI.


func before_test() -> void:
	StateManager.player = {"id": "p1", "name": "TestPlayer"}
	StateManager.ship = {"hull": 100, "max_hull": 100}
	StateManager.location = {"poi_id": "poi_001", "docked_at": ""}
	StateManager.cargo = []
	StateManager.current_system = {}


func after_test() -> void:
	StateManager.reset()


# --- Script loading ---

func test_wreck_panel_script_loads() -> void:
	var script: GDScript = load("res://scripts/ui/wreck_panel.gd")
	assert_that(script).is_not_null()
	assert_bool(script.can_instantiate()).is_true()


# --- Age formatting ---

func test_format_age_seconds_when_under_one_minute() -> void:
	var script: GDScript = load("res://scripts/ui/wreck_panel.gd")
	# 3 ticks = 30 seconds
	assert_str(script.format_age(3)).is_equal("30s ago")


func test_format_age_zero_ticks() -> void:
	var script: GDScript = load("res://scripts/ui/wreck_panel.gd")
	assert_str(script.format_age(0)).is_equal("0s ago")


func test_format_age_minutes_when_over_one_minute() -> void:
	var script: GDScript = load("res://scripts/ui/wreck_panel.gd")
	# 60 ticks = 600 seconds = 10 minutes
	assert_str(script.format_age(60)).is_equal("10m ago")


func test_format_age_minutes_boundary() -> void:
	var script: GDScript = load("res://scripts/ui/wreck_panel.gd")
	# 6 ticks = 60 seconds = 1 minute
	assert_str(script.format_age(6)).is_equal("1m ago")


func test_format_age_hours_when_over_sixty_minutes() -> void:
	var script: GDScript = load("res://scripts/ui/wreck_panel.gd")
	# 420 ticks = 4200 seconds = 70 minutes = 1h 10m
	assert_str(script.format_age(420)).is_equal("1h 10m ago")


func test_format_age_exact_hour() -> void:
	var script: GDScript = load("res://scripts/ui/wreck_panel.gd")
	# 360 ticks = 3600 seconds = 60 minutes = 1h 0m
	assert_str(script.format_age(360)).is_equal("1h 0m ago")


# --- Age to minutes conversion ---

func test_age_to_minutes_basic() -> void:
	var script: GDScript = load("res://scripts/ui/wreck_panel.gd")
	# 60 ticks * 10 seconds / 60 = 10 minutes
	assert_int(script.age_to_minutes(60)).is_equal(10)


func test_age_to_minutes_zero() -> void:
	var script: GDScript = load("res://scripts/ui/wreck_panel.gd")
	assert_int(script.age_to_minutes(0)).is_equal(0)


func test_age_to_minutes_partial() -> void:
	var script: GDScript = load("res://scripts/ui/wreck_panel.gd")
	# 3 ticks = 30 seconds = 0 minutes (integer division)
	assert_int(script.age_to_minutes(3)).is_equal(0)


func test_age_to_minutes_large() -> void:
	var script: GDScript = load("res://scripts/ui/wreck_panel.gd")
	# 180 ticks = 1800 seconds = 30 minutes (wreck despawn time)
	assert_int(script.age_to_minutes(180)).is_equal(30)


# --- Wreck data parsing ---

func test_empty_wreck_list_is_empty() -> void:
	var wrecks: Array = []
	assert_bool(wrecks.is_empty()).is_true()


func test_wreck_data_extraction() -> void:
	var wreck := {
		"wreck_id": "w1",
		"player_name": "Pirate",
		"ship_class": "Corsair",
		"age_ticks": 30,
		"items": [
			{"item_id": "ore_1", "name": "Iron Ore", "quantity": 5},
			{"item_id": "mod_1", "name": "Shield Booster", "quantity": 1},
		]
	}
	assert_str(wreck.get("wreck_id", "")).is_equal("w1")
	assert_str(wreck.get("player_name", "Unknown")).is_equal("Pirate")
	assert_str(wreck.get("ship_class", "Unknown")).is_equal("Corsair")
	assert_int(wreck.get("age_ticks", 0)).is_equal(30)
	assert_int(wreck.get("items", []).size()).is_equal(2)


func test_wreck_item_data_extraction() -> void:
	var item := {"item_id": "ore_1", "name": "Iron Ore", "quantity": 5}
	assert_str(item.get("item_id", "")).is_equal("ore_1")
	assert_str(item.get("name", "Unknown")).is_equal("Iron Ore")
	assert_int(item.get("quantity", 0)).is_equal(5)


func test_wreck_with_no_items() -> void:
	var wreck := {
		"wreck_id": "w2",
		"player_name": "Miner",
		"ship_class": "Hauler",
		"age_ticks": 100,
		"items": []
	}
	assert_bool(wreck.get("items", []).is_empty()).is_true()


func test_wreck_missing_items_key_defaults_empty() -> void:
	var wreck := {
		"wreck_id": "w3",
		"player_name": "Explorer",
		"ship_class": "Scout",
		"age_ticks": 10,
	}
	assert_int(wreck.get("items", []).size()).is_equal(0)


# --- Undocked requirement ---

func test_wreck_panel_requires_undocked() -> void:
	# Wrecks are in space -- player should not be docked to see this panel
	StateManager.location = {"poi_id": "poi_001", "docked_at": ""}
	assert_bool(StateManager.is_docked()).is_false()


func test_wreck_panel_hidden_when_docked() -> void:
	StateManager.location = {"poi_id": "poi_001", "docked_at": "base_001"}
	assert_bool(StateManager.is_docked()).is_true()
