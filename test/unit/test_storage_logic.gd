extends GdUnitTestSuite

# Tests for storage-related state logic — verifying that cargo updates
# flow correctly after deposit/withdraw operations.


func before_test() -> void:
	StateManager.player = {}
	StateManager.ship = {}
	StateManager.location = {}
	StateManager.cargo = []
	StateManager.current_system = {}


# --- Cargo state after deposit ---

func test_cargo_updated_after_deposit_refreshes_state() -> void:
	# Simulate having cargo before deposit
	StateManager.cargo = [
		{"item_id": "copper_ore", "item_name": "Copper Ore", "quantity": 10},
		{"item_id": "iron_ore", "item_name": "Iron Ore", "quantity": 5},
	]
	assert_int(StateManager.cargo.size()).is_equal(2)

	# Simulate state update after get_status (as deposit flow does)
	StateManager.update_state({
		"cargo": [
			{"item_id": "copper_ore", "item_name": "Copper Ore", "quantity": 6},
			{"item_id": "iron_ore", "item_name": "Iron Ore", "quantity": 5},
		]
	})
	assert_int(StateManager.cargo.size()).is_equal(2)
	assert_int(StateManager.cargo[0].get("quantity")).is_equal(6)


func test_cargo_empty_after_depositing_all() -> void:
	StateManager.cargo = [
		{"item_id": "copper_ore", "item_name": "Copper Ore", "quantity": 4},
	]
	# Simulate full deposit + state refresh
	StateManager.update_state({"cargo": []})
	assert_int(StateManager.cargo.size()).is_equal(0)


func test_cargo_grows_after_withdraw() -> void:
	StateManager.cargo = []
	# Simulate withdraw + state refresh adding items to cargo
	StateManager.update_state({
		"cargo": [
			{"item_id": "copper_ore", "item_name": "Copper Ore", "quantity": 4},
		]
	})
	assert_int(StateManager.cargo.size()).is_equal(1)
	assert_int(StateManager.cargo[0].get("quantity")).is_equal(4)


func test_cargo_changed_signal_emitted_on_deposit() -> void:
	var monitor := monitor_signals(StateManager, false)
	StateManager.update_state({
		"cargo": [{"item_id": "ore", "quantity": 3}]
	})
	await assert_signal(monitor).is_emitted("cargo_changed")


func test_cargo_changed_signal_emitted_on_withdraw() -> void:
	StateManager.cargo = [{"item_id": "ore", "quantity": 5}]
	var monitor := monitor_signals(StateManager, false)
	StateManager.update_state({
		"cargo": [{"item_id": "ore", "quantity": 8}]
	})
	await assert_signal(monitor).is_emitted("cargo_changed")


# --- Docking prerequisite ---

func test_is_docked_required_for_storage() -> void:
	# Storage operations should only be available when docked
	StateManager.location = {}
	assert_bool(StateManager.is_docked()).is_false()

	StateManager.location = {"docked_at": "base_001"}
	assert_bool(StateManager.is_docked()).is_true()


func test_cargo_pct_after_partial_deposit() -> void:
	StateManager.ship = {"cargo_used": 50, "cargo_capacity": 100}
	assert_float(StateManager.cargo_pct()).is_equal_approx(0.5, 0.001)

	# After depositing some cargo, cargo_used decreases
	StateManager.ship = {"cargo_used": 30, "cargo_capacity": 100}
	assert_float(StateManager.cargo_pct()).is_equal_approx(0.3, 0.001)


func test_cargo_pct_after_withdraw() -> void:
	StateManager.ship = {"cargo_used": 20, "cargo_capacity": 100}
	assert_float(StateManager.cargo_pct()).is_equal_approx(0.2, 0.001)

	# After withdrawing, cargo_used increases
	StateManager.ship = {"cargo_used": 40, "cargo_capacity": 100}
	assert_float(StateManager.cargo_pct()).is_equal_approx(0.4, 0.001)
