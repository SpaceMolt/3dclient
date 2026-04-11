extends GdUnitTestSuite

# Tests for ship panel module management, commission, and marketplace logic.
# Uses static methods on ShipPanel class_name.


func before_test() -> void:
	StateManager.player = {"id": "p1", "name": "TestPlayer"}
	StateManager.ship = {"hull": 100, "max_hull": 100}
	StateManager.location = {"poi_id": "poi_001", "docked_at": ""}
	StateManager.current_system = {"pois": []}
	StateManager.cargo = []
	StateManager.modules = []


func after_test() -> void:
	StateManager.reset()


# --- Script loading ---

func test_ship_panel_script_loads() -> void:
	var script: GDScript = load("res://scripts/ui/ship_panel.gd")
	assert_that(script).is_not_null()
	assert_bool(script.can_instantiate()).is_true()


# --- Module list population from StateManager.modules ---

func test_get_installable_modules_empty_when_no_cargo() -> void:
	StateManager.cargo = []
	var result: Array = ShipPanel.get_installable_modules_from_cargo()
	assert_int(result.size()).is_equal(0)


func test_get_installable_modules_finds_module_type_items() -> void:
	StateManager.cargo = [
		{"item_id": "laser_mk1", "item_name": "Laser Mk1", "type": "weapon_module", "quantity": 1},
		{"item_id": "copper_ore", "item_name": "Copper Ore", "type": "ore", "quantity": 10},
		{"item_id": "shield_mod", "item_name": "Shield Module", "type": "defense_module", "quantity": 1},
	]
	var result: Array = ShipPanel.get_installable_modules_from_cargo()
	assert_int(result.size()).is_equal(2)
	assert_str(result[0].get("item_id")).is_equal("laser_mk1")
	assert_str(result[1].get("item_id")).is_equal("shield_mod")


func test_get_installable_modules_matches_category_field() -> void:
	StateManager.cargo = [
		{"item_id": "scanner", "item_name": "Scanner", "type": "utility", "category": "module", "quantity": 1},
		{"item_id": "fuel", "item_name": "Fuel", "type": "consumable", "category": "resource", "quantity": 5},
	]
	var result: Array = ShipPanel.get_installable_modules_from_cargo()
	assert_int(result.size()).is_equal(1)
	assert_str(result[0].get("item_id")).is_equal("scanner")


func test_module_list_reads_from_state_manager() -> void:
	StateManager.modules = [
		{"module_id": "mod_1", "name": "Laser Mk1", "type": "weapon", "size": 2, "wear": 0.0, "cpu": 5, "power": 10},
		{"module_id": "mod_2", "name": "Shield Gen", "type": "defense", "size": 3, "wear": 0.25, "cpu": 8, "power": 15},
	]
	assert_int(StateManager.modules.size()).is_equal(2)
	assert_str(StateManager.modules[0].get("name")).is_equal("Laser Mk1")
	assert_str(StateManager.modules[1].get("name")).is_equal("Shield Gen")


func test_module_list_updates_via_state_manager() -> void:
	StateManager.modules = []
	assert_int(StateManager.modules.size()).is_equal(0)

	StateManager.update_state({
		"modules": [
			{"module_id": "mod_a", "name": "Mining Laser", "type": "mining", "wear": 0.0},
		]
	})
	assert_int(StateManager.modules.size()).is_equal(1)
	assert_str(StateManager.modules[0].get("name")).is_equal("Mining Laser")


# --- Docking requirement ---

func test_docking_required_for_module_management() -> void:
	StateManager.location = {}
	assert_bool(StateManager.is_docked()).is_false()

	StateManager.location = {"docked_at": "base_001"}
	assert_bool(StateManager.is_docked()).is_true()


func test_not_docked_when_docked_at_empty_string() -> void:
	StateManager.location = {"docked_at": ""}
	assert_bool(StateManager.is_docked()).is_false()


# --- Wear percentage calculation (static) ---

func test_compute_wear_pct_zero() -> void:
	assert_int(ShipPanel.compute_wear_pct(0.0)).is_equal(0)


func test_compute_wear_pct_half() -> void:
	assert_int(ShipPanel.compute_wear_pct(0.5)).is_equal(50)


func test_compute_wear_pct_full() -> void:
	assert_int(ShipPanel.compute_wear_pct(1.0)).is_equal(100)


func test_compute_wear_pct_fraction() -> void:
	assert_int(ShipPanel.compute_wear_pct(0.33)).is_equal(33)


func test_compute_wear_pct_from_integer_percentage() -> void:
	assert_int(ShipPanel.compute_wear_pct(75)).is_equal(75)
	assert_int(ShipPanel.compute_wear_pct(100)).is_equal(100)


func test_compute_wear_pct_clamps_above_100() -> void:
	assert_int(ShipPanel.compute_wear_pct(150)).is_equal(100)


func test_compute_wear_pct_clamps_below_zero() -> void:
	assert_int(ShipPanel.compute_wear_pct(-0.5)).is_equal(0)
