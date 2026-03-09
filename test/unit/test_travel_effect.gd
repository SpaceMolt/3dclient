extends GdUnitTestSuite

# Tests for the travel signal behavior on StateManager


func before_test() -> void:
	# Reset via the internal variable to avoid triggering signals during setup
	StateManager.set("is_traveling", false)


func after_test() -> void:
	StateManager.set("is_traveling", false)


func test_travel_started_signal_emitted_when_is_traveling_set_true() -> void:
	var monitor := monitor_signals(StateManager, false)
	StateManager.begin_travel("test_poi", "Test POI")
	await assert_signal(monitor).is_emitted("travel_started", ["test_poi", "Test POI"])


func test_travel_ended_signal_emitted_when_is_traveling_set_false() -> void:
	StateManager.begin_travel("test_poi", "Test POI")
	var monitor := monitor_signals(StateManager, false)
	StateManager.end_travel()
	await assert_signal(monitor).is_emitted("travel_ended")


func test_no_signal_when_setting_same_value() -> void:
	# Already false, setting false again should not emit
	var monitor := monitor_signals(StateManager, false)
	StateManager.is_traveling = false
	await assert_signal(monitor).is_not_emitted("travel_ended")


func test_no_duplicate_signal_when_setting_true_twice() -> void:
	StateManager.begin_travel("test_poi", "Test POI")
	var monitor := monitor_signals(StateManager, false)
	# Setting is_traveling = true again should not re-emit
	StateManager.is_traveling = true
	await assert_signal(monitor).is_not_emitted("travel_started")
