extends GdUnitTestSuite

# End-to-end integration test that plays through core game actions against the
# live SpaceMolt API using real credentials. Exercises the full flow:
# NetworkManager → API → StateManager → verify state.
#
# This test modifies real game state (undock, travel, mine, dock, trade, etc.)
# so it should leave the character back where it started (docked at home).

const CRED_PATH := "res://.test_credentials"
const TIMEOUT := 120000 # 2min per command — travel/mine block server-side for multiple ticks

var _username: String = ""
var _password: String = ""
var _original_auth: bool = false


func _load_credentials() -> bool:
	if not FileAccess.file_exists(CRED_PATH):
		push_warning("No .test_credentials file — skipping e2e tests")
		return false
	var file := FileAccess.open(CRED_PATH, FileAccess.READ)
	while not file.eof_reached():
		var line := file.get_line().strip_edges()
		if line.begins_with("SPACEMOLT_USERNAME="):
			_username = line.get_slice("=", 1).trim_prefix('"').trim_suffix('"')
		elif line.begins_with("SPACEMOLT_PASSWORD="):
			_password = line.get_slice("=", 1)
	return not _username.is_empty() and not _password.is_empty()


func before() -> void:
	# Save original NetworkManager state so we can restore after tests
	_original_auth = NetworkManager.is_authenticated


func after() -> void:
	# Restore original state — don't leave test session active
	NetworkManager.disconnect_from_server()
	NetworkManager.is_authenticated = _original_auth
	StateManager.reset()


# --- Helper to wait for a command to complete ---

func _await_command(action: String, params: Dictionary = {}) -> Dictionary:
	while NetworkManager.is_request_pending:
		await get_tree().process_frame
	var state: Array = [false, {}] # [done, content]
	NetworkManager.send_command(action, params, func(content: Dictionary) -> void:
		state[1] = content
		state[0] = true
	)
	# Wait for the on_complete callback (fires after state refresh for mutations)
	var start := Time.get_ticks_msec()
	while not state[0] and (Time.get_ticks_msec() - start) < TIMEOUT:
		await get_tree().process_frame
	if not state[0]:
		push_warning("_await_command('%s') timed out after %ds" % [action, TIMEOUT / 1000])
	return state[1]


func _await_market_command(action: String, params: Dictionary = {}) -> Dictionary:
	while NetworkManager.is_request_pending:
		await get_tree().process_frame
	var state: Array = [false, {}]
	NetworkManager.send_market_command(action, params, func(content: Dictionary) -> void:
		state[1] = content
		state[0] = true
	)
	var start := Time.get_ticks_msec()
	while not state[0] and (Time.get_ticks_msec() - start) < TIMEOUT:
		await get_tree().process_frame
	return state[1]


# --- Login ---

func test_01_login_and_state_populated() -> void:
	if not _load_credentials():
		return

	# Login over the socket; the logged_in frame carries the initial state
	var login_state: Array = [false, {}] # [done, content]
	var on_auth := func(content: Dictionary) -> void:
		StateManager.set_initial_state(content)
		login_state[0] = true
		login_state[1] = content
	NetworkManager.authenticated.connect(on_auth, CONNECT_ONE_SHOT)
	NetworkManager.login_password(_username, _password)
	var start := Time.get_ticks_msec()
	while not login_state[0] and (Time.get_ticks_msec() - start) < 10000:
		await get_tree().process_frame
	assert_bool(login_state[0]).is_true()

	# Verify StateManager got populated from LoginResponse
	assert_str(StateManager.player.get("username", "")).is_equal(_username)
	assert_str(StateManager.player.get("id", "")).is_not_empty()
	assert_str(StateManager.player.get("empire", "")).is_not_empty()

	# Ship should have real values (JSON parser may return int or float)
	var max_hull = StateManager.ship.get("max_hull", 0)
	var max_shield = StateManager.ship.get("max_shield", 0)
	var max_fuel = StateManager.ship.get("max_fuel", 0)
	var cargo_cap = StateManager.ship.get("cargo_capacity", 0)
	assert_float(float(max_hull)).is_greater(0.0)
	assert_float(float(max_shield)).is_greater(0.0)
	assert_float(float(max_fuel)).is_greater(0.0)
	assert_float(float(cargo_cap)).is_greater(0.0)

	# Debug: print ship data so we can see what the API returned
	print("  Ship: hull=%s/%s shield=%s/%s fuel=%s/%s cargo=%s/%s" % [
		StateManager.ship.get("hull", "?"), max_hull,
		StateManager.ship.get("shield", "?"), max_shield,
		StateManager.ship.get("fuel", "?"), max_fuel,
		StateManager.ship.get("cargo_used", "?"), cargo_cap,
	])
	print("  hull_pct=%f shield_pct=%f fuel_pct=%f cargo_pct=%f" % [
		StateManager.hull_pct(), StateManager.shield_pct(),
		StateManager.fuel_pct(), StateManager.cargo_pct(),
	])

	# Percentage helpers should work with real data
	assert_float(StateManager.hull_pct()).is_greater(0.0)
	assert_float(StateManager.hull_pct()).is_less_equal(1.0)

	# Location should be set
	assert_str(StateManager.location.get("poi_id", "")).is_not_empty()
	assert_str(StateManager.get_current_poi_name()).is_not_empty()

	# System should be populated
	assert_str(StateManager.current_system.get("name", "")).is_not_empty()
	assert_int(StateManager.current_system.get("pois", []).size()).is_greater(0)

	print("  Login OK: %s in %s at %s" % [
		StateManager.player.get("username"),
		StateManager.current_system.get("name"),
		StateManager.get_current_poi_name(),
	])


func test_02_get_status_updates_state() -> void:
	if not _load_credentials():
		return
	if not NetworkManager.is_authenticated:
		await _do_login()

	var content := await _await_command("get_status")
	assert_bool(content.is_empty()).is_false()

	# Should have location with system and poi info
	assert_str(StateManager.location.get("system_id", "")).is_not_empty()
	assert_str(StateManager.location.get("poi_id", "")).is_not_empty()

	# Nearby data should have been extracted from location
	# (may be empty arrays but should be present)
	assert_bool(StateManager.nearby_players is Array).is_true()
	assert_bool(StateManager.nearby_pirates is Array).is_true()

	print("  get_status OK: %d nearby players, %d pirates" % [
		StateManager.nearby_players.size(),
		StateManager.nearby_pirates.size(),
	])


func test_03_get_system_populates_pois() -> void:
	if not _load_credentials():
		return
	if not NetworkManager.is_authenticated:
		await _do_login()

	var state: Array = [false, {}]
	NetworkManager.send_command("get_system", {}, func(c: Dictionary) -> void:
		StateManager.update_system(c)
		state[0] = true
		state[1] = c
	)
	await await_millis(5000)
	assert_bool(state[0]).is_true()

	assert_str(StateManager.current_system.get("name", "")).is_not_empty()
	var pois: Array = StateManager.current_system.get("pois", [])
	assert_int(pois.size()).is_greater(0)

	# Each POI should have id, name, type, position
	var first_poi: Dictionary = pois[0]
	assert_str(first_poi.get("id", "")).is_not_empty()
	assert_str(first_poi.get("name", "")).is_not_empty()
	assert_str(first_poi.get("type", "")).is_not_empty()
	assert_bool(first_poi.has("position")).is_true()

	print("  get_system OK: %s with %d POIs" % [
		StateManager.current_system.get("name"),
		pois.size(),
	])


func test_04_undock_travel_mine_dock_cycle() -> void:
	if not _load_credentials():
		return
	if not NetworkManager.is_authenticated:
		await _do_login()

	# Find the home station (a dockable POI)
	var home_poi: String = ""
	for poi in StateManager.current_system.get("pois", []):
		if poi.get("has_base", false):
			home_poi = poi.get("id", "")
			break
	assert_str(home_poi).is_not_empty()

	# Make sure we're at the station and docked
	if StateManager.location.get("poi_id", "") != home_poi:
		print("  Traveling to station %s..." % home_poi)
		await _await_command("travel", {"id": home_poi})
	if not StateManager.is_docked():
		await _await_command("dock", {"id": home_poi})

	assert_bool(StateManager.is_docked()).is_true()
	print("  Starting docked at: %s" % StateManager.get_current_poi_name())

	# Undock
	var undock_result := await _await_command("undock")
	assert_bool(StateManager.is_docked()).is_false()
	print("  Undocked successfully")

	# Find a minable POI (asteroid_belt, ice_field, gas_cloud)
	var mine_target: String = ""
	var mine_name: String = ""
	for poi in StateManager.current_system.get("pois", []):
		var ptype: String = poi.get("type", "")
		if ptype in ["asteroid_belt", "ice_field", "gas_cloud"]:
			mine_target = poi.get("id", "")
			mine_name = poi.get("name", "")
			break

	if mine_target.is_empty():
		print("  No minable POI in system — skipping mine test")
	else:
		# Travel to mining location
		print("  Traveling to %s..." % mine_name)
		var travel_result := await _await_command("travel", {"id": mine_target})
		assert_str(StateManager.location.get("poi_id", "")).is_equal(mine_target)
		print("  Arrived at %s" % mine_name)

		# Mine (may fail with "Resources depleted" — that's OK)
		var fuel_before: int = StateManager.ship.get("fuel", 0)
		print("  Mining... (fuel before: %d)" % fuel_before)
		var mine_result := await _await_command("mine", {"id": mine_target})
		var cargo_used: int = StateManager.ship.get("cargo_used", 0)
		print("  Mine result. Cargo: %d/%d" % [
			cargo_used,
			StateManager.ship.get("cargo_capacity", 0),
		])

		# Travel back to home
		print("  Traveling back to %s..." % home_poi)
		await _await_command("travel", {"id": home_poi})

	# Dock back at the station
	await _await_command("dock", {"id": home_poi})
	# Refresh state after docking (dock response may not include full location)
	await _await_command("get_status")
	assert_bool(StateManager.is_docked()).is_true()
	print("  Re-docked at home. Fuel: %d/%d" % [
		StateManager.ship.get("fuel", 0),
		StateManager.ship.get("max_fuel", 0),
	])


func test_05_repair_and_refuel_while_docked() -> void:
	if not _load_credentials():
		return
	if not NetworkManager.is_authenticated:
		await _do_login()

	# Make sure we're docked at a station
	if not StateManager.is_docked():
		var station_id: String = ""
		for poi in StateManager.current_system.get("pois", []):
			if poi.get("has_base", false):
				station_id = poi.get("id", "")
				break
		if StateManager.location.get("poi_id", "") != station_id:
			await _await_command("travel", {"id": station_id})
		await _await_command("dock", {"id": station_id})

	# Repair
	var hull_before: int = StateManager.ship.get("hull", 0)
	await _await_command("repair")
	var hull_after: int = StateManager.ship.get("hull", 0)
	print("  Repair: hull %d -> %d" % [hull_before, hull_after])

	# Refuel
	var fuel_before: int = StateManager.ship.get("fuel", 0)
	await _await_command("refuel", {"quantity": 10})
	var fuel_after: int = StateManager.ship.get("fuel", 0)
	print("  Refuel: fuel %d -> %d" % [fuel_before, fuel_after])


func test_06_market_view() -> void:
	if not _load_credentials():
		return
	if not NetworkManager.is_authenticated:
		await _do_login()

	if not StateManager.is_docked():
		var station_id: String = ""
		for poi in StateManager.current_system.get("pois", []):
			if poi.get("has_base", false):
				station_id = poi.get("id", "")
				break
		if StateManager.location.get("poi_id", "") != station_id:
			await _await_command("travel", {"id": station_id})
		await _await_command("dock", {"id": station_id})

	var market := await _await_market_command("view_market")
	assert_bool(market.is_empty()).is_false()

	var items: Array = market.get("items", [])
	print("  Market has %d items" % items.size())
	if items.size() > 0:
		var first: Dictionary = items[0]
		print("  First item: %s — buy: %d, sell: %d" % [
			first.get("name", "?"),
			first.get("buy_price", 0),
			first.get("sell_price", 0),
		])


func test_07_get_skills() -> void:
	if not _load_credentials():
		return
	if not NetworkManager.is_authenticated:
		await _do_login()

	var content := await _await_command("get_skills")
	# Skills may be empty for a new character but should not error
	print("  Skills response received (keys: %s)" % str(content.keys()))


func test_08_get_cargo() -> void:
	if not _load_credentials():
		return
	if not NetworkManager.is_authenticated:
		await _do_login()

	var content := await _await_command("get_cargo")
	print("  Cargo response received (keys: %s)" % str(content.keys()))


# --- Helper to login if not already authenticated ---

func _do_login() -> void:
	if not _load_credentials():
		return

	var login_state: Array = [false]
	NetworkManager.authenticated.connect(func(content: Dictionary) -> void:
		StateManager.set_initial_state(content)
		login_state[0] = true
	, CONNECT_ONE_SHOT)
	NetworkManager.login_password(_username, _password)
	while not login_state[0]:
		await get_tree().process_frame

	# Fetch system data
	var sys_state: Array = [false]
	NetworkManager.send_command("get_system", {}, func(sys: Dictionary) -> void:
		StateManager.update_system(sys)
		sys_state[0] = true
	)
	while not sys_state[0]:
		await get_tree().process_frame
