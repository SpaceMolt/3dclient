extends GdUnitTestSuite

# Tests for mining, docking, undocking, and jump signal behavior on StateManager


func before_test() -> void:
	StateManager.set("is_mining", false)
	StateManager.set("is_docking", false)
	StateManager.set("is_undocking", false)
	StateManager.set("is_jumping", false)


func after_test() -> void:
	StateManager.set("is_mining", false)
	StateManager.set("is_docking", false)
	StateManager.set("is_undocking", false)
	StateManager.set("is_jumping", false)


# --- Mining ---

func test_mining_started_emitted() -> void:
	var monitor := monitor_signals(StateManager, false)
	StateManager.is_mining = true
	await assert_signal(monitor).is_emitted("mining_started")


func test_mining_ended_emitted() -> void:
	StateManager.is_mining = true
	var monitor := monitor_signals(StateManager, false)
	StateManager.is_mining = false
	await assert_signal(monitor).is_emitted("mining_ended")


func test_mining_no_duplicate_when_already_true() -> void:
	StateManager.is_mining = true
	var monitor := monitor_signals(StateManager, false)
	StateManager.is_mining = true
	await assert_signal(monitor).is_not_emitted("mining_started")


func test_mining_no_signal_when_already_false() -> void:
	var monitor := monitor_signals(StateManager, false)
	StateManager.is_mining = false
	await assert_signal(monitor).is_not_emitted("mining_ended")


# --- Docking ---

func test_docking_started_emitted() -> void:
	var monitor := monitor_signals(StateManager, false)
	StateManager.is_docking = true
	await assert_signal(monitor).is_emitted("docking_started")


func test_docking_ended_emitted() -> void:
	StateManager.is_docking = true
	var monitor := monitor_signals(StateManager, false)
	StateManager.is_docking = false
	await assert_signal(monitor).is_emitted("docking_ended")


# --- Undocking ---

func test_undocking_started_emitted() -> void:
	var monitor := monitor_signals(StateManager, false)
	StateManager.is_undocking = true
	await assert_signal(monitor).is_emitted("undocking_started")


func test_undocking_ended_emitted() -> void:
	StateManager.is_undocking = true
	var monitor := monitor_signals(StateManager, false)
	StateManager.is_undocking = false
	await assert_signal(monitor).is_emitted("undocking_ended")


# --- Jumping ---

func test_jump_started_emitted() -> void:
	var monitor := monitor_signals(StateManager, false)
	StateManager.is_jumping = true
	await assert_signal(monitor).is_emitted("jump_started")


func test_jump_ended_emitted() -> void:
	StateManager.is_jumping = true
	var monitor := monitor_signals(StateManager, false)
	StateManager.is_jumping = false
	await assert_signal(monitor).is_emitted("jump_ended")


func test_jump_no_duplicate_when_already_true() -> void:
	StateManager.is_jumping = true
	var monitor := monitor_signals(StateManager, false)
	StateManager.is_jumping = true
	await assert_signal(monitor).is_not_emitted("jump_started")
