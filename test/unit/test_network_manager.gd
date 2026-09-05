extends GdUnitTestSuite

# Unit tests for NetworkManager logic that doesn't require live HTTP.
# HTTP behaviour is covered by integration tests with a local dev server.


func after_test() -> void:
	NetworkManager.api_key = ""
	NetworkManager._delete_saved_auth()


func test_session_id_empty_on_init() -> void:
	# Verify clean initial state — session requires explicit creation
	assert_str(NetworkManager.session_id).is_empty()


func test_is_authenticated_false_on_init() -> void:
	assert_bool(NetworkManager.is_authenticated).is_false()


func test_is_request_pending_false_on_init() -> void:
	assert_bool(NetworkManager.is_request_pending).is_false()


func test_poll_timer_exists_in_tree() -> void:
	var timer := NetworkManager.get_node_or_null("PollTimer")
	assert_object(timer).is_not_null()
	assert_object(timer).is_instanceof(Timer)


func test_poll_timer_interval_is_10s() -> void:
	var timer := NetworkManager.get_node("PollTimer") as Timer
	assert_float(timer.wait_time).is_equal_approx(10.0, 0.001)


func test_poll_timer_not_running_before_auth() -> void:
	# Timer should not be running until login succeeds
	var timer := NetworkManager.get_node("PollTimer") as Timer
	assert_bool(timer.is_stopped()).is_true()


func test_api_post_requires_session_id() -> void:
	# api_post with no session_id should push an error rather than crashing
	var original_session := NetworkManager.session_id
	NetworkManager.session_id = ""

	# Should not throw — just log an error internally
	NetworkManager.api_post("/test", {}, func(_c): pass)

	NetworkManager.session_id = original_session


func test_save_and_load_auth() -> void:
	NetworkManager.api_key = "sk_test_key123"
	NetworkManager._save_auth()
	NetworkManager.api_key = ""
	NetworkManager._load_auth()
	assert_str(NetworkManager.api_key).is_equal("sk_test_key123")


func test_has_saved_auth_true() -> void:
	NetworkManager.api_key = "sk_test_key123"
	NetworkManager._save_auth()
	assert_bool(NetworkManager.has_saved_auth()).is_true()


func test_has_saved_auth_false_when_no_file() -> void:
	NetworkManager._delete_saved_auth()
	assert_bool(NetworkManager.has_saved_auth()).is_false()


func test_delete_saved_auth() -> void:
	NetworkManager.api_key = "sk_test_key123"
	NetworkManager._save_auth()
	NetworkManager._delete_saved_auth()
	assert_bool(NetworkManager.has_saved_auth()).is_false()


func test_initial_state_no_api_key() -> void:
	assert_str(NetworkManager.api_key).is_equal("")
	assert_bool(NetworkManager.is_authenticated).is_false()


# --- Device login (browser link) ---

func _device_timer() -> Timer:
	return NetworkManager.get_node("DeviceLinkTimer") as Timer


func _reset_device_login() -> void:
	NetworkManager._clear_session()
	NetworkManager._delete_saved_auth()


func test_device_link_timer_is_one_shot() -> void:
	var timer := _device_timer()
	assert_object(timer).is_not_null()
	assert_bool(timer.one_shot).is_true()
	assert_bool(timer.is_stopped()).is_true()


func test_pending_poll_reschedules_timer() -> void:
	NetworkManager.device_code = "dev123"
	NetworkManager._on_device_link_polled({"status": "authorization_pending", "interval": 5})
	assert_bool(_device_timer().is_stopped()).is_false()
	assert_float(_device_timer().wait_time).is_equal_approx(5.0, 0.001)
	assert_bool(NetworkManager.is_authenticated).is_false()
	_reset_device_login()


func test_pending_poll_clamps_tiny_interval() -> void:
	NetworkManager.device_code = "dev123"
	NetworkManager._on_device_link_polled({"status": "authorization_pending", "interval": 0})
	assert_float(_device_timer().wait_time).is_equal_approx(1.0, 0.001)
	_reset_device_login()


func test_denied_poll_emits_auth_error_and_stops() -> void:
	NetworkManager.device_code = "dev123"
	var monitor := monitor_signals(NetworkManager, false)
	NetworkManager._on_device_link_polled({"status": "access_denied"})
	await assert_signal(monitor).is_emitted("auth_error", ["Login declined in the browser."])
	assert_str(NetworkManager.device_code).is_empty()
	assert_bool(NetworkManager.is_authenticated).is_false()
	_reset_device_login()


func test_expired_poll_emits_auth_error() -> void:
	NetworkManager.device_code = "dev123"
	var monitor := monitor_signals(NetworkManager, false)
	NetworkManager._on_device_link_polled({"status": "expired_token"})
	await assert_signal(monitor).is_emitted("auth_error", ["Login link expired. Try again."])
	assert_str(NetworkManager.device_code).is_empty()
	_reset_device_login()


func test_approved_poll_logs_in_and_saves_session() -> void:
	NetworkManager.device_code = "dev123"
	NetworkManager.session_id = "sess_abc"
	var monitor := monitor_signals(NetworkManager, false)
	var login := {"player": {"username": "Vex"}, "ship": {"hull": 100}}
	NetworkManager._on_device_link_polled(login)
	await assert_signal(monitor).is_emitted("authenticated", [login])
	assert_bool(NetworkManager.is_authenticated).is_true()
	assert_str(NetworkManager.device_code).is_empty()
	assert_bool(NetworkManager.get_node("PollTimer").is_stopped()).is_false()
	# Session persists so a relaunch within the server's idle window skips the browser
	NetworkManager.session_id = ""
	NetworkManager._load_auth()
	assert_str(NetworkManager.session_id).is_equal("sess_abc")
	_reset_device_login()


func test_stale_poll_result_ignored_after_cancel() -> void:
	NetworkManager.device_code = ""
	var monitor := monitor_signals(NetworkManager, false)
	NetworkManager._on_device_link_polled({"player": {"username": "Vex"}})
	await assert_signal(monitor).wait_until(200).is_not_emitted("authenticated")
	assert_bool(NetworkManager.is_authenticated).is_false()


func test_clear_session_stops_device_polling() -> void:
	NetworkManager.device_code = "dev123"
	NetworkManager._schedule_device_poll(3.0)
	NetworkManager._clear_session()
	assert_str(NetworkManager.device_code).is_empty()
	assert_bool(_device_timer().is_stopped()).is_true()


func test_save_and_load_session_id() -> void:
	NetworkManager.session_id = "sess_xyz"
	NetworkManager._save_auth()
	NetworkManager.session_id = ""
	NetworkManager._load_auth()
	assert_str(NetworkManager.session_id).is_equal("sess_xyz")
	_reset_device_login()
