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
