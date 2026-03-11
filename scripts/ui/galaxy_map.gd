extends CanvasLayer

## Galaxy map overlay — 2D node graph of all systems with connections.
## Opened via G key or Map button. Click a system to select, then Jump to travel.

@onready var map_panel: Panel = $MapPanel
@onready var map_canvas: Control = $MapPanel/MapCanvas
@onready var info_panel: PanelContainer = $MapPanel/InfoPanel
@onready var system_name_label: Label = $MapPanel/InfoPanel/VBox/SystemNameLabel
@onready var system_details_label: Label = $MapPanel/InfoPanel/VBox/SystemDetailsLabel
@onready var jump_button: Button = $MapPanel/InfoPanel/VBox/JumpButton
@onready var close_button: Button = $MapPanel/CloseButton
@onready var search_field: LineEdit = $MapPanel/TopBar/SearchField
@onready var zoom_label: Label = $MapPanel/TopBar/ZoomLabel

var _systems: Array = []
var _system_lookup: Dictionary = {}  # system_id -> system dict
var _selected_id: String = ""

# View transform
var _offset := Vector2.ZERO  # Pan offset in map coordinates
var _zoom: float = 1.0
var _dragging := false
var _drag_start := Vector2.ZERO
var _drag_offset_start := Vector2.ZERO

# Map bounds (computed from system positions)
var _min_pos := Vector2.ZERO
var _max_pos := Vector2.ZERO


func _ready() -> void:
	visible = false
	close_button.pressed.connect(func(): hide())
	jump_button.pressed.connect(_on_jump)
	search_field.text_submitted.connect(_on_search)
	map_canvas.draw.connect(_draw_map)
	map_canvas.gui_input.connect(_on_canvas_input)
	StateManager.galaxy_map_loaded.connect(_on_map_loaded)
	info_panel.hide()

	if not StateManager.galaxy_map.is_empty():
		_on_map_loaded()


func show_map() -> void:
	visible = true
	# Center on current system
	var cur_id := StateManager.get_current_system_id()
	if _system_lookup.has(cur_id):
		var sys: Dictionary = _system_lookup[cur_id]
		var pos: Dictionary = sys.get("position", {})
		_offset = -Vector2(pos.get("x", 0.0), pos.get("y", 0.0))
	map_canvas.queue_redraw()


func _on_map_loaded() -> void:
	_systems = StateManager.galaxy_map.get("systems", [])
	_system_lookup.clear()

	# Build lookup and compute bounds
	_min_pos = Vector2(INF, INF)
	_max_pos = Vector2(-INF, -INF)
	for s in _systems:
		var sid: String = s.get("system_id", "")
		_system_lookup[sid] = s
		var pos: Dictionary = s.get("position", {})
		var p := Vector2(pos.get("x", 0.0), pos.get("y", 0.0))
		_min_pos = _min_pos.min(p)
		_max_pos = _max_pos.max(p)

	# Initial zoom to fit map
	_fit_to_view()
	map_canvas.queue_redraw()


func _fit_to_view() -> void:
	if _systems.is_empty():
		return
	var map_size := _max_pos - _min_pos
	if map_size.x <= 0 or map_size.y <= 0:
		return
	var canvas_size := map_canvas.size
	var scale_x := canvas_size.x / (map_size.x * 1.1)
	var scale_y := canvas_size.y / (map_size.y * 1.1)
	_zoom = minf(scale_x, scale_y)
	var center := (_min_pos + _max_pos) * 0.5
	_offset = -center


func _map_to_screen(map_pos: Vector2) -> Vector2:
	var canvas_center := map_canvas.size * 0.5
	return (map_pos + _offset) * _zoom + canvas_center


func _screen_to_map(screen_pos: Vector2) -> Vector2:
	var canvas_center := map_canvas.size * 0.5
	return (screen_pos - canvas_center) / _zoom - _offset


func _draw_map() -> void:
	if _systems.is_empty():
		map_canvas.draw_string(ThemeDB.fallback_font, Vector2(20, 30), "Loading galaxy map...",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.5, 0.5, 0.5))
		return

	var cur_system_id := StateManager.get_current_system_id()
	var node_radius: float = clampf(3.0 * _zoom, 2.0, 8.0)
	var font := ThemeDB.fallback_font
	var label_size := clampi(int(10.0 * _zoom), 6, 14)
	var show_labels := _zoom > 0.03

	# Draw connections first (below nodes)
	var connection_color := Color(0.2, 0.3, 0.4, 0.4)
	var drawn_connections: Dictionary = {}
	for s in _systems:
		var sid: String = s.get("system_id", "")
		var pos: Dictionary = s.get("position", {})
		var screen_pos := _map_to_screen(Vector2(pos.get("x", 0.0), pos.get("y", 0.0)))

		for conn_id in s.get("connections", []):
			# Avoid drawing each connection twice
			var key: String = sid + "|" + conn_id if sid < conn_id else conn_id + "|" + sid
			if drawn_connections.has(key):
				continue
			drawn_connections[key] = true

			if not _system_lookup.has(conn_id):
				continue
			var conn: Dictionary = _system_lookup[conn_id]
			var conn_pos: Dictionary = conn.get("position", {})
			var conn_screen := _map_to_screen(Vector2(conn_pos.get("x", 0.0), conn_pos.get("y", 0.0)))
			map_canvas.draw_line(screen_pos, conn_screen, connection_color, 1.0)

	# Draw system nodes
	for s in _systems:
		var sid: String = s.get("system_id", "")
		var pos: Dictionary = s.get("position", {})
		var screen_pos := _map_to_screen(Vector2(pos.get("x", 0.0), pos.get("y", 0.0)))

		# Skip if off-screen
		if screen_pos.x < -20 or screen_pos.x > map_canvas.size.x + 20:
			continue
		if screen_pos.y < -20 or screen_pos.y > map_canvas.size.y + 20:
			continue

		var color := Color(0.3, 0.4, 0.6)
		if sid == cur_system_id:
			color = Color(0.2, 1.0, 0.4)
		elif sid == _selected_id:
			color = Color(1.0, 1.0, 0.3)
		elif s.get("visited", false):
			color = Color(0.5, 0.7, 0.9)

		var r := node_radius
		if sid == cur_system_id or sid == _selected_id:
			r *= 1.5

		# Online player indicator
		var online: int = int(s.get("online", 0))
		if online > 0 and sid != cur_system_id:
			map_canvas.draw_circle(screen_pos, r + 3, Color(0.4, 0.8, 1.0, 0.3))

		map_canvas.draw_circle(screen_pos, r, color)

		if show_labels:
			var name_text: String = s.get("name", "")
			map_canvas.draw_string(font, screen_pos + Vector2(r + 3, 4),
				name_text, HORIZONTAL_ALIGNMENT_LEFT, -1, label_size, Color(0.7, 0.7, 0.7, 0.8))

	# Draw path from current to selected
	if not _selected_id.is_empty() and _selected_id != cur_system_id:
		if _system_lookup.has(cur_system_id) and _system_lookup.has(_selected_id):
			var from_pos: Dictionary = _system_lookup[cur_system_id].get("position", {})
			var to_pos: Dictionary = _system_lookup[_selected_id].get("position", {})
			var from_screen := _map_to_screen(Vector2(from_pos.get("x", 0.0), from_pos.get("y", 0.0)))
			var to_screen := _map_to_screen(Vector2(to_pos.get("x", 0.0), to_pos.get("y", 0.0)))
			map_canvas.draw_line(from_screen, to_screen, Color(1.0, 1.0, 0.3, 0.6), 2.0, true)

	zoom_label.text = "%.0f%%" % (_zoom * 100.0 / _initial_zoom())


func _initial_zoom() -> float:
	var map_size := _max_pos - _min_pos
	if map_size.x <= 0 or map_size.y <= 0:
		return 1.0
	var canvas_size := map_canvas.size
	var scale_x := canvas_size.x / (map_size.x * 1.1)
	var scale_y := canvas_size.y / (map_size.y * 1.1)
	return minf(scale_x, scale_y)


func _on_canvas_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_at(event.position, 1.15)
			map_canvas.queue_redraw()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_at(event.position, 1.0 / 1.15)
			map_canvas.queue_redraw()
		elif event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				# Check for system click
				var clicked := _find_system_at(event.position)
				if not clicked.is_empty():
					_select_system(clicked)
				else:
					_dragging = true
					_drag_start = event.position
					_drag_offset_start = _offset
			else:
				_dragging = false
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			if event.pressed:
				_selected_id = ""
				info_panel.hide()
				map_canvas.queue_redraw()

	elif event is InputEventMouseMotion and _dragging:
		var delta: Vector2 = event.position - _drag_start
		_offset = _drag_offset_start + delta / _zoom
		map_canvas.queue_redraw()


func _zoom_at(screen_pos: Vector2, factor: float) -> void:
	var map_pos_before := _screen_to_map(screen_pos)
	_zoom *= factor
	_zoom = clampf(_zoom, 0.001, 5.0)
	var map_pos_after := _screen_to_map(screen_pos)
	_offset += map_pos_after - map_pos_before


func _find_system_at(screen_pos: Vector2) -> String:
	var best_id := ""
	var best_dist := 15.0  # Click radius in pixels
	for s in _systems:
		var pos: Dictionary = s.get("position", {})
		var sp := _map_to_screen(Vector2(pos.get("x", 0.0), pos.get("y", 0.0)))
		var dist := screen_pos.distance_to(sp)
		if dist < best_dist:
			best_dist = dist
			best_id = s.get("system_id", "")
	return best_id


func _select_system(system_id: String) -> void:
	_selected_id = system_id
	var sys: Dictionary = _system_lookup.get(system_id, {})
	if sys.is_empty():
		info_panel.hide()
		return

	system_name_label.text = sys.get("name", "Unknown")
	var details := ""
	details += "POIs: %d" % int(sys.get("poi_count", 0))
	var online: int = int(sys.get("online", 0))
	if online > 0:
		details += "  |  Online: %d" % online
	if sys.get("visited", false):
		details += "  |  Visited"
	system_details_label.text = details

	# Can only jump to connected systems (or allow any jump?)
	var cur_id := StateManager.get_current_system_id()
	var is_current := system_id == cur_id
	var is_connected := false
	var cur_sys: Dictionary = _system_lookup.get(cur_id, {})
	if system_id in cur_sys.get("connections", []):
		is_connected = true

	jump_button.visible = not is_current
	jump_button.text = "Jump" if is_connected else "Jump (distant)"
	jump_button.disabled = is_current or StateManager.is_docked() or StateManager.is_traveling
	info_panel.show()
	map_canvas.queue_redraw()


func _on_jump() -> void:
	if _selected_id.is_empty():
		return
	var sys: Dictionary = _system_lookup.get(_selected_id, {})
	var sys_name: String = sys.get("name", "Unknown")

	jump_button.disabled = true
	jump_button.text = "Jumping..."

	NetworkManager.execute_jump(_selected_id, func(succeeded: bool):
		if not succeeded:
			jump_button.disabled = false
			jump_button.text = "Jump"
			UIManager.show_error("Jump to %s failed." % sys_name)
			return
		hide()
	)


func _on_search(text: String) -> void:
	var search := text.strip_edges().to_lower()
	if search.is_empty():
		return
	for s in _systems:
		var name: String = s.get("name", "").to_lower()
		if name.find(search) != -1:
			# Center on this system
			var pos: Dictionary = s.get("position", {})
			_offset = -Vector2(pos.get("x", 0.0), pos.get("y", 0.0))
			_select_system(s.get("system_id", ""))
			map_canvas.queue_redraw()
			return


func _unhandled_key_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and not event.is_echo():
		match event.keycode:
			KEY_ESCAPE, KEY_G:
				hide()
				get_viewport().set_input_as_handled()
			KEY_HOME:
				# Center on current system
				var cur_id := StateManager.get_current_system_id()
				if _system_lookup.has(cur_id):
					var pos: Dictionary = _system_lookup[cur_id].get("position", {})
					_offset = -Vector2(pos.get("x", 0.0), pos.get("y", 0.0))
					map_canvas.queue_redraw()
				get_viewport().set_input_as_handled()
