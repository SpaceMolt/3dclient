extends Node
## Game transport over WebSocket v2 (/ws/v2). Every game action is a frame
## {tool, action, payload, request_id}; the server answers with a correlated
## result / action_result / action_error / error frame and pushes events on its
## own. Only the dashboard API-key flow still uses HTTP (player list, ws-token).

const DEFAULT_BASE_URL = "https://game.spacemolt.com"
const DEFAULT_TICK_DURATION = 10.0
const AUTH_PATH = "user://auth.cfg"
const DEVICE_LINK_POLL_INTERVAL = 3.0
const MISSING_MODELS_LOG_NAME = "missing_ship_models.log"
# get_map alone is ~140 KB, well past WebSocketPeer's 64 KB default.
const INBOUND_BUFFER_SIZE = 16 * 1024 * 1024
const CLOSE_SESSION_REPLACED = 4001

var base_url: String = DEFAULT_BASE_URL
var tick_duration: float = DEFAULT_TICK_DURATION

var is_authenticated: bool = false
var is_request_pending: bool = false
var api_key: String = ""
var registration_code: String = ""
var device_code: String = ""

var _ws: WebSocketPeer = null
var _welcomed: bool = false
var _on_open: Array[Callable] = []
var _pending: Dictionary = {}  # request_id -> {on_complete: Callable, on_error: Callable}
var _next_request_id: int = 0
var _registered: Dictionary = {}  # password/player_id from a `registered` frame, merged into login

signal request_started
signal request_completed
signal authenticated(initial_state: Dictionary)
signal auth_error(message: String)
signal session_expired


func _ready() -> void:
	_init_named_logs()
	var env_url := OS.get_environment("SPACEMOLT_SERVER_URL")
	if not env_url.is_empty():
		base_url = env_url.rstrip("/")
	Log.i("NetworkManager ready, base_url=%s" % base_url)
	var link_timer := Timer.new()
	link_timer.name = "DeviceLinkTimer"
	link_timer.one_shot = true
	link_timer.wait_time = DEVICE_LINK_POLL_INTERVAL
	link_timer.timeout.connect(_poll_device_link)
	add_child(link_timer)


func _process(_delta: float) -> void:
	if _ws == null:
		return
	_ws.poll()
	match _ws.get_ready_state():
		WebSocketPeer.STATE_OPEN:
			while _ws.get_available_packet_count() > 0:
				_handle_message(_ws.get_packet().get_string_from_utf8())
		WebSocketPeer.STATE_CLOSED:
			var code := _ws.get_close_code()
			var reason := _ws.get_close_reason()
			_ws = null
			_handle_close(code, reason)


# --- Connection ---

func is_connected_to_server() -> bool:
	return _ws != null and _welcomed and _ws.get_ready_state() == WebSocketPeer.STATE_OPEN


func ws_url() -> String:
	var url := base_url.rstrip("/")
	if url.begins_with("https://"):
		url = "wss://" + url.trim_prefix("https://")
	elif url.begins_with("http://"):
		url = "ws://" + url.trim_prefix("http://")
	return url + "/ws/v2"


## Runs callback once the socket is open and the welcome frame has arrived.
func _connect_then(callback: Callable) -> void:
	if is_connected_to_server():
		callback.call()
		return
	_on_open.append(callback)
	if _ws == null:
		_ws = WebSocketPeer.new()
		_ws.inbound_buffer_size = INBOUND_BUFFER_SIZE
		_welcomed = false
		var err := _ws.connect_to_url(ws_url())
		Log.i("Connecting to %s" % ws_url())
		if err != OK:
			Log.e("connect_to_url failed: %d" % err)
			_ws = null
			_handle_close(-1, "connect failed (%d)" % err)


func disconnect_from_server() -> void:
	if _ws:
		_ws.close()
	_ws = null
	_welcomed = false


# --- Sending ---

## Sends one frame and correlates the reply. on_complete receives the query's
## structuredContent, or for mutations the outcome details once the action
## executes. Errors go to on_error when given, otherwise on_complete({}).
func _request(tool: String, action: String, params: Dictionary, on_complete: Callable = Callable(), on_error: Callable = Callable()) -> void:
	if not is_connected_to_server():
		Log.e("Not connected; dropping %s/%s" % [tool, action])
		_deliver_error(on_complete, on_error, {"code": "not_connected", "message": "Not connected to the server."})
		return
	_next_request_id += 1
	var request_id := "r%d" % _next_request_id
	_pending[request_id] = {"on_complete": on_complete, "on_error": on_error}
	_update_pending_flag()
	var frame := {"tool": tool, "action": action, "payload": params, "request_id": request_id}
	var logged := params.duplicate()
	if logged.has("password"):
		logged["password"] = "***"
	Log.i(">> %s/%s %s %s" % [tool, action, request_id, JSON.stringify(logged)])
	_ws.send_text(JSON.stringify(frame))


func _deliver_error(on_complete: Callable, on_error: Callable, error: Dictionary) -> void:
	if on_error.is_valid():
		on_error.call(error)
	elif on_complete.is_valid():
		on_complete.call({})


func _settle(request_id: String) -> Dictionary:
	var entry: Dictionary = _pending.get(request_id, {})
	_pending.erase(request_id)
	_update_pending_flag()
	return entry


func _update_pending_flag() -> void:
	var pending := not _pending.is_empty()
	if pending == is_request_pending:
		return
	is_request_pending = pending
	if pending:
		request_started.emit()
	else:
		request_completed.emit()


func _fail_all_pending(error: Dictionary) -> void:
	var entries := _pending.values()
	_pending.clear()
	_update_pending_flag()
	for entry in entries:
		_deliver_error(entry["on_complete"], entry["on_error"], error)


# --- Receiving ---

## The server packs several frames into one message, newline separated.
static func split_frames(text: String) -> Array[String]:
	var frames: Array[String] = []
	for line in text.split("\n"):
		if not line.strip_edges().is_empty():
			frames.append(line)
	return frames


func _handle_message(text: String) -> void:
	for line in split_frames(text):
		var frame = JSON.parse_string(line)
		if frame is Dictionary and frame.has("type"):
			_handle_frame(frame)
		else:
			Log.e("Dropped unparseable frame: %s" % line.left(200))


## True when a `result` frame is only the pending acknowledgement of a queued
## mutation. `jump` nests the marker under details; most actions keep it top level.
static func is_pending_ack(content) -> bool:
	if not content is Dictionary:
		return false
	if content.get("pending", false) == true:
		return true
	var details = content.get("details")
	return details is Dictionary and details.get("pending", false) == true


func _handle_frame(frame: Dictionary) -> void:
	var type: String = frame.get("type", "")
	var payload = frame.get("payload", {})
	var request_id: String = frame.get("request_id", "")
	if not payload is Dictionary:
		payload = {"result": payload}
	match type:
		"welcome":
			_on_welcome(payload)
		"result":
			if is_pending_ack(payload.get("structuredContent")):
				Log.i("<< pending %s" % request_id)
				return
			Log.i("<< result %s" % request_id)
			var content = payload.get("structuredContent")
			if not content is Dictionary:
				content = {"result": payload.get("result", "")}
			StateManager.update_state(content)
			var entry := _settle(request_id)
			if entry.has("on_complete") and entry["on_complete"].is_valid():
				entry["on_complete"].call(content)
		"action_result":
			var delta = payload.get("result", {})
			if not delta is Dictionary:
				delta = {}
			Log.i("<< action_result %s %s tick=%s" % [request_id, payload.get("command", ""), payload.get("tick", "")])
			StateManager.update_state(delta)
			var message: String = str(delta.get("message", ""))
			if not message.is_empty():
				UIManager.add_event({"msg_type": payload.get("command", "result"), "message": message})
			var entry := _settle(request_id)
			if entry.has("on_complete") and entry["on_complete"].is_valid():
				entry["on_complete"].call(delta.get("details", delta))
		"action_error", "error":
			Log.w("<< %s %s %s" % [type, request_id, JSON.stringify(payload)])
			_handle_error(payload)
			var entry := _settle(request_id)
			if not entry.is_empty():
				_deliver_error(entry["on_complete"], entry["on_error"], payload)
		"registered":
			_registered = payload
		"logged_in":
			var entry := _settle(request_id)
			var content := _finish_login(payload)
			if entry.has("on_complete") and entry["on_complete"].is_valid():
				entry["on_complete"].call(content)
		"chat_message":
			UIManager.add_chat(payload)
		"player_died":
			UIManager.add_event({"msg_type": type, "data": payload})
			_request("spacemolt", "get_status", {})
		_:
			UIManager.add_event({"msg_type": type, "message": str(payload.get("message", "")), "data": payload})


func _on_welcome(payload: Dictionary) -> void:
	_welcomed = true
	var tick_rate := float(payload.get("tick_rate", 0))
	if tick_rate > 0.0:
		tick_duration = tick_rate
	Log.i("Connected: server %s, tick %ss" % [payload.get("version", "?"), tick_duration])
	var callbacks := _on_open.duplicate()
	_on_open.clear()
	for callback in callbacks:
		callback.call()
	if not device_code.is_empty():
		_schedule_device_poll(DEVICE_LINK_POLL_INTERVAL)


func _handle_close(code: int, reason: String) -> void:
	_welcomed = false
	_on_open.clear()
	Log.w("Socket closed code=%d reason=%s" % [code, reason])
	var was_authenticated := is_authenticated
	_fail_all_pending({"code": "disconnected", "message": "Connection closed (%d)" % code})
	if not device_code.is_empty():
		# Device login outlives the 30 s unauthenticated socket limit: reconnect
		# and keep polling the same device code.
		await get_tree().create_timer(2.0).timeout
		if not device_code.is_empty():
			_connect_then(func() -> void: pass)
		return
	if was_authenticated:
		is_authenticated = false
		var message := "Logged in from another client." if code == CLOSE_SESSION_REPLACED else "Connection lost (%d)." % code
		UIManager.show_error(message)
		session_expired.emit()


func _handle_error(error: Dictionary) -> void:
	var code: String = error.get("code", "")
	var message: String = error.get("message", "Unknown error")
	match code:
		"not_authenticated", "session_expired", "session_invalid":
			if is_authenticated:
				is_authenticated = false
				UIManager.show_error("Session expired. Please log in again.")
				session_expired.emit()
		"rate_limited":
			var retry_after: float = error.get("details", {}).get("retry_after", error.get("retry_after", 5.0))
			UIManager.show_error("Rate limited. Try again in %ds." % int(retry_after))
		"combat_interrupt":
			UIManager.show_error("Action cancelled: you were pulled into combat.")
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
			_request("spacemolt", "get_nearby", {}, func(content: Dictionary) -> void:
				StateManager.update_nearby(content)
			)
		_:
			UIManager.show_error(message)


# --- Authentication ---

func set_api_key(key: String) -> void:
	api_key = key
	_save_auth()


func get_players(on_success: Callable, on_error: Callable = Callable()) -> void:
	_api_get_with_key("/api/registration-code", func(data: Dictionary) -> void:
		registration_code = data.get("registration_code", "")
		on_success.call(data.get("players", []))
	, on_error)


func create_player(username: String, empire: String, on_success: Callable, on_error: Callable = Callable()) -> void:
	_connect_then(func() -> void:
		_request("spacemolt_auth", "register",
			{"username": username, "empire": empire, "registration_code": registration_code},
			on_success, on_error)
	)


func select_player(player_id: String, on_success: Callable, on_error: Callable = Callable()) -> void:
	_api_post_with_key("/api/player/" + player_id + "/ws-token", {}, func(data: Dictionary) -> void:
		var token: String = data.get("token", "")
		if token.is_empty():
			if on_error.is_valid():
				on_error.call({"code": "no_token", "message": "Failed to get auth token"})
			return
		_connect_then(func() -> void:
			_request("spacemolt_auth", "login_token", {"token": token}, on_success, on_error)
		)
	, on_error)


## Password login for scripted dev runs (SPACEMOLT_USERNAME / SPACEMOLT_PASSWORD).
func login_password(username: String, password: String, on_error: Callable = Callable()) -> void:
	_connect_then(func() -> void:
		_request("spacemolt_auth", "login", {"username": username, "password": password}, Callable(), on_error)
	)


## Browser device login: the server hands back a link for the human to approve.
## on_link(url, user_code) fires when the link is ready; approval or failure
## arrives through the authenticated / auth_error signals.
func start_device_login(on_link: Callable, on_error: Callable = Callable()) -> void:
	_connect_then(func() -> void:
		_request("spacemolt_auth", "login_link", {}, func(content: Dictionary) -> void:
			device_code = content.get("device_code", "")
			var url: String = content.get("verification_uri_complete", "")
			Log.i("Device login link: %s" % url)
			on_link.call(url, content.get("user_code", ""))
			_schedule_device_poll(content.get("interval", DEVICE_LINK_POLL_INTERVAL))
		, on_error)
	)


func _schedule_device_poll(interval: float) -> void:
	# Unauthenticated frames are capped at 20/min per IP; never poll faster than the server asks.
	(get_node("DeviceLinkTimer") as Timer).start(maxf(interval, DEVICE_LINK_POLL_INTERVAL))


func _poll_device_link() -> void:
	if device_code.is_empty() or not is_connected_to_server():
		return
	_request("spacemolt_auth", "login_link_poll", {"device_code": device_code}, _on_device_link_polled, func(_error: Dictionary) -> void:
		_schedule_device_poll(DEVICE_LINK_POLL_INTERVAL)
	)


func _on_device_link_polled(content: Dictionary) -> void:
	if device_code.is_empty():
		return
	match content.get("status", ""):
		"authorization_pending":
			_schedule_device_poll(content.get("interval", DEVICE_LINK_POLL_INTERVAL))
		"access_denied":
			device_code = ""
			auth_error.emit("Login declined in the browser.")
		"expired_token":
			device_code = ""
			auth_error.emit("Login link expired. Try again.")
		_:
			pass  # Approval arrives as a logged_in frame, handled in _handle_frame.


## Marks the connection logged in and emits the initial state, with the
## password/player_id from a preceding `registered` frame merged in.
func _finish_login(payload: Dictionary) -> Dictionary:
	is_authenticated = true
	device_code = ""
	(get_node("DeviceLinkTimer") as Timer).stop()
	var content := payload.duplicate()
	content.merge(_registered)
	_registered = {}
	authenticated.emit(content)
	return content


func logout() -> void:
	if is_connected_to_server():
		_request("spacemolt_auth", "logout", {})
	is_authenticated = false
	device_code = ""
	clear_auth()
	StateManager.reset()
	disconnect_from_server()
	session_expired.emit()


## Restores a saved dashboard API key: on_success gets the player list.
func try_restore_auth(on_success: Callable, on_failure: Callable) -> void:
	_load_auth()
	if api_key.is_empty():
		on_failure.call()
		return
	get_players(on_success, func(_error: Dictionary = {}) -> void:
		clear_auth()
		on_failure.call()
	)


func clear_auth() -> void:
	api_key = ""
	registration_code = ""
	_delete_saved_auth()


func has_saved_auth() -> bool:
	return FileAccess.file_exists(AUTH_PATH)


# --- Game commands (tool wrappers) ---

func send_command(action: String, params: Dictionary, on_complete: Callable = Callable()) -> void:
	_request("spacemolt", action, params, on_complete)


func execute_jump(target_system_id: String, on_complete: Callable) -> void:
	send_command("jump", {"id": target_system_id}, func(_content: Dictionary) -> void:
		if StateManager.get_current_system_id() != target_system_id:
			on_complete.call(false)
			return
		send_command("get_system", {}, func(sys_content: Dictionary) -> void:
			StateManager.update_system(sys_content)
			send_command("get_nearby", {}, func(nearby_content: Dictionary) -> void:
				StateManager.update_nearby(nearby_content)
				on_complete.call(true)
			)
		)
	)


func send_battle_command(action: String, params: Dictionary, on_complete: Callable = Callable()) -> void:
	_request("spacemolt_battle", action, params, on_complete)


func send_market_command(action: String, params: Dictionary, on_complete: Callable = Callable()) -> void:
	_request("spacemolt_market", action, params, on_complete)


func send_storage_command(action: String, params: Dictionary, on_complete: Callable = Callable()) -> void:
	_request("spacemolt_storage", action, params, on_complete)


func send_transfer_command(action: String, params: Dictionary, on_complete: Callable = Callable()) -> void:
	_request("spacemolt_transfer", action, params, on_complete)


func send_social_command(action: String, params: Dictionary, on_complete: Callable = Callable()) -> void:
	_request("spacemolt_social", action, params, on_complete)


func send_salvage_command(action: String, params: Dictionary, on_complete: Callable = Callable()) -> void:
	_request("spacemolt_salvage", action, params, on_complete)


func send_ship_command(action: String, params: Dictionary, on_complete: Callable = Callable()) -> void:
	_request("spacemolt_ship", action, params, on_complete)


func send_catalog_command(params: Dictionary, on_complete: Callable = Callable()) -> void:
	_request("spacemolt_catalog", "", params, on_complete)


# --- Dashboard API key HTTP calls (player list, ws-token) ---

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
					var err = data.get("error", {})
					on_error.call(err if err is Dictionary else {"message": err})
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
					var err = data.get("error", {})
					on_error.call(err if err is Dictionary else {"message": err})
				return
			Log.i("<< OK %s http=%d" % [path, response_code])
			on_success.call(data)
	)
	var headers := PackedStringArray([
		"Content-Type: application/json",
		"Authorization: Bearer " + api_key,
	])
	http.request(base_url + path, headers, HTTPClient.METHOD_POST, JSON.stringify(body))



# --- Saved auth ---

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
