extends Node

const DEFAULT_BASE_URL = "https://game.spacemolt.com"
const DEFAULT_TICK_DURATION = 10.0
const POLL_INTERVAL = 10.0
const AUTH_PATH = "user://auth.cfg"
const MISSING_MODELS_LOG_NAME = "missing_ship_models.log"

var base_url: String = DEFAULT_BASE_URL
var tick_duration: float = DEFAULT_TICK_DURATION

var session_id: String = ""
var is_authenticated: bool = false
var is_request_pending: bool = false
var _is_restoring_session: bool = false
var api_key: String = ""
var registration_code: String = ""

signal request_started
signal request_completed
signal authenticated(initial_state: Dictionary)
signal auth_error(message: String)
signal session_expired


func _ready() -> void:
	_init_named_logs()
	Log.i("NetworkManager ready, base_url=%s" % base_url)
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


func set_api_key(key: String) -> void:
	api_key = key
	_save_auth()


func get_players(on_success: Callable, on_error: Callable = Callable()) -> void:
	_api_get_with_key("/api/registration-code", func(data: Dictionary) -> void:
		registration_code = data.get("registration_code", "")
		var players: Array = data.get("players", [])
		on_success.call(players)
	, on_error)


func create_player(username: String, empire: String, on_success: Callable, on_error: Callable = Callable()) -> void:
	create_session(func() -> void:
		api_post(
			"/api/v2/spacemolt_auth/register",
			{"username": username, "empire": empire, "registration_code": registration_code},
			func(content: Dictionary) -> void:
				is_authenticated = true
				_start_poll()
				authenticated.emit(content)
				on_success.call(content)
		, on_error)
	)

func select_player(player_id: String, on_success: Callable, on_error: Callable = Callable()) -> void:
	_api_post_with_key("/api/player/" + player_id + "/ws-token", {}, func(data: Dictionary) -> void:
		var token: String = data.get("token", "")
		if token.is_empty():
			if on_error.is_valid():
				on_error.call({"code": "no_token", "message": "Failed to get auth token"})
			return
		create_session(func() -> void:
			api_post(
				"/api/v2/spacemolt_auth/login_token",
				{"token": token},
				func(content: Dictionary) -> void:
					is_authenticated = true
					_start_poll()
					authenticated.emit(content)
					on_success.call(content)
			, on_error)
		)
	, on_error)


func logout() -> void:
	if session_id.is_empty():
		return
	api_post("/api/v2/spacemolt_auth/logout", {}, func(_content: Dictionary) -> void:
		pass
	)
	_clear_session()
	clear_auth()
	StateManager.reset()
	session_expired.emit()


func try_restore_auth(on_success: Callable, on_failure: Callable) -> void:
	_load_auth()
	if api_key.is_empty():
		on_failure.call()
		return
	get_players(func(players: Array) -> void:
		on_success.call(players)
	, func(_error: Dictionary = {}) -> void:
		clear_auth()
		on_failure.call()
	)


func clear_auth() -> void:
	api_key = ""
	registration_code = ""
	_delete_saved_auth()


func has_saved_auth() -> bool:
	return FileAccess.file_exists(AUTH_PATH)


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


func execute_jump(target_system_id: String, on_complete: Callable) -> void:
	send_command("jump", {"id": target_system_id}, func(_content: Dictionary):
		if StateManager.get_current_system_id() != target_system_id:
			on_complete.call(false)
			return
		send_command("get_system", {}, func(sys_content: Dictionary):
			StateManager.update_system(sys_content)
			send_command("get_nearby", {}, func(nearby_content: Dictionary):
				StateManager.update_nearby(nearby_content)
				on_complete.call(true)
			)
		)
	)


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
		Log.e("api_post called without session_id for %s" % path)
		if on_error.is_valid():
			on_error.call({"code": "no_session", "message": "No session"})
		return

	Log.i(">> POST %s %s" % [path, JSON.stringify(body)])
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
				Log.e("<< NETWORK ERROR %s result=%d" % [path, result])
				UIManager.show_error("Network error (code %d)" % result)
				if on_error.is_valid():
					on_error.call({})
				return

			var raw_text := body_bytes.get_string_from_utf8()
			var data = JSON.parse_string(raw_text)
			if data == null:
				Log.e("<< PARSE ERROR %s http=%d body=%s" % [path, response_code, raw_text.left(500)])
				UIManager.show_error("Invalid response from server")
				if on_error.is_valid():
					on_error.call({})
				return

			if data.has("error") and data["error"] != null:
				Log.w("<< ERROR %s http=%d error=%s" % [path, response_code, JSON.stringify(data["error"])])
				_handle_error(data["error"])
				if on_error.is_valid():
					on_error.call(data.get("error", {}))
				return

			Log.i("<< OK %s http=%d" % [path, response_code])

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
	Log.w("HANDLE_ERROR code=%s message=%s" % [code, message])

	match code:
		"session_expired", "session_invalid", "not_authenticated":
			Log.w("SESSION LOST — emitting session_expired, returning to login")
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


func _api_get_with_key(path: String, on_success: Callable, on_error: Callable = Callable()) -> void:
	Log.i(">> GET %s (with API key)" % path)
	var http := HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(
		func(result: int, response_code: int, _headers: PackedStringArray, body_bytes: PackedByteArray) -> void:
			http.queue_free()
			if result != HTTPRequest.RESULT_SUCCESS:
				Log.e("<< NETWORK ERROR %s result=%d" % [path, result])
				UIManager.show_error("Network error (code %d)" % result)
				if on_error.is_valid():
					on_error.call({})
				return
			var raw_text := body_bytes.get_string_from_utf8()
			var data = JSON.parse_string(raw_text)
			if data == null:
				Log.e("<< PARSE ERROR %s http=%d body=%s" % [path, response_code, raw_text.left(500)])
				UIManager.show_error("Invalid response from server")
				if on_error.is_valid():
					on_error.call({})
				return
			if data is Dictionary and data.has("error") and data["error"] != null:
				Log.w("<< ERROR %s: %s" % [path, JSON.stringify(data["error"])])
				if on_error.is_valid():
					on_error.call(data.get("error", {}))
				return
			Log.i("<< OK %s http=%d" % [path, response_code])
			on_success.call(data)
	)
	var headers := PackedStringArray([
		"Authorization: Bearer " + api_key,
	])
	http.request(base_url + path, headers, HTTPClient.METHOD_GET)


func _api_post_with_key(path: String, body: Dictionary, on_success: Callable, on_error: Callable = Callable()) -> void:
	Log.i(">> POST %s (with API key)" % path)
	var http := HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(
		func(result: int, response_code: int, _headers: PackedStringArray, body_bytes: PackedByteArray) -> void:
			http.queue_free()
			if result != HTTPRequest.RESULT_SUCCESS:
				Log.e("<< NETWORK ERROR %s result=%d" % [path, result])
				UIManager.show_error("Network error (code %d)" % result)
				if on_error.is_valid():
					on_error.call({})
				return
			var raw_text := body_bytes.get_string_from_utf8()
			var data = JSON.parse_string(raw_text)
			if data == null:
				Log.e("<< PARSE ERROR %s http=%d body=%s" % [path, response_code, raw_text.left(500)])
				UIManager.show_error("Invalid response from server")
				if on_error.is_valid():
					on_error.call({})
				return
			if data is Dictionary and data.has("error") and data["error"] != null:
				Log.w("<< ERROR %s: %s" % [path, JSON.stringify(data["error"])])
				if on_error.is_valid():
					on_error.call(data.get("error", {}))
				return
			Log.i("<< OK %s http=%d" % [path, response_code])
			on_success.call(data)
	)
	var headers := PackedStringArray([
		"Content-Type: application/json",
		"Authorization: Bearer " + api_key,
	])
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


func _clear_session() -> void:
	is_authenticated = false
	session_id = ""
	_stop_poll()


func _save_auth() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("auth", "api_key", api_key)
	cfg.save(AUTH_PATH)


func _load_auth() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(AUTH_PATH) != OK:
		return
	api_key = cfg.get_value("auth", "api_key", "")


func _delete_saved_auth() -> void:
	if FileAccess.file_exists(AUTH_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(AUTH_PATH))


func _init_named_logs() -> void:
	for resolved_path in _resolve_named_log_paths(MISSING_MODELS_LOG_NAME):
		_ensure_named_log_exists_at_path(resolved_path, "=== Missing Ship Models Log Started %s ===\n")
	Log.i("Missing ship model logs: %s" % JSON.stringify(_resolve_named_log_paths(MISSING_MODELS_LOG_NAME)))


func append_missing_model_log(msg: String) -> void:
	_append_named_log(MISSING_MODELS_LOG_NAME, msg)


func get_missing_model_log_path() -> String:
	var resolved_paths := _resolve_named_log_paths(MISSING_MODELS_LOG_NAME)
	if resolved_paths.is_empty():
		return ""
	return String(resolved_paths[0])


func _append_named_log(file_name: String, msg: String) -> void:
	var timestamp := Time.get_datetime_string_from_system()
	for resolved_path_variant in _resolve_named_log_paths(file_name):
		var resolved_path := String(resolved_path_variant)
		var dir_path := resolved_path.get_base_dir()
		if not dir_path.is_empty():
			DirAccess.make_dir_recursive_absolute(dir_path)
		var file := FileAccess.open(resolved_path, FileAccess.READ_WRITE)
		if file == null:
			file = FileAccess.open(resolved_path, FileAccess.WRITE_READ)
		if file == null:
			Log.w("Failed to open named log: %s" % resolved_path)
			continue
		file.seek_end()
		file.store_string("[%s] %s\n" % [timestamp, msg])
		file.flush()
		file.close()


func _resolve_named_log_paths(file_name: String) -> Array[String]:
	var resolved_paths: Array[String] = []
	var user_path := ProjectSettings.globalize_path("user://" + file_name)
	if not user_path.is_empty():
		resolved_paths.append(user_path)
	var exe_dir := OS.get_executable_path().get_base_dir()
	if not exe_dir.is_empty():
		var exe_path := exe_dir.path_join(file_name)
		if not resolved_paths.has(exe_path):
			resolved_paths.append(exe_path)
	return resolved_paths


func _ensure_named_log_exists_at_path(resolved_path: String, header_template: String) -> void:
	if FileAccess.file_exists(resolved_path):
		return
	var dir_path := resolved_path.get_base_dir()
	if not dir_path.is_empty():
		DirAccess.make_dir_recursive_absolute(dir_path)
	var file := FileAccess.open(resolved_path, FileAccess.WRITE)
	if file == null:
		Log.w("Failed to create named log: %s" % resolved_path)
		return
	file.store_string(header_template % Time.get_datetime_string_from_system())
	file.flush()
	file.close()
