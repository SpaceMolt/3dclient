extends GdUnitTestSuite


func test_hull_pct_full_health() -> void:
	StateManager.ship = {"hull": 100, "max_hull": 100}
	assert_float(StateManager.hull_pct()).is_equal_approx(1.0, 0.001)


func test_hull_pct_half_health() -> void:
	StateManager.ship = {"hull": 50, "max_hull": 100}
	assert_float(StateManager.hull_pct()).is_equal_approx(0.5, 0.001)


func test_hull_pct_zero_health() -> void:
	StateManager.ship = {"hull": 0, "max_hull": 100}
	assert_float(StateManager.hull_pct()).is_equal_approx(0.0, 0.001)


func test_hull_pct_zero_max_does_not_divide_by_zero() -> void:
	StateManager.ship = {"hull": 0, "max_hull": 0}
	assert_float(StateManager.hull_pct()).is_equal_approx(0.0, 0.001)


func test_shield_pct() -> void:
	StateManager.ship = {"shield": 30, "max_shield": 50}
	assert_float(StateManager.shield_pct()).is_equal_approx(0.6, 0.001)


func test_fuel_pct() -> void:
	StateManager.ship = {"fuel": 25, "max_fuel": 100}
	assert_float(StateManager.fuel_pct()).is_equal_approx(0.25, 0.001)


func test_cargo_pct() -> void:
	StateManager.ship = {"cargo_used": 10, "cargo_capacity": 40}
	assert_float(StateManager.cargo_pct()).is_equal_approx(0.25, 0.001)


func test_is_docked_when_docked_at_set() -> void:
	StateManager.location = {"docked_at": "base_001"}
	assert_bool(StateManager.is_docked()).is_true()


func test_is_docked_when_docked_at_empty() -> void:
	StateManager.location = {"docked_at": ""}
	assert_bool(StateManager.is_docked()).is_false()


func test_is_docked_when_docked_at_missing() -> void:
	StateManager.location = {}
	assert_bool(StateManager.is_docked()).is_false()


func test_update_state_updates_ship() -> void:
	StateManager.ship = {}
	StateManager.update_state({
		"ship": {"hull": 80, "max_hull": 100, "shield": 50, "max_shield": 50}
	})
	assert_int(StateManager.ship.get("hull")).is_equal(80)


func test_update_state_emits_state_updated() -> void:
	var signal_watcher := monitor_signals(StateManager)
	StateManager.update_state({"ship": {"hull": 50, "max_hull": 100}})
	await assert_signal(signal_watcher).is_emitted("state_updated")


func test_update_state_emits_ship_updated_when_ship_changes() -> void:
	var signal_watcher := monitor_signals(StateManager)
	StateManager.update_state({"ship": {"hull": 50, "max_hull": 100}})
	await assert_signal(signal_watcher).is_emitted("ship_updated")


func test_update_state_emits_location_changed_on_poi_change() -> void:
	StateManager.location = {"poi_id": "poi_001"}
	var signal_watcher := monitor_signals(StateManager)
	StateManager.update_state({"location": {"poi_id": "poi_002"}})
	await assert_signal(signal_watcher).is_emitted("location_changed", ["poi_001", "poi_002"])


func test_update_state_does_not_emit_location_changed_for_same_poi() -> void:
	StateManager.location = {"poi_id": "poi_001"}
	var signal_watcher := monitor_signals(StateManager)
	StateManager.update_state({"location": {"poi_id": "poi_001"}})
	await assert_signal(signal_watcher).is_not_emitted("location_changed")


func test_update_state_ignores_empty_dict() -> void:
	StateManager.ship = {"hull": 100, "max_hull": 100}
	StateManager.update_state({})
	assert_int(StateManager.ship.get("hull")).is_equal(100)


func test_set_initial_state_populates_player_and_ship() -> void:
	StateManager.set_initial_state({
		"player": {"id": "p1", "username": "TestPilot"},
		"ship": {"hull": 100, "max_hull": 100},
		"system": {"id": "sys_001", "name": "Sol"},
		"poi": {"id": "poi_001", "name": "Earth Station"},
	})
	assert_str(StateManager.player.get("username")).is_equal("TestPilot")
	assert_str(StateManager.current_system.get("name")).is_equal("Sol")


func test_update_nearby_populates_players_and_pirates() -> void:
	StateManager.update_nearby({
		"nearby": [{"player_id": "p2", "username": "OtherPilot"}],
		"pirates": [{"pirate_id": "x1", "name": "Raider"}],
	})
	assert_int(StateManager.nearby_players.size()).is_equal(1)
	assert_int(StateManager.nearby_pirates.size()).is_equal(1)


func test_update_nearby_emits_signal() -> void:
	var signal_watcher := monitor_signals(StateManager)
	StateManager.update_nearby({"nearby": [], "pirates": []})
	await assert_signal(signal_watcher).is_emitted("nearby_updated")
