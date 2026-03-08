extends Node

const BASE_URL = "https://game.spacemolt.com"
const POLL_INTERVAL = 10.0
const SESSION_PATH = "user://session.cfg"

var session_id: String = ""
var is_authenticated: bool = false
var is_request_pending: bool = false

signal request_started
signal request_completed
signal authenticated(initial_state: Dictionary)
signal auth_error(message: String)
signal session_expired


func _ready() -> void:
	var poll_timer := Timer.new()
	poll_timer.name = "PollTimer"
	poll_timer.wait_time = POLL_INTERVAL
	poll_timer.timeout.connect(_poll_state)
	add_child(poll_timer)


func create_session(on_complete: Callable) -> void:
	_raw_post("/api/v2/session", {}, func(data: Dictionary) -> void:
		if data.has("error") and data["error"] != null:
			auth_error.emit(data["error"].get("message", "Session creation failed"))
			return
		session_id = data["session"]["id"]
		on_complete.call()
	)


func login(username: String, password: String) -> void:
	api_post(
		"/api/v2/spacemolt_auth/login",
		{"username": username, "password": password},
		func(content: Dictionary) -> void:
			is_authenticated = true
			_save_session(username, password)
			_start_poll()
			authenticated.emit(content)
	)


func register(username: String, empire: String, code: String) -> void:
	api_post(
		"/api/v2/spacemolt_auth/register",
		{"username": username, "empire": empire, "registration_code": code},
		func(content: Dictionary) -> void:
			is_authenticated = true
			# Save the generated password from the response for future logins
			var password: String = content.get("password", "")
			var uname: String = content.get("player", {}).get("name", "")
			if not password.is_empty() and not uname.is_empty():
				_save_session(uname, password)
			_start_poll()
			authenticated.emit(content)
	)


func logout() -> void:
	if session_id.is_empty():
		return
	api_post("/api/v2/spacemolt_auth/logout", {}, func(_content: Dictionary) -> void:
		pass
	)
	_clear_session()
	_delete_saved_session()
	StateManager.reset()
	session_expired.emit()


func try_restore_session(on_success: Callable, on_failure: Callable) -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SESSION_PATH) != OK:
		on_failure.call()
		return

	var username: String = cfg.get_value("auth", "username", "")
	var password: String = cfg.get_value("auth", "password", "")
	if username.is_empty() or password.is_empty():
		on_failure.call()
		return

	# Create a new session then try to login with saved credentials
	create_session(func():
		api_post(
			"/api/v2/spacemolt_auth/login",
			{"username": username, "password": password},
			func(content: Dictionary) -> void:
				is_authenticated = true
				_save_session(username, password)
				_start_poll()
				on_success.call(content)
		)
	)


func has_saved_session() -> bool:
	return FileAccess.file_exists(SESSION_PATH)


func send_command(action: String, params: Dictionary, on_complete: Callable = Callable()) -> void:
	api_post("/api/v2/spacemolt/" + action, params, func(content: Dictionary) -> void:
		StateManager.update_state(content)
		if on_complete.is_valid():
			on_complete.call(content)
		_reset_poll()
	)


func send_battle_command(action: String, params: Dictionary, on_complete: Callable = Callable()) -> void:
	api_post("/api/v2/spacemolt_battle/" + action, params, func(content: Dictionary) -> void:
		if on_complete.is_valid():
			on_complete.call(content)
		_reset_poll()
	)


func send_market_command(action: String, params: Dictionary, on_complete: Callable = Callable()) -> void:
	api_post("/api/v2/spacemolt_market/" + action, params, func(content: Dictionary) -> void:
		if on_complete.is_valid():
			on_complete.call(content)
		_reset_poll()
	)


func api_post(path: String, body: Dictionary, on_success: Callable) -> void:
	if session_id.is_empty():
		push_error("NetworkManager: api_post called without session_id")
		return

	is_request_pending = true
	request_started.emit()

	var http := HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(
		func(result: int, _code: int, _headers: PackedStringArray, body_bytes: PackedByteArray) -> void:
			http.queue_free()
			is_request_pending = false
			request_completed.emit()

			if result != HTTPRequest.RESULT_SUCCESS:
				UIManager.show_error("Network error (code %d)" % result)
				return

			var data = JSON.parse_string(body_bytes.get_string_from_utf8())
			if data == null:
				UIManager.show_error("Invalid response from server")
				return

			if data.has("notifications") and data["notifications"] is Array:
				_handle_notifications(data["notifications"])

			# Show the narrative result text in event log (if present and non-empty)
			var result_text: String = data.get("result", "")
			if not result_text.is_empty():
				UIManager.add_event({"msg_type": "result", "message": result_text})

			if data.has("error") and data["error"] != null:
				_handle_error(data["error"])
				return

			on_success.call(data.get("structuredContent", {}))
	)

	var headers := PackedStringArray([
		"Content-Type: application/json",
		"X-Session-Id: " + session_id,
	])
	http.request(BASE_URL + path, headers, HTTPClient.METHOD_POST, JSON.stringify(body))


func _handle_error(error: Dictionary) -> void:
	var code: String = error.get("code", "")
	var message: String = error.get("message", "Unknown error")

	match code:
		"session_expired", "not_authenticated":
			UIManager.show_error("Session expired. Please log in again.")
			_clear_session()
			session_expired.emit()
		"rate_limited":
			var retry_after: float = error.get("retry_after", 5.0)
			UIManager.show_error("Rate limited. Try again in %ds." % int(retry_after))
		"in_combat":
			UIManager.show_error("Cannot do that during combat.")
		"not_in_combat":
			UIManager.show_error("Not in combat.")
		"insufficient_fuel":
			UIManager.show_error("Not enough fuel.")
		"already_docked":
			UIManager.show_info("Already docked.")
		"invalid_target":
			UIManager.show_error("Invalid target. Refreshing...")
			# Refresh nearby data since our target list is stale
			send_command("get_nearby", {}, func(content: Dictionary) -> void:
				StateManager.update_nearby(content)
			)
		_:
			UIManager.show_error(message)


func _raw_post(path: String, body: Dictionary, callback: Callable) -> void:
	var http := HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(
		func(result: int, _code: int, _headers: PackedStringArray, body_bytes: PackedByteArray) -> void:
			http.queue_free()
			if result != HTTPRequest.RESULT_SUCCESS:
				UIManager.show_error("Network error during session creation")
				return
			var data = JSON.parse_string(body_bytes.get_string_from_utf8())
			if data == null:
				UIManager.show_error("Invalid response from server")
				return
			callback.call(data)
	)
	var headers := PackedStringArray(["Content-Type: application/json"])
	http.request(BASE_URL + path, headers, HTTPClient.METHOD_POST, JSON.stringify(body))


func _poll_state() -> void:
	if not is_authenticated or is_request_pending:
		return
	api_post("/api/v2/spacemolt/get_status", {}, func(content: Dictionary) -> void:
		StateManager.update_state(content)
	)


func _handle_notifications(notifications: Array) -> void:
	for notif in notifications:
		match notif.get("msg_type", ""):
			"chat_message":
				UIManager.add_chat(notif.get("data", {}))
			_:
				UIManager.add_event(notif)


func _start_poll() -> void:
	var timer := get_node_or_null("PollTimer") as Timer
	if timer:
		timer.start()


func _reset_poll() -> void:
	var timer := get_node_or_null("PollTimer") as Timer
	if timer:
		timer.stop()
		timer.start()


func _stop_poll() -> void:
	var timer := get_node_or_null("PollTimer") as Timer
	if timer:
		timer.stop()


func _clear_session() -> void:
	is_authenticated = false
	session_id = ""
	_stop_poll()


func _save_session(username: String, password: String) -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("auth", "username", username)
	cfg.set_value("auth", "password", password)
	cfg.save(SESSION_PATH)


func _delete_saved_session() -> void:
	if FileAccess.file_exists(SESSION_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SESSION_PATH))
