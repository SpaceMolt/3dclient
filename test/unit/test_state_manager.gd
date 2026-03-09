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
	StateManager.in_combat = false
	StateManager.battle = {}
	StateManager.galaxy_map = {}
	StateManager.travel_dest_poi_id = ""
	StateManager.travel_dest_poi_name = ""
	StateManager.travel_origin_poi_id = ""
	StateManager.set("is_traveling", false)
	StateManager.set("is_mining", false)
	StateManager.set("is_docking", false)
	StateManager.set("is_undocking", false)
	StateManager.set("is_jumping", false)


# --- Percentage helpers ---

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


func test_is_docked_when_docked_at_null() -> void:
	StateManager.location = {"docked_at": null}
	assert_bool(StateManager.is_docked()).is_false()


# --- update_state data population ---

func test_update_state_updates_ship() -> void:
	StateManager.update_state({
		"ship": {"hull": 80, "max_hull": 100, "shield": 50, "max_shield": 50}
	})
	assert_int(StateManager.ship.get("hull")).is_equal(80)


func test_update_state_ignores_empty_dict() -> void:
	StateManager.ship = {"hull": 100, "max_hull": 100}
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
	StateManager.update_state({"ship": {"hull": 50, "max_hull": 100}})
	await assert_signal(monitor).is_emitted("state_updated")


func test_update_state_emits_ship_updated_when_ship_changes() -> void:
	var monitor := monitor_signals(StateManager, false)
	StateManager.update_state({"ship": {"hull": 50, "max_hull": 100}})
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
		"ship": {"hull": 100, "max_hull": 100},
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
		"nearby": [{"player_id": "p2", "username": "OtherPilot"}],
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


# --- Battle state ---

func test_update_battle_sets_in_combat() -> void:
	StateManager.update_battle({"is_participant": true, "battle_id": "b1"})
	assert_bool(StateManager.in_combat).is_true()
	assert_str(StateManager.battle.get("battle_id")).is_equal("b1")


func test_update_battle_clears_combat_when_not_participant() -> void:
	StateManager.in_combat = true
	StateManager.update_battle({"is_participant": false})
	assert_bool(StateManager.in_combat).is_false()


func test_update_battle_emits_combat_started() -> void:
	var monitor := monitor_signals(StateManager, false)
	StateManager.update_battle({"is_participant": true})
	await assert_signal(monitor).is_emitted("combat_started")


func test_update_battle_emits_combat_ended() -> void:
	StateManager.in_combat = true
	var monitor := monitor_signals(StateManager, false)
	StateManager.update_battle({"is_participant": false})
	await assert_signal(monitor).is_emitted("combat_ended")


func test_update_battle_emits_battle_updated() -> void:
	var monitor := monitor_signals(StateManager, false)
	StateManager.update_battle({"is_participant": true})
	await assert_signal(monitor).is_emitted("battle_updated")


func test_get_my_participant_returns_matching_entry() -> void:
	StateManager.player = {"id": "p1"}
	StateManager.battle = {
		"participants": [
			{"player_id": "p1", "stance": "fire", "zone": "2"},
			{"player_id": "p2", "stance": "evade", "zone": "3"},
		]
	}
	var me := StateManager.get_my_participant()
	assert_str(me.get("stance")).is_equal("fire")


func test_get_my_participant_returns_empty_when_not_found() -> void:
	StateManager.player = {"id": "p1"}
	StateManager.battle = {"participants": []}
	var me := StateManager.get_my_participant()
	assert_bool(me.is_empty()).is_true()


func test_clear_battle_resets_state() -> void:
	StateManager.in_combat = true
	StateManager.battle = {"battle_id": "b1"}
	StateManager.clear_battle()
	assert_bool(StateManager.in_combat).is_false()
	assert_bool(StateManager.battle.is_empty()).is_true()


# --- set_initial_state location normalization ---

func test_set_initial_state_normalizes_poi_to_location() -> void:
	StateManager.set_initial_state({
		"player": {"id": "p1"},
		"system": {"id": "sys_001", "name": "Sol"},
		"poi": {"id": "poi_001", "name": "Earth Station", "type": "station", "position": {"x": 1.0, "y": 2.0}},
	})
	assert_str(StateManager.location.get("poi_id")).is_equal("poi_001")
	assert_str(StateManager.location.get("system_id")).is_equal("sys_001")
	assert_str(StateManager.location.get("name")).is_equal("Earth Station")


func test_set_initial_state_is_docked_false_when_not_at_base() -> void:
	StateManager.set_initial_state({
		"player": {"id": "p1"},
		"poi": {"id": "poi_001", "name": "Station"},
	})
	assert_bool(StateManager.is_docked()).is_false()


func test_set_initial_state_is_docked_when_player_docked_at_base() -> void:
	StateManager.set_initial_state({
		"player": {"id": "p1", "docked_at_base": "base_001"},
		"poi": {"id": "poi_001", "name": "Station"},
	})
	assert_bool(StateManager.is_docked()).is_true()


# --- get_current_poi_name ---

func test_get_current_poi_name_from_location() -> void:
	StateManager.location = {"name": "Mars Base", "poi_id": "poi_002"}
	assert_str(StateManager.get_current_poi_name()).is_equal("Mars Base")


func test_get_current_poi_name_from_system_pois() -> void:
	StateManager.location = {"poi_id": "poi_003"}
	StateManager.current_system = {
		"pois": [
			{"id": "poi_003", "name": "Asteroid Belt"},
			{"id": "poi_004", "name": "Wormhole"},
		]
	}
	assert_str(StateManager.get_current_poi_name()).is_equal("Asteroid Belt")


func test_get_current_poi_name_returns_empty_when_not_found() -> void:
	StateManager.location = {"poi_id": "poi_999"}
	StateManager.current_system = {"pois": []}
	assert_str(StateManager.get_current_poi_name()).is_empty()


# --- update_system ---

func test_update_system_with_system_key() -> void:
	StateManager.update_system({"system": {"id": "sys_001", "name": "Sol", "pois": []}})
	assert_str(StateManager.current_system.get("name")).is_equal("Sol")


func test_update_system_with_top_level_pois() -> void:
	StateManager.update_system({"id": "sys_002", "name": "Alpha", "pois": [{"id": "p1"}]})
	assert_str(StateManager.current_system.get("name")).is_equal("Alpha")
	assert_int(StateManager.current_system.get("pois", []).size()).is_equal(1)


func test_update_system_emits_state_updated() -> void:
	var monitor := monitor_signals(StateManager, false)
	StateManager.update_system({"system": {"name": "Sol"}})
	await assert_signal(monitor).is_emitted("state_updated")


# --- reset ---

func test_reset_clears_all_state() -> void:
	StateManager.player = {"id": "p1", "name": "Test"}
	StateManager.ship = {"hull": 50, "max_hull": 100}
	StateManager.location = {"poi_id": "poi_001"}
	StateManager.cargo = [{"item": "ore"}]
	StateManager.in_combat = true
	StateManager.battle = {"battle_id": "b1"}
	StateManager.current_system = {"name": "Sol"}
	StateManager.nearby_players = [{"player_id": "p2"}]

	StateManager.reset()

	assert_bool(StateManager.player.is_empty()).is_true()
	assert_bool(StateManager.ship.is_empty()).is_true()
	assert_bool(StateManager.location.is_empty()).is_true()
	assert_int(StateManager.cargo.size()).is_equal(0)
	assert_bool(StateManager.in_combat).is_false()
	assert_bool(StateManager.battle.is_empty()).is_true()
	assert_bool(StateManager.current_system.is_empty()).is_true()
	assert_int(StateManager.nearby_players.size()).is_equal(0)
	assert_bool(StateManager.is_traveling).is_false()


func test_set_galaxy_map_stores_systems() -> void:
	var map_data := {
		"systems": [
			{"system_id": "sol", "name": "Sol", "position": {"x": 0, "y": 0}, "connections": ["alpha"]},
			{"system_id": "alpha", "name": "Alpha Centauri", "position": {"x": 10, "y": 5}, "connections": ["sol"]},
		],
		"total_count": 2
	}
	StateManager.set_galaxy_map(map_data)

	assert_int(StateManager.galaxy_map.get("systems", []).size()).is_equal(2)
	assert_int(StateManager.galaxy_map.get("total_count", 0)).is_equal(2)


func test_get_system_by_id_finds_system() -> void:
	StateManager.galaxy_map = {
		"systems": [
			{"system_id": "sol", "name": "Sol"},
			{"system_id": "alpha", "name": "Alpha Centauri"},
		]
	}

	var found := StateManager.get_system_by_id("alpha")
	assert_str(found.get("name", "")).is_equal("Alpha Centauri")

	var not_found := StateManager.get_system_by_id("nonexistent")
	assert_bool(not_found.is_empty()).is_true()


func test_get_current_system_id_from_current_system() -> void:
	StateManager.current_system = {"id": "sol"}
	assert_str(StateManager.get_current_system_id()).is_equal("sol")


func test_get_current_system_id_from_location() -> void:
	StateManager.current_system = {}
	StateManager.location = {"system_id": "alpha"}
	assert_str(StateManager.get_current_system_id()).is_equal("alpha")


func test_update_state_handles_missions_as_array() -> void:
	StateManager.update_state({
		"missions": [{"id": "m1", "title": "Test Mission"}]
	})
	# Missions should be wrapped in a dict when provided as an array
	assert_bool(StateManager.missions is Dictionary).is_true()
	var mission_list: Array = StateManager.missions.get("list", [])
	assert_int(mission_list.size()).is_equal(1)


func test_is_traveling_state() -> void:
	assert_bool(StateManager.is_traveling).is_false()
	StateManager.is_traveling = true
	assert_bool(StateManager.is_traveling).is_true()
	StateManager.reset()
	assert_bool(StateManager.is_traveling).is_false()


# --- Mining signals ---

func test_mining_started_signal_emitted() -> void:
	var monitor := monitor_signals(StateManager, false)
	StateManager.is_mining = true
	await assert_signal(monitor).is_emitted("mining_started")


func test_mining_ended_signal_emitted() -> void:
	StateManager.set("is_mining", true)
	var monitor := monitor_signals(StateManager, false)
	StateManager.is_mining = false
	await assert_signal(monitor).is_emitted("mining_ended")


func test_mining_no_duplicate_signal() -> void:
	StateManager.set("is_mining", true)
	var monitor := monitor_signals(StateManager, false)
	StateManager.is_mining = true
	await assert_signal(monitor).is_not_emitted("mining_started")


func test_reset_clears_mining() -> void:
	StateManager.is_mining = true
	StateManager.reset()
	assert_bool(StateManager.is_mining).is_false()


# --- Docking signals ---

func test_docking_started_signal_emitted() -> void:
	var monitor := monitor_signals(StateManager, false)
	StateManager.is_docking = true
	await assert_signal(monitor).is_emitted("docking_started")


func test_docking_ended_signal_emitted() -> void:
	StateManager.set("is_docking", true)
	var monitor := monitor_signals(StateManager, false)
	StateManager.is_docking = false
	await assert_signal(monitor).is_emitted("docking_ended")


func test_undocking_started_signal_emitted() -> void:
	var monitor := monitor_signals(StateManager, false)
	StateManager.is_undocking = true
	await assert_signal(monitor).is_emitted("undocking_started")


func test_undocking_ended_signal_emitted() -> void:
	StateManager.set("is_undocking", true)
	var monitor := monitor_signals(StateManager, false)
	StateManager.is_undocking = false
	await assert_signal(monitor).is_emitted("undocking_ended")


func test_reset_clears_docking_undocking() -> void:
	StateManager.is_docking = true
	StateManager.is_undocking = true
	StateManager.reset()
	assert_bool(StateManager.is_docking).is_false()
	assert_bool(StateManager.is_undocking).is_false()


# --- Jumping signal ---

func test_jumping_started_signal_emitted() -> void:
	var monitor := monitor_signals(StateManager, false)
	StateManager.is_jumping = true
	await assert_signal(monitor).is_emitted("jump_started")


func test_jumping_ended_signal_emitted() -> void:
	StateManager.set("is_jumping", true)
	var monitor := monitor_signals(StateManager, false)
	StateManager.is_jumping = false
	await assert_signal(monitor).is_emitted("jump_ended")


func test_reset_clears_jumping() -> void:
	StateManager.is_jumping = true
	StateManager.reset()
	assert_bool(StateManager.is_jumping).is_false()


# --- begin_travel / end_travel / abort_travel ---

func test_begin_travel_sets_state() -> void:
	StateManager.location = {"poi_id": "origin_poi"}
	StateManager.begin_travel("dest_poi", "Destination Name")
	assert_bool(StateManager.is_traveling).is_true()
	assert_str(StateManager.travel_dest_poi_id).is_equal("dest_poi")
	assert_str(StateManager.travel_dest_poi_name).is_equal("Destination Name")
	assert_str(StateManager.travel_origin_poi_id).is_equal("origin_poi")


func test_begin_travel_emits_travel_started_with_dest() -> void:
	StateManager.location = {"poi_id": "origin_poi"}
	var monitor := monitor_signals(StateManager, false)
	StateManager.begin_travel("dest_poi", "Destination Name")
	await assert_signal(monitor).is_emitted("travel_started", ["dest_poi", "Destination Name"])


func test_end_travel_clears_state() -> void:
	StateManager.location = {"poi_id": "origin_poi"}
	StateManager.begin_travel("dest_poi", "Destination Name")
	StateManager.end_travel()
	assert_bool(StateManager.is_traveling).is_false()
	assert_str(StateManager.travel_dest_poi_id).is_empty()
	assert_str(StateManager.travel_dest_poi_name).is_empty()
	assert_str(StateManager.travel_origin_poi_id).is_empty()


func test_end_travel_emits_travel_ended() -> void:
	StateManager.location = {"poi_id": "origin_poi"}
	StateManager.begin_travel("dest_poi", "Dest")
	var monitor := monitor_signals(StateManager, false)
	StateManager.end_travel()
	await assert_signal(monitor).is_emitted("travel_ended")


func test_abort_travel_emits_travel_aborted_with_origin() -> void:
	StateManager.location = {"poi_id": "origin_poi"}
	StateManager.begin_travel("dest_poi", "Dest")
	var monitor := monitor_signals(StateManager, false)
	StateManager.abort_travel()
	await assert_signal(monitor).is_emitted("travel_aborted", ["origin_poi"])


func test_abort_travel_clears_state() -> void:
	StateManager.location = {"poi_id": "origin_poi"}
	StateManager.begin_travel("dest_poi", "Dest")
	StateManager.abort_travel()
	assert_bool(StateManager.is_traveling).is_false()
	assert_str(StateManager.travel_dest_poi_id).is_empty()
	assert_str(StateManager.travel_origin_poi_id).is_empty()


func test_reset_clears_travel_fields() -> void:
	StateManager.location = {"poi_id": "origin_poi"}
	StateManager.begin_travel("dest_poi", "Dest")
	StateManager.reset()
	assert_bool(StateManager.is_traveling).is_false()
	assert_str(StateManager.travel_dest_poi_id).is_empty()
	assert_str(StateManager.travel_dest_poi_name).is_empty()
	assert_str(StateManager.travel_origin_poi_id).is_empty()
