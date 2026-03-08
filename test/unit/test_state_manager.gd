extends GdUnitTestSuite


func before_test() -> void:
	# Reset StateManager to clean state before each test
	StateManager.player = {}
	StateManager.ship = {}
	StateManager.location = {}
	StateManager.cargo = []
	StateManager.modules = []
	StateManager.skills = {}
	StateManager.missions = {}
	StateManager.hints = []
	StateManager.current_system = {}
	StateManager.nearby_players = []
	StateManager.nearby_pirates = []


# --- Percentage helpers ---

func test_hull_pct_full_health() -> void:
	StateManager.ship = {"hull": 100, "hull_max": 100}
	assert_float(StateManager.hull_pct()).is_equal_approx(1.0, 0.001)


func test_hull_pct_half_health() -> void:
	StateManager.ship = {"hull": 50, "hull_max": 100}
	assert_float(StateManager.hull_pct()).is_equal_approx(0.5, 0.001)


func test_hull_pct_zero_health() -> void:
	StateManager.ship = {"hull": 0, "hull_max": 100}
	assert_float(StateManager.hull_pct()).is_equal_approx(0.0, 0.001)


func test_hull_pct_zero_max_does_not_divide_by_zero() -> void:
	StateManager.ship = {"hull": 0, "hull_max": 0}
	assert_float(StateManager.hull_pct()).is_equal_approx(0.0, 0.001)


func test_shield_pct() -> void:
	StateManager.ship = {"shield": 30, "shield_max": 50}
	assert_float(StateManager.shield_pct()).is_equal_approx(0.6, 0.001)


func test_fuel_pct() -> void:
	StateManager.ship = {"fuel": 25, "fuel_max": 100}
	assert_float(StateManager.fuel_pct()).is_equal_approx(0.25, 0.001)


func test_cargo_pct() -> void:
	StateManager.ship = {"cargo_used": 10, "cargo_max": 40}
	assert_float(StateManager.cargo_pct()).is_equal_approx(0.25, 0.001)


# --- is_docked ---

func test_is_docked_when_docked_at_set() -> void:
	StateManager.location = {"docked_at": "base_001"}
	assert_bool(StateManager.is_docked()).is_true()


func test_is_docked_when_docked_at_empty() -> void:
	StateManager.location = {"docked_at": ""}
	assert_bool(StateManager.is_docked()).is_false()


func test_is_docked_when_docked_at_missing() -> void:
	StateManager.location = {}
	assert_bool(StateManager.is_docked()).is_false()


# --- update_state data population ---

func test_update_state_updates_ship() -> void:
	StateManager.update_state({
		"ship": {"hull": 80, "hull_max": 100, "shield": 50, "shield_max": 50}
	})
	assert_int(StateManager.ship.get("hull")).is_equal(80)


func test_update_state_ignores_empty_dict() -> void:
	StateManager.ship = {"hull": 100, "hull_max": 100}
	StateManager.update_state({})
	assert_int(StateManager.ship.get("hull")).is_equal(100)


func test_update_state_updates_location() -> void:
	StateManager.update_state({"location": {"poi_id": "poi_002", "docked_at": ""}})
	assert_str(StateManager.location.get("poi_id")).is_equal("poi_002")


func test_update_state_updates_cargo() -> void:
	StateManager.update_state({"cargo": [{"item_id": "ore", "quantity": 5}]})
	assert_int(StateManager.cargo.size()).is_equal(1)


# --- Signals ---

func test_update_state_emits_state_updated() -> void:
	var monitor := monitor_signals(StateManager, false)
	StateManager.update_state({"ship": {"hull": 50, "hull_max": 100}})
	await assert_signal(monitor).is_emitted("state_updated")


func test_update_state_emits_ship_updated_when_ship_changes() -> void:
	var monitor := monitor_signals(StateManager, false)
	StateManager.update_state({"ship": {"hull": 50, "hull_max": 100}})
	await assert_signal(monitor).is_emitted("ship_updated")


func test_update_state_emits_location_changed_on_poi_change() -> void:
	StateManager.location = {"poi_id": "poi_001"}
	var monitor := monitor_signals(StateManager, false)
	StateManager.update_state({"location": {"poi_id": "poi_002"}})
	await assert_signal(monitor).is_emitted("location_changed", ["poi_001", "poi_002"])


func test_update_state_does_not_emit_location_changed_for_same_poi() -> void:
	StateManager.location = {"poi_id": "poi_001"}
	var monitor := monitor_signals(StateManager, false)
	StateManager.update_state({"location": {"poi_id": "poi_001"}})
	await assert_signal(monitor).is_not_emitted("location_changed")


# --- set_initial_state ---

func test_set_initial_state_populates_player_and_ship() -> void:
	StateManager.set_initial_state({
		"player": {"id": "p1", "name": "TestPilot"},
		"ship": {"hull": 100, "hull_max": 100},
		"system": {"id": "sys_001", "name": "Sol"},
		"poi": {"id": "poi_001", "name": "Earth Station"},
	})
	assert_str(StateManager.player.get("name")).is_equal("TestPilot")
	assert_str(StateManager.current_system.get("name")).is_equal("Sol")


func test_set_initial_state_emits_state_updated() -> void:
	var monitor := monitor_signals(StateManager, false)
	StateManager.set_initial_state({"player": {"id": "p1"}})
	await assert_signal(monitor).is_emitted("state_updated")


# --- update_nearby ---

func test_update_nearby_populates_players_and_pirates() -> void:
	StateManager.update_nearby({
		"nearby": [{"player_id": "p2", "player_name": "OtherPilot"}],
		"pirates": [{"id": "x1", "name": "Raider"}],
	})
	assert_int(StateManager.nearby_players.size()).is_equal(1)
	assert_int(StateManager.nearby_pirates.size()).is_equal(1)


func test_update_nearby_emits_signal() -> void:
	var monitor := monitor_signals(StateManager, false)
	StateManager.update_nearby({"nearby": [], "pirates": []})
	await assert_signal(monitor).is_emitted("nearby_updated")


func test_update_nearby_clears_previous_data() -> void:
	StateManager.nearby_players = [{"player_id": "old"}]
	StateManager.update_nearby({"nearby": [], "pirates": []})
	assert_int(StateManager.nearby_players.size()).is_equal(0)
