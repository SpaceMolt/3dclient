extends GdUnitTestSuite

# Tests for AutoTravel and RouteBanner scripts.


func before_test() -> void:
	StateManager.player = {"id": "p1"}
	StateManager.current_system = {"id": "sys_001"}


func after_test() -> void:
	StateManager.reset()


# --- AutoTravel script loading ---

func test_auto_travel_script_loads() -> void:
	var script: GDScript = load("res://scripts/game/auto_travel.gd")
	assert_that(script).is_not_null()
	assert_bool(script.can_instantiate()).is_true()


# --- RouteBanner script loading ---

func test_route_banner_script_loads() -> void:
	var script: GDScript = load("res://scripts/ui/route_banner.gd")
	assert_that(script).is_not_null()
	assert_bool(script.can_instantiate()).is_true()


# --- Progress tracking ---

func test_auto_travel_initial_progress() -> void:
	var at := AutoTravel.new()
	var progress := at.get_progress()
	assert_int(progress.current).is_equal(0)
	assert_int(progress.total).is_equal(0)
	assert_bool(progress.is_active).is_false()
	at.free()


func test_auto_travel_not_active_initially() -> void:
	var at := AutoTravel.new()
	assert_bool(at.is_active()).is_false()
	at.free()


# --- Abort behavior ---

func test_abort_sets_inactive() -> void:
	var at := AutoTravel.new()
	at._is_active = true
	at._route = [{"system_id": "s1", "name": "Test"}]
	at.abort()
	assert_bool(at.is_active()).is_false()
	at.free()


func test_abort_emits_signal() -> void:
	var at := AutoTravel.new()
	at._is_active = true
	at._route = [{"system_id": "s1", "name": "Test"}]
	var signal_monitor := monitor_signals(at)
	at.abort()
	assert_signal(at).is_emitted("route_aborted", ["Aborted by player"])
	at.free()


func test_abort_when_inactive_does_nothing() -> void:
	var at := AutoTravel.new()
	at._is_active = false
	at.abort()
	assert_bool(at.is_active()).is_false()
	assert_signal(at).is_not_emitted("route_aborted")
	at.free()


# --- Empty route ---

func test_empty_route_does_nothing() -> void:
	var at := AutoTravel.new()
	at.start_route([])
	assert_bool(at.is_active()).is_false()
	at.free()


# --- get_current_target ---

func test_get_current_target_empty_when_no_route() -> void:
	var at := AutoTravel.new()
	var target := at.get_current_target()
	assert_bool(target.is_empty()).is_true()
	at.free()


func test_get_current_target_returns_first_waypoint() -> void:
	var at := AutoTravel.new()
	at._route = [
		{"system_id": "s1", "name": "Alpha"},
		{"system_id": "s2", "name": "Beta"},
	]
	at._current_step = 0
	var target := at.get_current_target()
	assert_str(target.get("system_id", "")).is_equal("s1")
	assert_str(target.get("name", "")).is_equal("Alpha")
	at.free()


func test_get_current_target_advances_with_step() -> void:
	var at := AutoTravel.new()
	at._route = [
		{"system_id": "s1", "name": "Alpha"},
		{"system_id": "s2", "name": "Beta"},
	]
	at._current_step = 1
	var target := at.get_current_target()
	assert_str(target.get("system_id", "")).is_equal("s2")
	at.free()


func test_get_current_target_empty_past_end() -> void:
	var at := AutoTravel.new()
	at._route = [{"system_id": "s1", "name": "Alpha"}]
	at._current_step = 1
	var target := at.get_current_target()
	assert_bool(target.is_empty()).is_true()
	at.free()


# --- Progress after partial travel ---

func test_progress_reflects_step() -> void:
	var at := AutoTravel.new()
	at._route = [
		{"system_id": "s1", "name": "Alpha"},
		{"system_id": "s2", "name": "Beta"},
		{"system_id": "s3", "name": "Gamma"},
	]
	at._current_step = 2
	at._is_active = true
	var progress := at.get_progress()
	assert_int(progress.current).is_equal(2)
	assert_int(progress.total).is_equal(3)
	assert_bool(progress.is_active).is_true()
	at.free()
