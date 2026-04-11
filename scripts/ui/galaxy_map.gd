extends CanvasLayer

## Galaxy map overlay — 2D node graph of all systems with connections.
## Opened via G key or Map button. Click a system to select, then Jump to travel.
## Supports multi-jump route planning with auto-travel execution.

const ROUTE_BANNER_SCENE := preload("res://scenes/ui/route_banner.tscn")

@onready var map_panel: Panel = $MapPanel
@onready var map_canvas: Control = $MapPanel/MapCanvas
@onready var info_panel: PanelContainer = $MapPanel/InfoPanel
@onready var system_name_label: Label = $MapPanel/InfoPanel/VBox/SystemNameLabel
@onready var system_details_label: Label = $MapPanel/InfoPanel/VBox/SystemDetailsLabel
@onready var jump_button: Button = $MapPanel/InfoPanel/VBox/JumpButton
@onready var route_info_label: Label = $MapPanel/InfoPanel/VBox/RouteInfoLabel
@onready var begin_route_button: Button = $MapPanel/InfoPanel/VBox/BeginRouteButton
@onready var cancel_route_button: Button = $MapPanel/InfoPanel/VBox/CancelRouteButton
@onready var close_button: Button = $MapPanel/CloseButton
@onready var search_field: LineEdit = $MapPanel/TopBar/SearchField
@onready var zoom_label: Label = $MapPanel/TopBar/ZoomLabel

var _systems: Array = []
var _system_lookup: Dictionary = {}  # system_id -> system dict
var _selected_id: String = ""

# Route planning
var _planned_route: Array = []  # Array of {system_id, name} for the planned route
var _route_system_ids: Array = []  # Just the system_id strings for fast lookup during draw
var _is_requesting_route: bool = false

# Auto-travel
var _auto_travel: AutoTravel = null
var _route_banner: PanelContainer = null

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
	begin_route_button.pressed.connect(_on_begin_route)
	cancel_route_button.pressed.connect(_clear_route)
	search_field.text_submitted.connect(_on_search)
	map_canvas.draw.connect(_draw_map)
	map_canvas.gui_input.connect(_on_canvas_input)
	StateManager.galaxy_map_loaded.connect(_on_map_loaded)
	info_panel.hide()
	route_info_label.hide()
	begin_route_button.hide()
	cancel_route_button.hide()

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
			HORIZONTAL_ALIGNMENT_LEFT, -1, 14, ThemeColors.TEXT_MUTED)
		return

	var cur_system_id := StateManager.get_current_system_id()
	var node_radius: float = clampf(3.0 * _zoom, 2.0, 8.0)
	var font := ThemeDB.fallback_font
	var label_size := clampi(int(10.0 * _zoom), 6, 14)
	var show_labels := _zoom > 0.03

	# Draw connections first (below nodes)
	var connection_color := Color(ThemeColors.DIM_GREY, 0.4)
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

		var color := ThemeColors.HULL_GREY
		if sid == cur_system_id:
			color = ThemeColors.BIO_GREEN
		elif sid == _selected_id:
			color = ThemeColors.WARNING_YELLOW
		elif sid in _route_system_ids:
			color = ThemeColors.PLASMA_CYAN
		elif s.get("visited", false):
			color = ThemeColors.LASER_BLUE

		var r := node_radius
		if sid == cur_system_id or sid == _selected_id:
			r *= 1.5

		# Online player indicator
		var online: int = int(s.get("online", 0))
		if online > 0 and sid != cur_system_id:
			map_canvas.draw_circle(screen_pos, r + 3, Color(ThemeColors.PLASMA_CYAN, 0.3))

		map_canvas.draw_circle(screen_pos, r, color)

		if show_labels:
			var name_text: String = s.get("name", "")
			map_canvas.draw_string(font, screen_pos + Vector2(r + 3, 4),
				name_text, HORIZONTAL_ALIGNMENT_LEFT, -1, label_size, Color(ThemeColors.CHROME_SILVER, 0.8))

	# Draw planned route (multi-hop) or simple line to selected
	if not _planned_route.is_empty():
		_draw_planned_route(cur_system_id)
	elif not _selected_id.is_empty() and _selected_id != cur_system_id:
		if _system_lookup.has(cur_system_id) and _system_lookup.has(_selected_id):
			var from_pos: Dictionary = _system_lookup[cur_system_id].get("position", {})
			var to_pos: Dictionary = _system_lookup[_selected_id].get("position", {})
			var from_screen := _map_to_screen(Vector2(from_pos.get("x", 0.0), from_pos.get("y", 0.0)))
			var to_screen := _map_to_screen(Vector2(to_pos.get("x", 0.0), to_pos.get("y", 0.0)))
			map_canvas.draw_line(from_screen, to_screen, Color(ThemeColors.WARNING_YELLOW, 0.6), 2.0, true)

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
				_clear_route()
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

	var cur_id := StateManager.get_current_system_id()
	var is_current := system_id == cur_id
	var is_connected := false
	var cur_sys: Dictionary = _system_lookup.get(cur_id, {})
	if system_id in cur_sys.get("connections", []):
		is_connected = true

	var busy := StateManager.is_docked() or StateManager.is_traveling or _is_auto_traveling()

	if is_current:
		jump_button.hide()
		_hide_route_ui()
	elif is_connected:
		# Adjacent system -- direct jump only, no route needed
		jump_button.text = "Jump"
		jump_button.disabled = busy
		jump_button.show()
		_hide_route_ui()
	else:
		# Distant system -- request a route from the server
		jump_button.hide()
		_request_route(system_id)

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


# ── Route Planning ──────────────────────────────────────────────────────

func _request_route(target_system_id: String) -> void:
	if _is_requesting_route:
		return
	_is_requesting_route = true
	route_info_label.text = "Calculating route..."
	route_info_label.modulate = ThemeColors.TEXT_MUTED
	route_info_label.show()
	begin_route_button.hide()
	cancel_route_button.hide()

	NetworkManager.send_command("find_route", {"target_system": target_system_id}, func(content: Dictionary):
		_is_requesting_route = false
		var route: Array = content.get("route", [])
		if route.is_empty():
			route_info_label.text = "No route found."
			route_info_label.modulate = ThemeColors.TEXT_ERROR
			route_info_label.show()
			begin_route_button.hide()
			cancel_route_button.show()
			return
		_set_planned_route(route, content)
	)


func _set_planned_route(route: Array, content: Dictionary) -> void:
	_planned_route = route
	_route_system_ids.clear()
	for waypoint in route:
		_route_system_ids.append(waypoint.get("system_id", ""))

	var total_jumps: int = content.get("total_jumps", route.size())
	var fuel_cost: int = content.get("fuel_cost", 0)

	var info_parts: Array = []
	info_parts.append("%d jumps" % total_jumps)
	if fuel_cost > 0:
		info_parts.append("fuel: %d" % fuel_cost)
		# Warn if fuel is low
		var current_fuel: int = StateManager.ship.get("fuel", 0)
		if current_fuel < fuel_cost:
			info_parts.append("[LOW FUEL]")
			route_info_label.modulate = ThemeColors.WARNING_YELLOW
		else:
			route_info_label.modulate = ThemeColors.PLASMA_CYAN
	else:
		route_info_label.modulate = ThemeColors.PLASMA_CYAN

	route_info_label.text = "Route: " + " | ".join(info_parts)
	route_info_label.show()

	var busy := StateManager.is_docked() or StateManager.is_traveling or _is_auto_traveling()
	begin_route_button.disabled = busy
	begin_route_button.show()
	cancel_route_button.show()
	map_canvas.queue_redraw()


func _clear_route() -> void:
	_planned_route.clear()
	_route_system_ids.clear()
	_is_requesting_route = false
	_hide_route_ui()
	map_canvas.queue_redraw()


func _hide_route_ui() -> void:
	route_info_label.hide()
	begin_route_button.hide()
	cancel_route_button.hide()


func _draw_planned_route(cur_system_id: String) -> void:
	# Build the full chain: current system -> each waypoint in order
	var chain: Array = [cur_system_id]
	for waypoint in _planned_route:
		chain.append(waypoint.get("system_id", ""))

	var route_color := Color(ThemeColors.PLASMA_CYAN, 0.8)
	for i in range(chain.size() - 1):
		var from_id: String = chain[i]
		var to_id: String = chain[i + 1]
		if not _system_lookup.has(from_id) or not _system_lookup.has(to_id):
			continue
		var from_pos: Dictionary = _system_lookup[from_id].get("position", {})
		var to_pos: Dictionary = _system_lookup[to_id].get("position", {})
		var from_screen := _map_to_screen(Vector2(from_pos.get("x", 0.0), from_pos.get("y", 0.0)))
		var to_screen := _map_to_screen(Vector2(to_pos.get("x", 0.0), to_pos.get("y", 0.0)))
		map_canvas.draw_line(from_screen, to_screen, route_color, 2.5, true)

		# Draw a small direction indicator at the midpoint
		var mid := (from_screen + to_screen) * 0.5
		map_canvas.draw_circle(mid, 2.0, route_color)


# ── Auto-Travel ─────────────────────────────────────────────────────────

func _on_begin_route() -> void:
	if _planned_route.is_empty():
		return
	if _is_auto_traveling():
		return

	# Lock UI
	begin_route_button.disabled = true
	begin_route_button.text = "Traveling..."

	# Create AutoTravel node
	_auto_travel = AutoTravel.new()
	_auto_travel.name = "AutoTravel"
	add_child(_auto_travel)

	# Create route banner
	_route_banner = ROUTE_BANNER_SCENE.instantiate()
	# Add as sibling CanvasLayer child so it appears above the HUD
	get_parent().add_child(_route_banner)
	_route_banner.abort_requested.connect(_on_route_abort)

	# Wire signals
	_auto_travel.route_started.connect(_on_auto_route_started)
	_auto_travel.jump_completed.connect(_on_auto_jump_completed)
	_auto_travel.route_completed.connect(_on_auto_route_completed)
	_auto_travel.route_aborted.connect(_on_auto_route_aborted)
	_auto_travel.route_failed.connect(_on_auto_route_failed)

	# Copy the route and start
	var route_copy := _planned_route.duplicate(true)
	_clear_route()
	hide()
	_auto_travel.start_route(route_copy)


func _on_route_abort() -> void:
	if _auto_travel:
		_auto_travel.abort()


func _on_auto_route_started(total_jumps: int) -> void:
	if _route_banner:
		_route_banner.show_route(total_jumps)


func _on_auto_jump_completed(current: int, total: int, system_name: String) -> void:
	if _route_banner:
		_route_banner.update_progress(current, total, system_name)


func _on_auto_route_completed() -> void:
	UIManager.show_info("Route complete -- arrived at destination.")
	_cleanup_auto_travel()


func _on_auto_route_aborted(reason: String) -> void:
	UIManager.show_info("Route aborted: %s" % reason)
	_cleanup_auto_travel()


func _on_auto_route_failed(reason: String) -> void:
	UIManager.show_error("Route failed: %s" % reason)
	_cleanup_auto_travel()


func _cleanup_auto_travel() -> void:
	if _route_banner:
		_route_banner.queue_free()
		_route_banner = null
	if _auto_travel:
		_auto_travel.queue_free()
		_auto_travel = null
	# Reset button state
	begin_route_button.text = "Begin Route"
	begin_route_button.disabled = false


func _is_auto_traveling() -> bool:
	return _auto_travel != null and _auto_travel.is_active()
