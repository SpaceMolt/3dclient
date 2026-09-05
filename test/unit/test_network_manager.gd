extends GdUnitTestSuite

# Unit tests for NetworkManager frame handling. No socket is opened: frames are
# fed straight into _handle_frame with pending entries registered by hand.


func before_test() -> void:
	NetworkManager._pending.clear()
	NetworkManager._update_pending_flag()
	NetworkManager.is_authenticated = false
	NetworkManager.device_code = ""
	NetworkManager.api_key = ""
	NetworkManager._registered = {}
	StateManager.reset()


func after_test() -> void:
	NetworkManager._pending.clear()
	NetworkManager._update_pending_flag()
	NetworkManager.is_authenticated = false
	NetworkManager.device_code = ""
	NetworkManager.tick_duration = NetworkManager.DEFAULT_TICK_DURATION
	NetworkManager._delete_saved_auth()


func _pend(request_id: String, on_complete: Callable, on_error: Callable = Callable()) -> void:
	NetworkManager._pending[request_id] = {"on_complete": on_complete, "on_error": on_error}
	NetworkManager._update_pending_flag()


# --- Connection helpers ---

func test_initial_state() -> void:
	assert_bool(NetworkManager.is_authenticated).is_false()
	assert_bool(NetworkManager.is_request_pending).is_false()
	assert_bool(NetworkManager.is_connected_to_server()).is_false()


func test_ws_url_from_https_base() -> void:
	var original := NetworkManager.base_url
	NetworkManager.base_url = "https://game.spacemolt.com/"
	assert_str(NetworkManager.ws_url()).is_equal("wss://game.spacemolt.com/ws/v2")
	NetworkManager.base_url = "http://localhost:9090"
	assert_str(NetworkManager.ws_url()).is_equal("ws://localhost:9090/ws/v2")
	NetworkManager.base_url = original


func test_split_frames_handles_batched_messages() -> void:
	var frames := NetworkManager.split_frames('{"type":"a"}\n{"type":"b"}\n\n')
	assert_array(frames).contains_exactly(['{"type":"a"}', '{"type":"b"}'])


func test_request_without_socket_reports_error() -> void:
	var got: Array = []
	NetworkManager.send_command("get_status", {}, func(content: Dictionary) -> void: got.append(content))
	assert_array(got).contains_exactly([{}])
	assert_bool(NetworkManager.is_request_pending).is_false()


# --- Pending ack detection ---

func test_pending_ack_top_level() -> void:
	assert_bool(NetworkManager.is_pending_ack({"pending": true, "command": "mine"})).is_true()


func test_pending_ack_nested_in_details() -> void:
	assert_bool(NetworkManager.is_pending_ack({"details": {"pending": true}, "location": {}})).is_true()


func test_pending_ack_false_for_final_results() -> void:
	assert_bool(NetworkManager.is_pending_ack({"ship": {"hull": 10}})).is_false()
	assert_bool(NetworkManager.is_pending_ack("text")).is_false()
	assert_bool(NetworkManager.is_pending_ack(null)).is_false()


# --- Frame routing ---

func test_query_result_settles_pending_and_updates_state() -> void:
	var got: Array = []
	_pend("r1", func(content: Dictionary) -> void: got.append(content))
	assert_bool(NetworkManager.is_request_pending).is_true()
	var monitor := monitor_signals(NetworkManager, false)
	NetworkManager._handle_frame({"type": "result", "request_id": "r1", "payload": {
		"result": "text", "structuredContent": {"ship": {"hull": 42, "max_hull": 100}}}})
	assert_int(got.size()).is_equal(1)
	assert_int(int(got[0]["ship"]["hull"])).is_equal(42)
	assert_int(int(StateManager.ship["hull"])).is_equal(42)
	assert_bool(NetworkManager.is_request_pending).is_false()
	await assert_signal(monitor).is_emitted("request_completed")


func test_non_object_structured_content_is_wrapped() -> void:
	var got: Array = []
	_pend("r1", func(content: Dictionary) -> void: got.append(content))
	NetworkManager._handle_frame({"type": "result", "request_id": "r1", "payload": {"result": "help text", "structuredContent": null}})
	assert_str(got[0]["result"]).is_equal("help text")


func test_mutation_ack_keeps_pending_until_action_result() -> void:
	var got: Array = []
	_pend("r2", func(content: Dictionary) -> void: got.append(content))
	NetworkManager._handle_frame({"type": "result", "request_id": "r2", "payload": {
		"result": "pending", "structuredContent": {"pending": true, "command": "craft", "message": "..."}}})
	assert_array(got).is_empty()
	assert_bool(NetworkManager.is_request_pending).is_true()
	NetworkManager._handle_frame({"type": "action_result", "request_id": "r2", "payload": {
		"command": "craft", "tick": 7, "result": {
			"ship": {"hull": 9}, "cargo": [{"item_id": "x"}], "message": "Crafted 1x Widget",
			"details": {"output_name": "Widget", "quantity": 1}}}})
	assert_int(got.size()).is_equal(1)
	assert_str(got[0]["output_name"]).is_equal("Widget")
	assert_int(int(StateManager.ship["hull"])).is_equal(9)
	assert_int(StateManager.cargo.size()).is_equal(1)
	assert_bool(NetworkManager.is_request_pending).is_false()


func test_engine_action_result_without_details_passes_delta() -> void:
	var got: Array = []
	_pend("r3", func(content: Dictionary) -> void: got.append(content))
	NetworkManager._handle_frame({"type": "action_result", "request_id": "r3", "payload": {
		"command": "mine", "tick": 8, "result": {"cargo": [], "queue": {"has_pending": false}}}})
	assert_bool(got[0].has("cargo")).is_true()
	assert_bool(StateManager.has_pending).is_false()


func test_unmatched_action_result_still_applies_delta() -> void:
	NetworkManager._handle_frame({"type": "action_result", "request_id": "stale", "payload": {
		"command": "mine", "tick": 8, "result": {"ship": {"hull": 3}}}})
	assert_int(int(StateManager.ship["hull"])).is_equal(3)


func test_action_error_settles_with_empty_content() -> void:
	var got: Array = []
	_pend("r4", func(content: Dictionary) -> void: got.append(content))
	NetworkManager._handle_frame({"type": "action_error", "request_id": "r4", "payload": {
		"command": "jump", "tick": 9, "code": "invalid_target", "message": "no"}})
	assert_array(got).contains_exactly([{}])
	assert_bool(NetworkManager.is_request_pending).is_false()


func test_error_prefers_on_error_callback() -> void:
	var errors: Array = []
	var completes: Array = []
	_pend("r5", func(c: Dictionary) -> void: completes.append(c), func(e: Dictionary) -> void: errors.append(e))
	NetworkManager._handle_frame({"type": "error", "request_id": "r5", "payload": {"code": "rate_limited", "message": "slow down"}})
	assert_array(completes).is_empty()
	assert_str(errors[0]["code"]).is_equal("rate_limited")


func test_not_authenticated_error_expires_session() -> void:
	NetworkManager.is_authenticated = true
	var monitor := monitor_signals(NetworkManager, false)
	NetworkManager._handle_frame({"type": "error", "payload": {"code": "not_authenticated", "message": "login first"}})
	await assert_signal(monitor).is_emitted("session_expired")
	assert_bool(NetworkManager.is_authenticated).is_false()


func test_welcome_sets_tick_duration_and_runs_open_callbacks() -> void:
	var ran: Array = []
	NetworkManager._on_open.append(func() -> void: ran.append(true))
	NetworkManager._handle_frame({"type": "welcome", "payload": {"version": "1.0", "tick_rate": 5}})
	assert_float(NetworkManager.tick_duration).is_equal_approx(5.0, 0.001)
	assert_int(ran.size()).is_equal(1)
	assert_bool(NetworkManager._welcomed).is_true()
	NetworkManager._welcomed = false


func test_logged_in_authenticates_and_merges_registered_credentials() -> void:
	NetworkManager.device_code = "dev"
	var got: Array = []
	_pend("r6", func(content: Dictionary) -> void: got.append(content))
	var monitor := monitor_signals(NetworkManager, false)
	NetworkManager._handle_frame({"type": "registered", "payload": {"password": "secret", "player_id": "p1"}})
	NetworkManager._handle_frame({"type": "logged_in", "request_id": "r6", "payload": {"player": {"username": "Vex"}, "ship": {}}})
	await assert_signal(monitor).is_emitted("authenticated", [{"player": {"username": "Vex"}, "ship": {}, "password": "secret", "player_id": "p1"}])
	assert_bool(NetworkManager.is_authenticated).is_true()
	assert_str(NetworkManager.device_code).is_empty()
	assert_str(got[0]["password"]).is_equal("secret")


func test_chat_push_routes_to_ui_manager() -> void:
	var monitor := monitor_signals(UIManager, false)
	NetworkManager._handle_frame({"type": "chat_message", "payload": {"channel": "local", "sender": "Bob", "content": "hi"}})
	await assert_signal(monitor).is_emitted("chat_received", [{"channel": "local", "sender": "Bob", "content": "hi"}])


func test_other_push_becomes_event() -> void:
	var monitor := monitor_signals(UIManager, false)
	NetworkManager._handle_frame({"type": "skill_level_up", "payload": {"skill": "mining", "level": 4}})
	await assert_signal(monitor).is_emitted("event_received", [{"msg_type": "skill_level_up", "message": "mining reached level 4", "data": {"skill": "mining", "level": 4}}])


func test_push_messages_are_readable() -> void:
	assert_str(NetworkManager.push_message("mining_yield", {"quantity": 3, "resource_name": "Vanadium Ore", "remaining_display": "3012 units"})).is_equal("+3 Vanadium Ore (3012 units remaining)")
	assert_str(NetworkManager.push_message("mining_yield", {"quantity": 1, "resource_id": "iron_ore"})).is_equal("+1 iron_ore")
	assert_str(NetworkManager.push_message("achievement_unlocked", {"achievements": [{"name": "First Ore"}, {"name": "Long Haul"}]})).is_equal("Achievement: First Ore, Long Haul")
	assert_str(NetworkManager.push_message("server_restart_warning", {"message": "Restart in 5 min"})).is_equal("Restart in 5 min")
	assert_str(NetworkManager.push_message("unknown_thing", {})).is_empty()


func test_close_while_authenticated_expires_session_and_fails_pending() -> void:
	NetworkManager.is_authenticated = true
	var got: Array = []
	_pend("r7", func(content: Dictionary) -> void: got.append(content))
	var monitor := monitor_signals(NetworkManager, false)
	NetworkManager._handle_close(1006, "gone")
	await assert_signal(monitor).is_emitted("session_expired")
	assert_array(got).contains_exactly([{}])
	assert_bool(NetworkManager.is_authenticated).is_false()
	assert_bool(NetworkManager.is_request_pending).is_false()


# --- Device login polling ---

func _device_timer() -> Timer:
	return NetworkManager.get_node("DeviceLinkTimer") as Timer


func test_pending_poll_reschedules_timer_at_server_interval_or_floor() -> void:
	NetworkManager.device_code = "dev123"
	NetworkManager._on_device_link_polled({"status": "authorization_pending", "interval": 5})
	assert_bool(_device_timer().is_stopped()).is_false()
	assert_float(_device_timer().wait_time).is_equal_approx(5.0, 0.001)
	NetworkManager._on_device_link_polled({"status": "authorization_pending", "interval": 1})
	assert_float(_device_timer().wait_time).is_equal_approx(NetworkManager.DEVICE_LINK_POLL_INTERVAL, 0.001)
	_device_timer().stop()


func test_denied_poll_emits_auth_error_and_stops() -> void:
	NetworkManager.device_code = "dev123"
	var monitor := monitor_signals(NetworkManager, false)
	NetworkManager._on_device_link_polled({"status": "access_denied"})
	await assert_signal(monitor).is_emitted("auth_error", ["Login declined in the browser."])
	assert_str(NetworkManager.device_code).is_empty()


func test_expired_poll_emits_auth_error() -> void:
	NetworkManager.device_code = "dev123"
	var monitor := monitor_signals(NetworkManager, false)
	NetworkManager._on_device_link_polled({"status": "expired_token"})
	await assert_signal(monitor).is_emitted("auth_error", ["Login link expired. Try again."])


# --- Saved API key ---

func test_save_and_load_api_key() -> void:
	NetworkManager.api_key = "sk_test_key123"
	NetworkManager._save_auth()
	NetworkManager.api_key = ""
	NetworkManager._load_auth()
	assert_str(NetworkManager.api_key).is_equal("sk_test_key123")
	assert_bool(NetworkManager.has_saved_auth()).is_true()


func test_clear_auth_deletes_saved_key() -> void:
	NetworkManager.api_key = "sk_test_key123"
	NetworkManager._save_auth()
	NetworkManager.clear_auth()
	assert_bool(NetworkManager.has_saved_auth()).is_false()
	assert_str(NetworkManager.api_key).is_empty()


# --- Reconnect after a dropped socket ---

func _reset_reconnect() -> void:
	NetworkManager._relogin = Callable()
	NetworkManager._reconnect_attempt = 0
	NetworkManager.reconnect_delay = 2.0


func test_close_with_relogin_retries_instead_of_expiring() -> void:
	NetworkManager.is_authenticated = true
	NetworkManager.reconnect_delay = 0.01
	var calls: Array = []
	NetworkManager._relogin = func() -> void: calls.append(true)
	var monitor := monitor_signals(NetworkManager, false)
	NetworkManager._handle_close(1006, "gone")
	assert_int(NetworkManager._reconnect_attempt).is_equal(1)
	await await_millis(100)
	assert_int(calls.size()).is_equal(1)
	await assert_signal(monitor).wait_until(50).is_not_emitted("session_expired")
	_reset_reconnect()


func test_session_replaced_never_retries() -> void:
	NetworkManager.is_authenticated = true
	NetworkManager._relogin = func() -> void: pass
	var monitor := monitor_signals(NetworkManager, false)
	NetworkManager._handle_close(NetworkManager.CLOSE_SESSION_REPLACED, "replaced")
	await assert_signal(monitor).is_emitted("session_expired")
	assert_int(NetworkManager._reconnect_attempt).is_equal(0)
	_reset_reconnect()


func test_retries_stop_at_the_limit() -> void:
	NetworkManager.is_authenticated = false
	NetworkManager._relogin = func() -> void: pass
	NetworkManager._reconnect_attempt = NetworkManager.MAX_RECONNECT_ATTEMPTS
	var monitor := monitor_signals(NetworkManager, false)
	NetworkManager._handle_close(-2, "re-login failed")
	await assert_signal(monitor).is_emitted("session_expired")
	assert_int(NetworkManager._reconnect_attempt).is_equal(0)
	_reset_reconnect()


func test_successful_login_resets_attempts_and_logout_forgets_relogin() -> void:
	NetworkManager._reconnect_attempt = 3
	NetworkManager._handle_frame({"type": "logged_in", "payload": {"player": {}}})
	assert_int(NetworkManager._reconnect_attempt).is_equal(0)
	NetworkManager._relogin = func() -> void: pass
	NetworkManager.logout()
	assert_bool(NetworkManager._relogin.is_valid()).is_false()
	_reset_reconnect()
