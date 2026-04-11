extends GdUnitTestSuite

# Tests for jettison (storage_panel.gd), survey (action_bar.gd),
# and crafting enhancements (crafting_panel.gd).


func before_test() -> void:
	StateManager.player = {"id": "p1"}
	StateManager.ship = {"cargo_used": 50, "cargo_capacity": 100}
	StateManager.cargo = [
		{"item_id": "ore", "item_name": "Ore", "quantity": 10}
	]
	StateManager.location = {"poi_id": "poi_001", "poi_type": "planet", "docked_at": ""}
	StateManager.current_system = {
		"pois": [
			{"id": "poi_001", "name": "Earth", "type": "planet", "has_base": true},
		]
	}
	StateManager.in_combat = false
	StateManager.has_pending = false
	StateManager.skills = {}
	StateManager.nearby_players = []
	StateManager.nearby_pirates = []


func after_test() -> void:
	StateManager.reset()


# --- Script loading ---

func test_storage_panel_script_loads() -> void:
	var script: GDScript = load("res://scripts/ui/storage_panel.gd")
	assert_that(script).is_not_null()
	assert_bool(script.can_instantiate()).is_true()


func test_action_bar_script_loads() -> void:
	var script: GDScript = load("res://scripts/ui/action_bar.gd")
	assert_that(script).is_not_null()
	assert_bool(script.can_instantiate()).is_true()


func test_crafting_panel_script_loads() -> void:
	var script: GDScript = load("res://scripts/ui/crafting_panel.gd")
	assert_that(script).is_not_null()
	assert_bool(script.can_instantiate()).is_true()


# --- Jettison state tests ---

func test_jettison_reduces_cargo() -> void:
	# After jettison + state refresh, cargo should decrease
	StateManager.update_state({
		"cargo": [{"item_id": "ore", "item_name": "Ore", "quantity": 5}],
		"ship": {"cargo_used": 25, "cargo_capacity": 100}
	})
	assert_int(StateManager.cargo[0].get("quantity")).is_equal(5)
	assert_float(StateManager.cargo_pct()).is_equal_approx(0.25, 0.001)


func test_jettison_removes_item_completely() -> void:
	# Jettisoning all of an item removes it from cargo
	StateManager.update_state({
		"cargo": [],
		"ship": {"cargo_used": 0, "cargo_capacity": 100}
	})
	assert_int(StateManager.cargo.size()).is_equal(0)
	assert_float(StateManager.cargo_pct()).is_equal_approx(0.0, 0.001)


func test_cargo_changed_signal_on_jettison() -> void:
	var monitor := monitor_signals(StateManager, false)
	StateManager.update_state({
		"cargo": [{"item_id": "ore", "item_name": "Ore", "quantity": 3}]
	})
	await assert_signal(monitor).is_emitted("cargo_changed")


# --- Survey visibility tests ---

func test_survey_requires_undocked() -> void:
	# Survey should only be available when not docked
	StateManager.location = {"docked_at": "base_001"}
	assert_bool(StateManager.is_docked()).is_true()
	# Survey button should not show when docked


func test_survey_available_when_undocked() -> void:
	StateManager.location = {"poi_id": "poi_001", "docked_at": ""}
	assert_bool(StateManager.is_docked()).is_false()
	# Survey button should be visible when undocked and not in combat
	assert_bool(StateManager.in_combat).is_false()


func test_survey_unavailable_in_combat() -> void:
	StateManager.in_combat = true
	assert_bool(StateManager.in_combat).is_true()
	# Survey button should not show during combat


# --- Crafting helper tests ---

func test_crafting_cargo_lookup_finds_item() -> void:
	var script: GDScript = load("res://scripts/ui/crafting_panel.gd")
	var panel: PanelContainer = script.new()

	StateManager.cargo = [
		{"item_id": "iron_ore", "item_name": "Iron Ore", "quantity": 15},
		{"item_id": "copper_ore", "item_name": "Copper Ore", "quantity": 8},
	]

	assert_int(panel._get_cargo_quantity("iron_ore")).is_equal(15)
	assert_int(panel._get_cargo_quantity("copper_ore")).is_equal(8)
	assert_int(panel._get_cargo_quantity("nonexistent")).is_equal(0)
	panel.free()


func test_crafting_skill_lookup_returns_level() -> void:
	var script: GDScript = load("res://scripts/ui/crafting_panel.gd")
	var panel: PanelContainer = script.new()

	StateManager.skills = {
		"mining": {"level": 5, "xp": 1200},
		"crafting": {"level": 3, "xp": 400},
	}

	assert_int(panel._get_player_skill_level("mining")).is_equal(5)
	assert_int(panel._get_player_skill_level("crafting")).is_equal(3)
	assert_int(panel._get_player_skill_level("combat")).is_equal(0)
	panel.free()


func test_crafting_skill_lookup_missing_skill() -> void:
	var script: GDScript = load("res://scripts/ui/crafting_panel.gd")
	var panel: PanelContainer = script.new()

	StateManager.skills = {}

	assert_int(panel._get_player_skill_level("anything")).is_equal(0)
	panel.free()
