extends Node
## Dev control server for autonomous testing. Inactive unless SPACEMOLT_DEV_PORT is set.
## Protocol: one JSON object per line over TCP on 127.0.0.1, one JSON reply line per request.
## Driven by scripts/tools/devctl.py (screenshot, key, click, scroll, type, state, nodes, quit).

const MAX_NODES = 300

var _server: TCPServer = null
var _clients: Array[Dictionary] = []  # {peer: StreamPeerTCP, buf: String}


func _ready() -> void:
	var port_text := OS.get_environment("SPACEMOLT_DEV_PORT")
	if port_text.is_empty():
		set_process(false)
		return
	_server = TCPServer.new()
	var err := _server.listen(int(port_text), "127.0.0.1")
	if err != OK:
		Log.e("DevServer failed to listen on %s: %d" % [port_text, err])
		set_process(false)
		return
	Log.i("DevServer listening on 127.0.0.1:%s" % port_text)


func _process(_delta: float) -> void:
	while _server.is_connection_available():
		_clients.append({"peer": _server.take_connection(), "buf": ""})
	for client in _clients.duplicate():
		var peer: StreamPeerTCP = client["peer"]
		peer.poll()
		if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			_clients.erase(client)
			continue
		var available := peer.get_available_bytes()
		if available <= 0:
			continue
		client["buf"] += peer.get_utf8_string(available)
		var lines := take_lines(client)
		for line in lines:
			peer.put_data((JSON.stringify(handle_line(line)) + "\n").to_utf8_buffer())


## Splits complete lines off the client's buffer, leaving any partial line behind.
static func take_lines(client: Dictionary) -> Array[String]:
	var lines: Array[String] = []
	var buf: String = client["buf"]
	while true:
		var idx := buf.find("\n")
		if idx < 0:
			break
		var line := buf.substr(0, idx).strip_edges()
		buf = buf.substr(idx + 1)
		if not line.is_empty():
			lines.append(line)
	client["buf"] = buf
	return lines


func handle_line(line: String) -> Dictionary:
	var cmd = JSON.parse_string(line)
	if not cmd is Dictionary:
		return {"ok": false, "error": "expected a JSON object"}
	return handle(cmd)


func handle(cmd: Dictionary) -> Dictionary:
	match cmd.get("cmd", ""):
		"ping":
			return {"ok": true, "godot": Engine.get_version_info()["string"]}
		"screenshot":
			return _screenshot(cmd.get("path", ""))
		"key":
			return _key(str(cmd.get("key", "")), cmd.get("shift", false), cmd.get("ctrl", false))
		"click":
			return _click(cmd.get("x", 0.0), cmd.get("y", 0.0), int(cmd.get("button", 1)), cmd.get("double", false))
		"scroll":
			return _scroll(cmd.get("x", 0.0), cmd.get("y", 0.0), str(cmd.get("dir", "up")), int(cmd.get("n", 1)))
		"type":
			return _type(str(cmd.get("text", "")))
		"state":
			return {"ok": true, "state": _state()}
		"nodes":
			return {"ok": true, "nodes": _nodes(str(cmd.get("pattern", "")))}
		"quit":
			get_tree().quit()
			return {"ok": true}
		_:
			return {"ok": false, "error": "unknown cmd %s" % cmd.get("cmd", "")}


func _screenshot(path: String) -> Dictionary:
	if path.is_empty():
		return {"ok": false, "error": "path required"}
	var image := get_viewport().get_texture().get_image()
	var err := image.save_png(path)
	if err != OK:
		return {"ok": false, "error": "save_png failed: %d" % err}
	return {"ok": true, "path": path, "width": image.get_width(), "height": image.get_height()}


func _key(key_name: String, shift: bool, ctrl: bool) -> Dictionary:
	var keycode := OS.find_keycode_from_string(key_name)
	if keycode == KEY_NONE:
		return {"ok": false, "error": "unknown key %s" % key_name}
	for pressed in [true, false]:
		var ev := InputEventKey.new()
		ev.keycode = keycode
		ev.physical_keycode = keycode
		ev.shift_pressed = shift
		ev.ctrl_pressed = ctrl
		ev.pressed = pressed
		Input.parse_input_event(ev)
	return {"ok": true, "keycode": keycode}


func _click(x: float, y: float, button: int, double: bool) -> Dictionary:
	var pos := Vector2(x, y)
	var motion := InputEventMouseMotion.new()
	motion.position = pos
	motion.global_position = pos
	Input.parse_input_event(motion)
	for pressed in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.position = pos
		ev.global_position = pos
		ev.button_index = button
		ev.pressed = pressed
		ev.double_click = double and pressed
		Input.parse_input_event(ev)
	return {"ok": true}


func _scroll(x: float, y: float, dir: String, n: int) -> Dictionary:
	var button := MOUSE_BUTTON_WHEEL_UP if dir == "up" else MOUSE_BUTTON_WHEEL_DOWN
	for i in range(maxi(n, 1)):
		for pressed in [true, false]:
			var ev := InputEventMouseButton.new()
			ev.position = Vector2(x, y)
			ev.global_position = Vector2(x, y)
			ev.button_index = button
			ev.pressed = pressed
			Input.parse_input_event(ev)
	return {"ok": true}


func _type(text: String) -> Dictionary:
	for ch in text:
		for pressed in [true, false]:
			var ev := InputEventKey.new()
			ev.unicode = ch.unicode_at(0)
			ev.keycode = OS.find_keycode_from_string(ch.to_upper())
			ev.pressed = pressed
			Input.parse_input_event(ev)
	return {"ok": true, "length": text.length()}


func _state() -> Dictionary:
	var out := {}
	for prop in StateManager.get_script().get_script_property_list():
		var name: String = prop["name"]
		if name.begins_with("_"):
			continue
		out[name] = StateManager.get(name)
	out["network"] = {
		"base_url": NetworkManager.base_url,
		"is_authenticated": NetworkManager.is_authenticated,
		"is_request_pending": NetworkManager.is_request_pending,
		"connected": NetworkManager.is_connected_to_server(),
	}
	return out


## Visible Control nodes whose name or class contains pattern (case-insensitive), with screen rects.
func _nodes(pattern: String) -> Array:
	var found := []
	_collect_nodes(get_tree().root, pattern.to_lower(), found)
	return found


func _collect_nodes(node: Node, pattern: String, found: Array) -> void:
	if found.size() >= MAX_NODES:
		return
	if node is Control and node.is_visible_in_tree():
		var label := "%s %s" % [node.name, node.get_class()]
		if pattern.is_empty() or label.to_lower().contains(pattern):
			var rect: Rect2 = node.get_global_rect()
			var entry := {
				"name": node.name,
				"class": node.get_class(),
				"path": str(node.get_path()),
				"x": rect.position.x, "y": rect.position.y,
				"w": rect.size.x, "h": rect.size.y,
			}
			if "text" in node:
				entry["text"] = str(node.text).left(80)
			if "disabled" in node:
				entry["disabled"] = node.disabled
			found.append(entry)
	for child in node.get_children():
		_collect_nodes(child, pattern, found)
