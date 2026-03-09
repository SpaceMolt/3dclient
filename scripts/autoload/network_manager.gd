extends Node

const DEFAULT_BASE_URL = "https://game.spacemolt.com"
const DEFAULT_TICK_DURATION = 10.0
const POLL_INTERVAL = 10.0
const SESSION_PATH = "user://session.cfg"
const LOG_PATH = "user://spacemolt.log"

var base_url: String = DEFAULT_BASE_URL
var tick_duration: float = DEFAULT_TICK_DURATION

var session_id: String = ""
var is_authenticated: bool = false
var is_request_pending: bool = false
var _is_restoring_session: bool = false
var _log_file: FileAccess = null

signal request_started
signal request_completed
signal authenticated(initial_state: Dictionary)
signal auth_error(message: String)
signal session_expired


func _ready() -> void:
	_open_log()
	_log("NetworkManager ready, base_url=%s" % base_url)
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
	var saved_session: String = cfg.get_value("auth", "session_id", "")
	if username.is_empty() or password.is_empty():
		on_failure.call()
		return

	# Try reusing the saved session_id first (avoids a login call)
	if not saved_session.is_empty():
		session_id = saved_session
		_is_restoring_session = true
		# Temporarily intercept session_expired to fall back to full login
		var fallback := func():
			_is_restoring_session = false
			session_id = ""
			_full_login(username, password, on_success, on_failure)
		session_expired.connect(fallback, CONNECT_ONE_SHOT)
		# Test the session with a lightweight call
		api_post("/api/v2/spacemolt/get_status", {}, func(content: Dictionary) -> void:
			_is_restoring_session = false
			# Disconnect the fallback since we succeeded
			if session_expired.is_connected(fallback):
				session_expired.disconnect(fallback)
			is_authenticated = true
			StateManager.update_state(content)
			_save_session(username, password)
			_start_poll()
			on_success.call(content)
		)
		return

	# No saved session_id — create a new session and login
	_full_login(username, password, on_success, on_failure)


func has_saved_session() -> bool:
	return FileAccess.file_exists(SESSION_PATH)


func send_command(action: String, params: Dictionary, on_complete: Callable = Callable()) -> void:
	var _on_error := func(_error: Dictionary) -> void:
		# Even on error, refresh state (server may have changed) and notify caller
		_refresh_state_then(func():
			if on_complete.is_valid():
				on_complete.call({})
		)
		_reset_poll()
	api_post("/api/v2/spacemolt/" + action, params, func(content: Dictionary) -> void:
		# Try to update state from the response (works for get_status, get_nearby, etc.)
		StateManager.update_state(content)
		# Mutation responses (travel, dock, undock, mine, etc.) don't include
		# V2GameState fields, so refresh state after every command.
		if action != "get_status" and action != "get_nearby" and not action.begins_with("get_"):
			_refresh_state_then(func():
				if on_complete.is_valid():
					on_complete.call(content)
			)
		else:
			if on_complete.is_valid():
				on_complete.call(content)
		_reset_poll()
	, _on_error)


func send_battle_command(action: String, params: Dictionary, on_complete: Callable = Callable()) -> void:
	var _on_error := func(_error: Dictionary) -> void:
		if on_complete.is_valid():
			on_complete.call({})
		_reset_poll()
	api_post("/api/v2/spacemolt_battle/" + action, params, func(content: Dictionary) -> void:
		if on_complete.is_valid():
			on_complete.call(content)
		_reset_poll()
	, _on_error)


func send_market_command(action: String, params: Dictionary, on_complete: Callable = Callable()) -> void:
	var _on_error := func(_error: Dictionary) -> void:
		if on_complete.is_valid():
			on_complete.call({})
		_reset_poll()
	api_post("/api/v2/spacemolt_market/" + action, params, func(content: Dictionary) -> void:
		if on_complete.is_valid():
			on_complete.call(content)
		_reset_poll()
	, _on_error)


func send_storage_command(action: String, params: Dictionary, on_complete: Callable = Callable()) -> void:
	var _on_error := func(_error: Dictionary) -> void:
		if on_complete.is_valid():
			on_complete.call({})
	api_post("/api/v2/spacemolt_storage/" + action, params, func(content: Dictionary) -> void:
		if on_complete.is_valid():
			on_complete.call(content)
	, _on_error)


func send_social_command(action: String, params: Dictionary, on_complete: Callable = Callable()) -> void:
	var _on_error := func(_error: Dictionary) -> void:
		if on_complete.is_valid():
			on_complete.call({})
	api_post("/api/v2/spacemolt_social/" + action, params, func(content: Dictionary) -> void:
		if on_complete.is_valid():
			on_complete.call(content)
	, _on_error)


func send_ship_command(action: String, params: Dictionary, on_complete: Callable = Callable()) -> void:
	var _on_error := func(_error: Dictionary) -> void:
		if on_complete.is_valid():
			on_complete.call({})
	api_post("/api/v2/spacemolt_ship/" + action, params, func(content: Dictionary) -> void:
		if on_complete.is_valid():
			on_complete.call(content)
	, _on_error)


func send_catalog_command(params: Dictionary, on_complete: Callable = Callable()) -> void:
	var _on_error := func(_error: Dictionary) -> void:
		if on_complete.is_valid():
			on_complete.call({})
	api_post("/api/v2/spacemolt_catalog", params, func(content: Dictionary) -> void:
		if on_complete.is_valid():
			on_complete.call(content)
	, _on_error)


func api_post(path: String, body: Dictionary, on_success: Callable, on_error: Callable = Callable()) -> void:
	if session_id.is_empty():
		_log("ERROR: api_post called without session_id for %s" % path)
		push_error("NetworkManager: api_post called without session_id")
		if on_error.is_valid():
			on_error.call({"code": "no_session", "message": "No session"})
		return

	_log(">> POST %s %s" % [path, JSON.stringify(body)])
	is_request_pending = true
	request_started.emit()

	var http := HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(
		func(result: int, response_code: int, _headers: PackedStringArray, body_bytes: PackedByteArray) -> void:
			http.queue_free()
			is_request_pending = false
			request_completed.emit()

			if result != HTTPRequest.RESULT_SUCCESS:
				_log("<< NETWORK ERROR %s result=%d" % [path, result])
				UIManager.show_error("Network error (code %d)" % result)
				if on_error.is_valid():
					on_error.call({})
				return

			var raw_text := body_bytes.get_string_from_utf8()
			var data = JSON.parse_string(raw_text)
			if data == null:
				_log("<< PARSE ERROR %s http=%d body=%s" % [path, response_code, raw_text.left(500)])
				UIManager.show_error("Invalid response from server")
				if on_error.is_valid():
					on_error.call({})
				return

			if data.has("error") and data["error"] != null:
				_log("<< ERROR %s http=%d error=%s" % [path, response_code, JSON.stringify(data["error"])])
				_handle_error(data["error"])
				if on_error.is_valid():
					on_error.call(data.get("error", {}))
				return

			_log("<< OK %s http=%d" % [path, response_code])

			if data.has("notifications") and data["notifications"] is Array:
				_handle_notifications(data["notifications"])

			# Show the narrative result text in event log (if present and non-empty)
			var result_text: String = data.get("result", "")
			if not result_text.is_empty():
				UIManager.add_event({"msg_type": "result", "message": result_text})

			on_success.call(data.get("structuredContent", {}))
	)

	var headers := PackedStringArray([
		"Content-Type: application/json",
		"X-Session-Id: " + session_id,
	])
	http.request(base_url + path, headers, HTTPClient.METHOD_POST, JSON.stringify(body))


func _handle_error(error: Dictionary) -> void:
	var code: String = error.get("code", "")
	var message: String = error.get("message", "Unknown error")
	_log("HANDLE_ERROR code=%s message=%s" % [code, message])

	match code:
		"session_expired", "session_invalid", "not_authenticated":
			_log("SESSION LOST — emitting session_expired, returning to login")
			if not _is_restoring_session:
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
	http.request(base_url + path, headers, HTTPClient.METHOD_POST, JSON.stringify(body))


func _refresh_state_then(callback: Callable) -> void:
	api_post("/api/v2/spacemolt/get_status", {}, func(state: Dictionary) -> void:
		StateManager.update_state(state)
		callback.call()
	)


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


func pause_poll() -> void:
	_stop_poll()


func resume_poll() -> void:
	_reset_poll()


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


func _full_login(username: String, password: String, on_success: Callable, on_failure: Callable) -> void:
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


func _clear_session() -> void:
	is_authenticated = false
	session_id = ""
	_stop_poll()


func _save_session(username: String, password: String) -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("auth", "username", username)
	cfg.set_value("auth", "password", password)
	cfg.set_value("auth", "session_id", session_id)
	cfg.save(SESSION_PATH)


func _delete_saved_session() -> void:
	if FileAccess.file_exists(SESSION_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SESSION_PATH))


func _open_log() -> void:
	_log_file = FileAccess.open(LOG_PATH, FileAccess.WRITE)
	if _log_file:
		_log_file.store_string("=== SpaceMolt Log Started %s ===\n" % Time.get_datetime_string_from_system())


func _log(msg: String) -> void:
	var timestamp := Time.get_datetime_string_from_system()
	var line := "[%s] %s" % [timestamp, msg]
	print(line)
	if _log_file:
		_log_file.store_string(line + "\n")
		_log_file.flush()


func get_log_path() -> String:
	return ProjectSettings.globalize_path(LOG_PATH)
