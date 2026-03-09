extends Control

## A minimap showing the current system's POIs and the player's position.
## Drawn as a 2D overlay in the top-right corner of the screen.

const MAP_SIZE := 180.0  # Pixels
const MAP_MARGIN := 10.0
const POI_RADIUS := 4.0
const PLAYER_RADIUS := 5.0
const LABEL_FONT_SIZE := 9

# AU range to display — auto-fits to system bounds
var _min_pos := Vector2(-10.0, -10.0)
var _max_pos := Vector2(10.0, 10.0)


func _ready() -> void:
	StateManager.state_updated.connect(func(): queue_redraw())
	StateManager.location_changed.connect(func(_a, _b): queue_redraw())
	StateManager.nearby_updated.connect(func(): queue_redraw())
	# Position in top-right corner
	anchors_preset = Control.PRESET_TOP_RIGHT
	offset_left = -MAP_SIZE - MAP_MARGIN
	offset_top = MAP_MARGIN
	offset_right = -MAP_MARGIN
	offset_bottom = MAP_SIZE + MAP_MARGIN
	custom_minimum_size = Vector2(MAP_SIZE, MAP_SIZE)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var pois: Array = StateManager.current_system.get("pois", [])
	if pois.is_empty():
		return

	# Calculate bounds from POI positions
	_calculate_bounds(pois)

	# Background
	draw_rect(Rect2(Vector2.ZERO, Vector2(MAP_SIZE, MAP_SIZE)), Color(0.0, 0.0, 0.0, 0.5))
	draw_rect(Rect2(Vector2.ZERO, Vector2(MAP_SIZE, MAP_SIZE)), Color(0.2, 0.3, 0.5, 0.4), false, 1.0)

	# System name
	var sys_name: String = StateManager.current_system.get("name", "")
	if not sys_name.is_empty():
		draw_string(ThemeDB.fallback_font, Vector2(4, 12), sys_name,
			HORIZONTAL_ALIGNMENT_LEFT, MAP_SIZE - 8, LABEL_FONT_SIZE,
			Color(0.6, 0.7, 0.9, 0.8))

	# Draw POIs
	var current_poi_id: String = StateManager.location.get("poi_id", "")
	for poi in pois:
		var pos: Dictionary = poi.get("position", {})
		var screen_pos := _world_to_map(Vector2(pos.get("x", 0.0), pos.get("y", 0.0)))
		var poi_type: String = poi.get("type", "")
		var color := _poi_color(poi_type)

		# Highlight current location
		if poi.get("id", "") == current_poi_id:
			draw_circle(screen_pos, POI_RADIUS + 3.0, Color(1.0, 1.0, 1.0, 0.3))

		draw_circle(screen_pos, POI_RADIUS, color)

		# POI name label
		var pname: String = poi.get("name", "")
		if not pname.is_empty():
			draw_string(ThemeDB.fallback_font,
				screen_pos + Vector2(POI_RADIUS + 2, 3),
				pname, HORIZONTAL_ALIGNMENT_LEFT, MAP_SIZE * 0.4,
				LABEL_FONT_SIZE, Color(0.7, 0.8, 0.9, 0.6))

	# Draw nearby players
	for p in StateManager.nearby_players:
		var p_pos: Dictionary = p.get("position", {})
		if not p_pos.is_empty():
			var sp := _world_to_map(Vector2(p_pos.get("x", 0.0), p_pos.get("y", 0.0)))
			var pcolor := Color(0.3, 1.0, 0.3, 0.7)
			var pc: String = p.get("primary_color", "")
			if not pc.is_empty():
				pcolor = Color.from_string(pc, pcolor)
				pcolor.a = 0.7
			draw_circle(sp, 3.0, pcolor)

	# Draw nearby pirates
	for pirate in StateManager.nearby_pirates:
		var pp: Dictionary = pirate.get("position", {})
		if not pp.is_empty():
			var sp := _world_to_map(Vector2(pp.get("x", 0.0), pp.get("y", 0.0)))
			draw_circle(sp, 3.0, Color(1.0, 0.3, 0.3, 0.7))

	# Draw player position
	var player_pos := _get_player_map_pos()
	draw_circle(player_pos, PLAYER_RADIUS, Color(0.3, 0.8, 1.0, 1.0))
	draw_circle(player_pos, PLAYER_RADIUS + 1.0, Color(0.3, 0.8, 1.0, 0.4), false, 1.0)


func _calculate_bounds(pois: Array) -> void:
	var min_x := INF
	var min_y := INF
	var max_x := -INF
	var max_y := -INF

	for poi in pois:
		var pos: Dictionary = poi.get("position", {})
		var x: float = pos.get("x", 0.0)
		var y: float = pos.get("y", 0.0)
		min_x = minf(min_x, x)
		min_y = minf(min_y, y)
		max_x = maxf(max_x, x)
		max_y = maxf(max_y, y)

	# Add padding
	var range_x := max_x - min_x
	var range_y := max_y - min_y
	var padding := maxf(range_x, range_y) * 0.15 + 1.0
	_min_pos = Vector2(min_x - padding, min_y - padding)
	_max_pos = Vector2(max_x + padding, max_y + padding)

	# Make square
	var size_x := _max_pos.x - _min_pos.x
	var size_y := _max_pos.y - _min_pos.y
	if size_x > size_y:
		var diff := (size_x - size_y) * 0.5
		_min_pos.y -= diff
		_max_pos.y += diff
	else:
		var diff := (size_y - size_x) * 0.5
		_min_pos.x -= diff
		_max_pos.x += diff


func _world_to_map(world_pos: Vector2) -> Vector2:
	var range_vec := _max_pos - _min_pos
	var normalized := (world_pos - _min_pos) / range_vec
	# Inset from edges
	var inset := 20.0
	var usable := MAP_SIZE - inset * 2.0
	return Vector2(inset + normalized.x * usable, inset + normalized.y * usable)


func _get_player_map_pos() -> Vector2:
	# Try position from location data
	var pos: Dictionary = StateManager.location.get("position", {})
	if not pos.is_empty():
		return _world_to_map(Vector2(pos.get("x", 0.0), pos.get("y", 0.0)))

	# Look up from POI
	var poi_id: String = StateManager.location.get("poi_id", "")
	for poi in StateManager.current_system.get("pois", []):
		if poi.get("id", "") == poi_id:
			var p: Dictionary = poi.get("position", {})
			return _world_to_map(Vector2(p.get("x", 0.0), p.get("y", 0.0)))

	return Vector2(MAP_SIZE * 0.5, MAP_SIZE * 0.5)


func _poi_color(poi_type: String) -> Color:
	match poi_type:
		"station":
			return Color(0.2, 0.6, 1.0, 0.9)
		"asteroid_belt":
			return Color(0.6, 0.5, 0.3, 0.8)
		"ice_field":
			return Color(0.6, 0.85, 1.0, 0.8)
		"gas_cloud":
			return Color(0.8, 0.6, 0.3, 0.7)
		"planet":
			return Color(0.3, 0.5, 0.7, 0.8)
		"wormhole", "jump_gate":
			return Color(0.8, 0.3, 1.0, 0.9)
		_:
			return Color(0.5, 0.5, 0.5, 0.7)
