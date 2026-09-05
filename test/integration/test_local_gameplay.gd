extends GdUnitTestSuite

# Fast e2e tests against a local SpaceMolt server (1s ticks).
# Registers a fresh throwaway character each run — no persistence needed.
#
# To run: start local server on port 9090, then:
#   ./bin/godot --headless -s addons/gdUnit4/bin/GdUnitCmdTool.gd \
#       --add "res://test/integration/test_local_gameplay.gd" --ignoreHeadlessMode

const LOCAL_URL := "http://localhost:9090"
const TIMEOUT := 30000  # 30s — 1s ticks mean operations finish fast

var _original_base_url: String = ""
var _original_auth: bool = false
var _username: String = ""
var _password: String = ""


func _is_server_available() -> bool:
	# Quick check if local server is reachable
	var http := HTTPRequest.new()
	add_child(http)
	var done: Array = [false, false]  # [completed, success]
	http.request_completed.connect(func(result: int, _code: int, _h: PackedStringArray, _b: PackedByteArray):
		done[0] = true
		done[1] = (result == HTTPRequest.RESULT_SUCCESS)
	)
	http.request(LOCAL_URL + "/api/v2/session", PackedStringArray(["Content-Type: application/json"]),
		HTTPClient.METHOD_POST, "{}")
	var start := Time.get_ticks_msec()
	while not done[0] and (Time.get_ticks_msec() - start) < 3000:
		await get_tree().process_frame
	http.queue_free()
	return done[1]


func before() -> void:
	_original_base_url = NetworkManager.base_url
	_original_auth = NetworkManager.is_authenticated

	# Point NetworkManager at local server (1s ticks instead of 10s)
	NetworkManager.disconnect_from_server()
	NetworkManager.base_url = LOCAL_URL
	NetworkManager.tick_duration = 1.0
	NetworkManager.is_authenticated = false


func after() -> void:
	NetworkManager.disconnect_from_server()
	NetworkManager.base_url = _original_base_url
	NetworkManager.tick_duration = NetworkManager.DEFAULT_TICK_DURATION
	NetworkManager.is_authenticated = _original_auth
	StateManager.reset()


# --- Helpers ---

func _await_command(action: String, params: Dictionary = {}) -> Dictionary:
	while NetworkManager.is_request_pending:
		await get_tree().process_frame
	var state: Array = [false, {}]
	NetworkManager.send_command(action, params, func(content: Dictionary) -> void:
		state[1] = content
		state[0] = true
	)
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


func _await_storage_command(action: String, params: Dictionary = {}) -> Dictionary:
	while NetworkManager.is_request_pending:
		await get_tree().process_frame
	var state: Array = [false, {}]
	NetworkManager.send_storage_command(action, params, func(content: Dictionary) -> void:
		state[1] = content
		state[0] = true
	)
	var start := Time.get_ticks_msec()
	while not state[0] and (Time.get_ticks_msec() - start) < TIMEOUT:
		await get_tree().process_frame
	return state[1]


func _await_social_command(action: String, params: Dictionary = {}) -> Dictionary:
	while NetworkManager.is_request_pending:
		await get_tree().process_frame
	var state: Array = [false, {}]
	NetworkManager.send_social_command(action, params, func(content: Dictionary) -> void:
		state[1] = content
		state[0] = true
	)
	var start := Time.get_ticks_msec()
	while not state[0] and (Time.get_ticks_msec() - start) < TIMEOUT:
		await get_tree().process_frame
	return state[1]


func _await_catalog_command(params: Dictionary = {}) -> Dictionary:
	while NetworkManager.is_request_pending:
		await get_tree().process_frame
	var state: Array = [false, {}]
	NetworkManager.send_catalog_command(params, func(content: Dictionary) -> void:
		state[1] = content
		state[0] = true
	)
	var start := Time.get_ticks_msec()
	while not state[0] and (Time.get_ticks_msec() - start) < TIMEOUT:
		await get_tree().process_frame
	return state[1]


func _register_character() -> void:
	# Generate a unique throwaway name
	var name_suffix := str(Time.get_ticks_msec()).right(6)
	_username = "TestPilot_%s" % name_suffix

	var done: Array = [false, {}]
	NetworkManager.registration_code = "localtest"
	NetworkManager.create_player(_username, "voidborn", func(content: Dictionary) -> void:
		_password = content.get("password", "")
		StateManager.set_initial_state(content)
		done[1] = content
		done[0] = true
	)
	var start := Time.get_ticks_msec()
	while not done[0] and (Time.get_ticks_msec() - start) < 10000:
		await get_tree().process_frame
	assert_bool(done[0]).is_true()
	assert_str(_password).is_not_empty()
	print("  Registered: %s" % _username)


func _ensure_authenticated() -> void:
	if NetworkManager.is_authenticated:
		return
	await _register_character()
	# Fetch system data
	var sys_done: Array = [false]
	NetworkManager.send_command("get_system", {}, func(content: Dictionary) -> void:
		StateManager.update_system(content)
		sys_done[0] = true
	)
	while not sys_done[0]:
		await get_tree().process_frame


func _ensure_docked() -> void:
	if StateManager.is_docked():
		return
	var station_id: String = ""
	for poi in StateManager.current_system.get("pois", []):
		if poi.get("has_base", false):
			station_id = poi.get("id", "")
			break
	if station_id.is_empty():
		return
	if StateManager.location.get("poi_id", "") != station_id:
		await _await_command("travel", {"id": station_id})
	await _await_command("dock", {"id": station_id})
	await _await_command("get_status")


# --- Tests ---

func test_01_register_and_login() -> void:
	if not await _is_server_available():
		push_warning("Local server not available — skipping local tests")
		return

	await _register_character()

	# Verify state populated
	assert_str(StateManager.player.get("username", StateManager.player.get("name", ""))).is_not_empty()
	assert_float(float(StateManager.ship.get("max_hull", 0))).is_greater(0.0)
	assert_str(StateManager.location.get("poi_id", "")).is_not_empty()

	print("  Player: %s, Ship hull: %s/%s" % [
		StateManager.player.get("username", StateManager.player.get("name", "?")),
		StateManager.ship.get("hull", "?"),
		StateManager.ship.get("max_hull", "?"),
	])


func test_02_get_status() -> void:
	if not await _is_server_available():
		return
	await _ensure_authenticated()

	var content := await _await_command("get_status")
	assert_bool(content.is_empty()).is_false()
	assert_str(StateManager.location.get("poi_id", "")).is_not_empty()
	print("  Status OK at %s" % StateManager.get_current_poi_name())


func test_03_get_system() -> void:
	if not await _is_server_available():
		return
	await _ensure_authenticated()

	var sys_done: Array = [false, {}]
	NetworkManager.send_command("get_system", {}, func(c: Dictionary) -> void:
		StateManager.update_system(c)
		sys_done[0] = true
		sys_done[1] = c
	)
	await await_millis(5000)
	assert_bool(sys_done[0]).is_true()

	var pois: Array = StateManager.current_system.get("pois", [])
	assert_int(pois.size()).is_greater(0)
	print("  System: %s with %d POIs" % [
		StateManager.current_system.get("name", "?"),
		pois.size(),
	])


func test_04_undock_travel_dock_cycle() -> void:
	if not await _is_server_available():
		return
	await _ensure_authenticated()

	# Find home station
	var home_poi: String = ""
	for poi in StateManager.current_system.get("pois", []):
		if poi.get("has_base", false):
			home_poi = poi.get("id", "")
			break

	if home_poi.is_empty():
		# If no base, try current POI
		home_poi = StateManager.location.get("poi_id", "")

	# Make sure we're docked
	if not StateManager.is_docked() and not home_poi.is_empty():
		await _await_command("dock", {"id": home_poi})

	var was_docked := StateManager.is_docked()
	print("  Starting docked=%s at %s" % [was_docked, StateManager.get_current_poi_name()])

	# Undock
	if was_docked:
		await _await_command("undock")
		assert_bool(StateManager.is_docked()).is_false()
		print("  Undocked")

	# Find a different POI to travel to
	var target_poi: String = ""
	var target_name: String = ""
	for poi in StateManager.current_system.get("pois", []):
		if poi.get("id", "") != StateManager.location.get("poi_id", ""):
			target_poi = poi.get("id", "")
			target_name = poi.get("name", "?")
			break

	if not target_poi.is_empty():
		print("  Traveling to %s..." % target_name)
		await _await_command("travel", {"id": target_poi})
		print("  Arrived at %s" % StateManager.get_current_poi_name())

	# Travel back and dock
	if not home_poi.is_empty() and home_poi != StateManager.location.get("poi_id", ""):
		print("  Traveling back to home...")
		await _await_command("travel", {"id": home_poi})

	if not home_poi.is_empty():
		await _await_command("dock", {"id": home_poi})
		await _await_command("get_status")
		print("  Re-docked: %s" % StateManager.is_docked())


func test_05_mine_at_resource_poi() -> void:
	if not await _is_server_available():
		return
	await _ensure_authenticated()

	# Find a minable POI
	var mine_target: String = ""
	var mine_name: String = ""
	for poi in StateManager.current_system.get("pois", []):
		var ptype: String = poi.get("type", "")
		if ptype in ["asteroid_belt", "ice_field", "gas_cloud"]:
			mine_target = poi.get("id", "")
			mine_name = poi.get("name", "?")
			break

	if mine_target.is_empty():
		print("  No minable POI in system — skipping")
		return

	# Undock if docked
	if StateManager.is_docked():
		await _await_command("undock")

	# Travel to mining location
	if StateManager.location.get("poi_id", "") != mine_target:
		print("  Traveling to %s..." % mine_name)
		await _await_command("travel", {"id": mine_target})

	# Mine
	var cargo_before: int = StateManager.ship.get("cargo_used", 0)
	print("  Mining at %s (cargo: %d)..." % [mine_name, cargo_before])
	await _await_command("mine", {"id": mine_target})
	var cargo_after: int = StateManager.ship.get("cargo_used", 0)
	print("  Mining done. Cargo: %d -> %d" % [cargo_before, cargo_after])


func test_06_repair_and_refuel() -> void:
	if not await _is_server_available():
		return
	await _ensure_authenticated()

	# Find a station and dock
	if not StateManager.is_docked():
		var station_id: String = ""
		for poi in StateManager.current_system.get("pois", []):
			if poi.get("has_base", false):
				station_id = poi.get("id", "")
				break
		if not station_id.is_empty():
			if StateManager.location.get("poi_id", "") != station_id:
				await _await_command("travel", {"id": station_id})
			await _await_command("dock", {"id": station_id})

	await _await_command("repair")
	print("  Hull: %d/%d" % [
		StateManager.ship.get("hull", 0),
		StateManager.ship.get("max_hull", 0),
	])

	await _await_command("refuel", {"quantity": 10})
	print("  Fuel: %d/%d" % [
		StateManager.ship.get("fuel", 0),
		StateManager.ship.get("max_fuel", 0),
	])


func test_07_market_view() -> void:
	if not await _is_server_available():
		return
	await _ensure_authenticated()

	# Make sure we're docked
	if not StateManager.is_docked():
		var station_id: String = ""
		for poi in StateManager.current_system.get("pois", []):
			if poi.get("has_base", false):
				station_id = poi.get("id", "")
				break
		if not station_id.is_empty():
			if StateManager.location.get("poi_id", "") != station_id:
				await _await_command("travel", {"id": station_id})
			await _await_command("dock", {"id": station_id})

	var market := await _await_market_command("view_market")
	var items: Array = market.get("items", [])
	print("  Market: %d items" % items.size())
	if items.size() > 0:
		var first: Dictionary = items[0]
		print("  First: %s — buy:%d sell:%d" % [
			first.get("item_name", "?"),
			first.get("buy_price", 0),
			first.get("sell_price", 0),
		])


func test_08_get_skills_and_cargo() -> void:
	if not await _is_server_available():
		return
	await _ensure_authenticated()

	var skills := await _await_command("get_skills")
	print("  Skills keys: %s" % str(skills.keys()))

	var cargo := await _await_command("get_cargo")
	print("  Cargo keys: %s" % str(cargo.keys()))


func test_09_storage_view() -> void:
	if not await _is_server_available():
		return
	await _ensure_authenticated()

	# Make sure we're docked
	await _ensure_docked()

	var storage := await _await_storage_command("view")
	print("  Storage keys: %s" % str(storage.keys()))
	var items: Array = storage.get("items", [])
	print("  Storage items: %d" % items.size())


func test_10_chat_send_and_history() -> void:
	if not await _is_server_available():
		return
	await _ensure_authenticated()

	# Send a chat message — API uses "content" for message body and "target" for channel
	var send_result := await _await_social_command("chat", {"content": "Hello from test!", "target": "local"})
	print("  Chat send keys: %s" % str(send_result.keys()))

	# Fetch history
	var history := await _await_social_command("get_chat_history", {"target": "local"})
	var messages: Array = history.get("messages", [])
	print("  Chat history: %d messages" % messages.size())


func test_11_missions_view() -> void:
	if not await _is_server_available():
		return
	await _ensure_authenticated()

	var missions := await _await_command("get_missions")
	print("  Missions keys: %s" % str(missions.keys()))
	var avail: Array = missions.get("missions", [])
	print("  Available missions: %d" % avail.size())

	# Try to get active missions
	var active := await _await_command("get_active_missions")
	print("  Active missions keys: %s" % str(active.keys()))


func test_12_catalog_browse() -> void:
	if not await _is_server_available():
		return
	await _ensure_authenticated()

	var catalog := await _await_catalog_command({"type": "items", "page": 1, "page_size": 5})
	print("  Catalog keys: %s" % str(catalog.keys()))
	var items: Array = catalog.get("items", [])
	print("  Catalog items: %d" % items.size())
	var total: int = catalog.get("total", 0)
	print("  Total catalog items: %d" % total)
	if items.size() > 0:
		var first: Dictionary = items[0]
		print("  First: %s [%s]" % [first.get("name", "?"), first.get("category", "?")])


func test_13_create_and_cancel_buy_order() -> void:
	if not await _is_server_available():
		return
	await _ensure_authenticated()
	await _ensure_docked()

	# View market to find an item
	var market := await _await_market_command("view_market")
	var items: Array = market.get("items", [])
	if items.is_empty():
		print("  No market items — skipping order test")
		return

	# Pick the cheapest item
	var target_item: Dictionary = items[0]
	for item in items:
		if item.get("buy_price", 999999) < target_item.get("buy_price", 999999) and item.get("buy_price", 0) > 0:
			target_item = item

	var item_id: String = target_item.get("item_id", "")
	var item_name: String = target_item.get("item_name", "?")
	print("  Creating buy order for %s (id: %s)" % [item_name, item_id])

	# Create a buy order at a very low price so it won't fill
	var order_result := await _await_market_command("create_buy_order", {
		"item_id": item_id, "quantity": 1, "price_each": 1
	})
	print("  Buy order result keys: %s" % str(order_result.keys()))

	# View orders to see it listed
	var orders := await _await_market_command("view_orders")
	var my_orders: Array = orders.get("orders", [])
	print("  My orders: %d" % my_orders.size())

	# Cancel the order if it was listed
	if my_orders.size() > 0:
		var order_id: String = my_orders[0].get("order_id", my_orders[0].get("id", ""))
		if not order_id.is_empty():
			var cancel := await _await_market_command("cancel_order", {"order_id": order_id})
			print("  Cancel result keys: %s" % str(cancel.keys()))


func test_14_galaxy_map_and_jump() -> void:
	if not await _is_server_available():
		return
	await _ensure_authenticated()

	# Fetch galaxy map
	var map := await _await_command("get_map")
	assert_bool(map.has("systems")).is_true()
	var systems: Array = map.get("systems", [])
	assert_int(systems.size()).is_greater(0)
	print("  Galaxy map: %d systems" % systems.size())

	# Check first system has expected fields
	var first: Dictionary = systems[0]
	assert_str(first.get("system_id", "")).is_not_empty()
	assert_str(first.get("name", "")).is_not_empty()
	assert_bool(first.has("position")).is_true()
	assert_bool(first.has("connections")).is_true()
	print("  First system: %s (%s), connections: %d" % [
		first.get("name", "?"), first.get("system_id", "?"),
		first.get("connections", []).size()
	])

	# Test StateManager map caching
	StateManager.set_galaxy_map(map)
	assert_bool(StateManager.galaxy_map.has("systems")).is_true()

	# Find current system and a connected system to jump to
	var cur_sys_id := StateManager.get_current_system_id()
	print("  Current system: %s" % cur_sys_id)

	var cur_sys := StateManager.get_system_by_id(cur_sys_id)
	var connections: Array = cur_sys.get("connections", [])
	if connections.is_empty():
		print("  No connections from current system — skipping jump test")
		return

	# Undock if docked
	if StateManager.is_docked():
		await _await_command("undock")

	var jump_target: String = connections[0]
	var target_sys := StateManager.get_system_by_id(jump_target)
	print("  Jumping to: %s (%s)" % [target_sys.get("name", "?"), jump_target])

	StateManager.is_traveling = true
	var jump_result := await _await_command("jump", {"id": jump_target})
	StateManager.is_traveling = false
	print("  Jump result keys: %s" % str(jump_result.keys()))

	# Refresh system data
	var sys_content := await _await_command("get_system")
	StateManager.update_system(sys_content)
	var new_sys_id := StateManager.get_current_system_id()
	print("  Now in system: %s" % new_sys_id)


func test_15_deposit_and_withdraw_storage() -> void:
	if not await _is_server_available():
		return
	await _ensure_authenticated()

	# Mine something first so we have cargo to deposit
	var mine_poi: String = ""
	for poi in StateManager.current_system.get("pois", []):
		var ptype: String = poi.get("type", "")
		if ptype in ["asteroid_belt", "ice_field", "gas_cloud"]:
			mine_poi = poi.get("id", "")
			break

	if mine_poi.is_empty():
		print("  No minable POI — skipping storage test")
		return

	# Undock, travel, mine
	if StateManager.is_docked():
		await _await_command("undock")
	if StateManager.location.get("poi_id", "") != mine_poi:
		await _await_command("travel", {"id": mine_poi})
	await _await_command("mine", {"id": mine_poi})

	var cargo_before: Array = StateManager.cargo.duplicate()
	if cargo_before.is_empty():
		# Get cargo explicitly
		await _await_command("get_cargo")
		cargo_before = StateManager.cargo.duplicate()

	if cargo_before.is_empty():
		print("  No cargo after mining — skipping deposit test")
		return

	# Dock at a station
	await _ensure_docked()

	# Try to deposit first cargo item
	var item: Dictionary = cargo_before[0]
	var item_id: String = item.get("item_id", item.get("id", ""))
	var item_name: String = item.get("item_name", item.get("name", "?"))
	var qty: int = item.get("quantity", 1)
	print("  Depositing %dx %s" % [qty, item_name])

	var deposit := await _await_storage_command("deposit", {"item_id": item_id, "quantity": qty})
	print("  Deposit result keys: %s" % str(deposit.keys()))

	# Check storage
	var storage := await _await_storage_command("view")
	var stored: Array = storage.get("items", [])
	print("  Storage now has %d items" % stored.size())

	# Withdraw it back
	if stored.size() > 0:
		var stored_item: Dictionary = stored[0]
		var s_id: String = stored_item.get("item_id", stored_item.get("id", ""))
		var s_qty: int = stored_item.get("quantity", 1)
		print("  Withdrawing %dx %s" % [s_qty, stored_item.get("item_name", stored_item.get("name", "?"))])
		var withdraw := await _await_storage_command("withdraw", {"item_id": s_id, "quantity": s_qty})
		print("  Withdraw result keys: %s" % str(withdraw.keys()))
