extends Node3D

## Focus Bubble renderer.
##
## The player ship stays at world origin. The focused POI (where the player is
## located) is rendered at cinematic scale nearby. All other system POIs are
## rendered as small impostor dots at logarithmically compressed distances.

const FocusBubble := preload("res://scripts/game/focus_bubble.gd")
const SHIP_SCENE := preload("res://scenes/game/ship.tscn")
const POI_MARKER_SCENE := preload("res://scenes/game/poi_marker.tscn")

signal poi_selected(poi_id: String, poi_name: String, poi_type: String)
signal poi_deselected
signal ship_selected(ship_id: String, ship_name: String, is_pirate: bool)
signal ship_deselected

const TRAVEL_SPEED_FACTOR := 0.08
const SHIP_HIT_RADIUS := 3.0  # Ships are small, generous click area

var _ships: Dictionary = {}  # player_id -> ShipController node
var _poi_markers: Dictionary = {}  # poi_id -> POIMarker node
var _selected_poi_id: String = ""
var _selected_ship_id: String = ""
var _focused_poi_id: String = ""  # POI where player is located (rendered full-scale)

# Travel animation state
var _is_animating_travel: bool = false
var _travel_origin_pos: Vector3 = Vector3.ZERO
var _travel_dest_pos: Vector3 = Vector3.ZERO
var _travel_elapsed: float = 0.0
var _travel_path_line: MeshInstance3D = null


func _ready() -> void:
	StateManager.state_updated.connect(_on_state_updated)
	StateManager.nearby_updated.connect(_on_nearby_updated)
	StateManager.location_changed.connect(_on_location_changed)
	StateManager.travel_started.connect(_on_travel_started)
	StateManager.travel_ended.connect(_on_travel_ended)
	StateManager.travel_aborted.connect(_on_travel_aborted)
	StateManager.jump_started.connect(_on_jump_started)
	StateManager.jump_ended.connect(_on_jump_ended)


## Returns the distance from a ray to a point, and the ray parameter t.
## Returns [-1.0, INF] if the point is behind the ray origin.
static func ray_point_distance(ray_origin: Vector3, ray_dir: Vector3, point: Vector3) -> Array:
	var to_center: Vector3 = point - ray_origin
	var t: float = to_center.dot(ray_dir)
	if t < 0.0:
		return [-1.0, INF]
	var closest: Vector3 = ray_origin + ray_dir * t
	var dist: float = closest.distance_to(point)
	return [dist, t]


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return
	var camera := get_viewport().get_camera_3d()
	if not camera:
		return
	var from := camera.project_ray_origin(event.position)
	var dir := camera.project_ray_normal(event.position)
	# Find closest POI marker hit by the ray
	var best_marker: Node3D = null
	var best_dist := INF
	for marker_v in _poi_markers.values():
		var marker_node: Node3D = marker_v as Node3D
		var hit_r: float = FocusBubble.hit_radius(
			marker_node.poi_type, marker_node.poi_class, marker_node.is_impostor)
		var result: Array = ray_point_distance(from, dir, marker_node.global_position)
		var dist_to_ray: float = result[0]
		var t: float = result[1]
		if dist_to_ray >= 0.0 and dist_to_ray < hit_r and t < best_dist:
			best_dist = t
			best_marker = marker_node
	# Also check ships (excluding player ship)
	var own_id: String = StateManager.player.get("id", "")
	var best_ship: Node3D = null
	var best_ship_dist := INF
	for pid in _ships:
		if pid == own_id:
			continue
		var ship: Node3D = _ships[pid]
		var result: Array = ray_point_distance(from, dir, ship.global_position)
		var dist_to_ray: float = result[0]
		var t: float = result[1]
		if dist_to_ray >= 0.0 and dist_to_ray < SHIP_HIT_RADIUS and t < best_ship_dist:
			best_ship_dist = t
			best_ship = ship
	# Prefer POI if both are close, otherwise pick the nearer one
	if best_marker and (not best_ship or best_dist <= best_ship_dist):
		_on_poi_marker_selected(best_marker)
		get_viewport().set_input_as_handled()
	elif best_ship:
		_on_ship_selected(best_ship)
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if not _is_animating_travel:
		return
	_travel_elapsed += delta
	var progress := minf(1.0 - exp(-TRAVEL_SPEED_FACTOR * _travel_elapsed), 0.95)
	var own_id: String = StateManager.player.get("id", "")
	if _ships.has(own_id):
		var ship: Node3D = _ships[own_id]
		var new_pos := _travel_origin_pos.lerp(_travel_dest_pos, progress)
		ship.global_position = new_pos
		ship._tick_t = 1.0
		ship._prev_pos = new_pos
		ship._next_pos = new_pos
		ship.engine_glow.light_energy = lerpf(3.0, 1.5, progress)
	if _travel_path_line:
		var ship_pos: Vector3 = _ships[own_id].global_position if _ships.has(own_id) else _travel_origin_pos
		_update_travel_path(ship_pos, _travel_dest_pos)


func _on_state_updated() -> void:
	_update_player_ship()
	_sync_poi_markers()


func _on_nearby_updated() -> void:
	_sync_nearby_ships()


func _on_location_changed(_old_poi: String, _new_poi: String) -> void:
	# Clear OTHER ships when moving to a new POI — keep player ship for smooth travel
	var own_id: String = StateManager.player.get("id", "")
	for pid in _ships.keys():
		if pid != own_id:
			_ships[pid].queue_free()
			_ships.erase(pid)

	# Rebuild the focus bubble around the new location
	_rebuild_bubble()

	# Fetch fresh nearby data and system data
	NetworkManager.send_command("get_nearby", {}, func(content):
		StateManager.update_nearby(content)
	)
	NetworkManager.send_command("get_system", {}, func(content):
		StateManager.update_system(content)
	)


## Rebuilds all POI marker positions around the current player location.
## Called when location changes (travel arrival, jump, etc.).
func _rebuild_bubble() -> void:
	var own_id: String = StateManager.player.get("id", "")
	_focused_poi_id = StateManager.location.get("poi_id", "")

	# Snap player ship to origin if not animating
	if not _is_animating_travel and _ships.has(own_id):
		_ships[own_id].global_position = Vector3.ZERO
		_ships[own_id]._prev_pos = Vector3.ZERO
		_ships[own_id]._next_pos = Vector3.ZERO
		_ships[own_id]._tick_t = 1.0

	# Reposition all existing markers
	var player_au := _get_player_au_pos()
	for id in _poi_markers:
		var marker: Node3D = _poi_markers[id]
		_position_marker(marker, id, player_au)


func _update_player_ship() -> void:
	if _is_animating_travel:
		return  # Don't reposition during travel animation
	var pid: String = StateManager.player.get("id", "")
	if pid.is_empty():
		return

	# In focus bubble, player ship is always at world origin
	var pos := Vector3.ZERO

	if _ships.has(pid):
		_ships[pid].move_to(pos)
	else:
		var ship := SHIP_SCENE.instantiate() as Node3D
		add_child(ship)
		ship.setup(pid, StateManager.player.get("name", "You"), pos, true)
		_ships[pid] = ship

		# Tell camera to follow player ship
		var camera := get_viewport().get_camera_3d()
		if camera and camera.has_method("follow"):
			camera.follow(ship)

	# Update focused POI tracking
	var new_focused: String = StateManager.location.get("poi_id", "")
	if new_focused != _focused_poi_id:
		_focused_poi_id = new_focused
		_rebuild_bubble()


func _sync_nearby_ships() -> void:
	var seen_ids: Array = []

	# Nearby ships are at the same POI — scatter them near origin
	for p in StateManager.nearby_players:
		var pid: String = p.get("player_id", "")
		if pid.is_empty() or pid == StateManager.player.get("id", ""):
			continue
		seen_ids.append(pid)

		# Place nearby ships near origin with a small offset based on their ID hash
		var offset := _nearby_ship_offset(pid)
		var prim: String = p.get("primary_color", "")
		var sec: String = p.get("secondary_color", "")
		if _ships.has(pid):
			_ships[pid].move_to(offset)
			_ships[pid].update_colors(prim, sec)
		else:
			var ship := SHIP_SCENE.instantiate() as Node3D
			add_child(ship)
			ship.setup(pid, p.get("username", "Unknown"), offset, false, prim, sec)
			ship.selected.connect(_on_ship_selected)
			_ships[pid] = ship

	# Update or create pirate ships
	for pirate in StateManager.nearby_pirates:
		var pid: String = "pirate_" + pirate.get("id", "")
		seen_ids.append(pid)

		var offset := _nearby_ship_offset(pid)
		if _ships.has(pid):
			_ships[pid].move_to(offset)
		else:
			var ship := SHIP_SCENE.instantiate() as Node3D
			add_child(ship)
			ship.setup(pid, "⚠ " + pirate.get("name", "Pirate"), offset, false, "#cc3333", "#ff0000")
			ship.set_pirate_aura(pirate.get("is_boss", false), pirate.get("tier", "common"))
			ship.selected.connect(_on_ship_selected)
			_ships[pid] = ship

	# Remove ships that are no longer nearby
	var own_id: String = StateManager.player.get("id", "")
	for pid in _ships.keys():
		if pid != own_id and pid not in seen_ids:
			_ships[pid].queue_free()
			_ships.erase(pid)


## Returns a small world-space offset for a nearby ship so they don't all stack at origin.
func _nearby_ship_offset(pid: String) -> Vector3:
	var h := pid.hash()
	var angle := fmod(float(h), TAU)
	var dist := 3.0 + fmod(float(h) / 1000.0, 5.0)  # 3-8 units from origin
	return Vector3(cos(angle) * dist, 0.0, sin(angle) * dist)


func _sync_poi_markers() -> void:
	var pois: Array = StateManager.current_system.get("pois", [])
	var seen_ids: Array = []
	var player_au := _get_player_au_pos()

	_focused_poi_id = StateManager.location.get("poi_id", "")

	for poi in pois:
		var id: String = poi.get("id", "")
		if id.is_empty():
			continue
		seen_ids.append(id)

		if _poi_markers.has(id):
			# Update position (focus bubble may have changed)
			_position_marker(_poi_markers[id], id, player_au)
			continue

		# Create new marker
		var marker := POI_MARKER_SCENE.instantiate() as Node3D
		add_child(marker)
		# Position will be set by _position_marker; pass Vector3.ZERO for now
		marker.setup(id, poi.get("name", "Unknown"), poi.get("type", ""), Vector3.ZERO, poi.get("class", ""))
		marker.selected.connect(_on_poi_marker_selected)
		_poi_markers[id] = marker
		_position_marker(marker, id, player_au)

	# Remove markers for POIs no longer in the system
	for id in _poi_markers.keys():
		if id not in seen_ids:
			_poi_markers[id].queue_free()
			_poi_markers.erase(id)


## Positions a POI marker based on whether it's the focused POI or an impostor.
func _position_marker(marker: Node3D, poi_id: String, player_au: Vector2) -> void:
	var is_focused := (poi_id == _focused_poi_id)
	if is_focused:
		# Full cinematic scale, near origin
		var offset: Vector3 = FocusBubble.focused_poi_offset(marker.poi_type, marker.poi_class)
		marker.global_position = offset
		marker.set_mode(false)  # full geometry
	else:
		# Impostor at compressed distance
		var poi_au := _get_poi_au_pos(poi_id)
		var world_pos: Vector3 = FocusBubble.impostor_position(player_au, poi_au)
		marker.global_position = world_pos
		marker.set_mode(true)  # impostor dot


func _on_poi_marker_selected(marker: Node3D) -> void:
	# Deselect previous
	if _selected_poi_id and _poi_markers.has(_selected_poi_id):
		_poi_markers[_selected_poi_id].set_selected(false)

	# Also deselect any selected ship
	if _selected_ship_id:
		deselect_ship()

	if marker.poi_id == _selected_poi_id:
		# Toggle off
		_selected_poi_id = ""
		poi_deselected.emit()
	else:
		_selected_poi_id = marker.poi_id
		marker.set_selected(true)
		poi_selected.emit(marker.poi_id, marker.poi_name, marker.poi_type)


func _on_ship_selected(ship_node: Node3D) -> void:
	# Deselect any previous ship
	if _selected_ship_id and _ships.has(_selected_ship_id):
		_ships[_selected_ship_id].set_selected(false)

	# Also deselect any selected POI
	if _selected_poi_id:
		deselect_poi()

	if ship_node.player_id == _selected_ship_id:
		# Toggle off
		_selected_ship_id = ""
		ship_deselected.emit()
	else:
		_selected_ship_id = ship_node.player_id
		ship_node.set_selected(true)
		var is_pirate: bool = ship_node.player_id.begins_with("pirate_")
		ship_selected.emit(ship_node.player_id, ship_node.player_name, is_pirate)


func deselect_ship() -> void:
	if _selected_ship_id and _ships.has(_selected_ship_id):
		_ships[_selected_ship_id].set_selected(false)
	_selected_ship_id = ""
	ship_deselected.emit()


func get_selected_ship_id() -> String:
	return _selected_ship_id


func deselect_poi() -> void:
	if _selected_poi_id and _poi_markers.has(_selected_poi_id):
		_poi_markers[_selected_poi_id].set_selected(false)
	_selected_poi_id = ""
	poi_deselected.emit()


func get_selected_poi_id() -> String:
	return _selected_poi_id


## Returns the player's current AU position as a 2D vector.
func _get_player_au_pos() -> Vector2:
	var pos: Dictionary = StateManager.location.get("position", {})
	return Vector2(pos.get("x", 0.0), pos.get("y", 0.0))


## Returns the AU position for a POI by looking it up in current_system.pois.
func _get_poi_au_pos(poi_id: String) -> Vector2:
	for poi in StateManager.current_system.get("pois", []):
		if poi.get("id", "") == poi_id:
			return FocusBubble.poi_au_pos(poi)
	return Vector2.ZERO


# --- Travel animation ---

func _on_travel_started(dest_poi_id: String, _dest_poi_name: String) -> void:
	var own_id: String = StateManager.player.get("id", "")
	_travel_origin_pos = _ships[own_id].global_position if _ships.has(own_id) else Vector3.ZERO

	# Destination is the impostor position of the target POI
	var player_au := _get_player_au_pos()
	var dest_au := _get_poi_au_pos(dest_poi_id)
	_travel_dest_pos = FocusBubble.impostor_position(player_au, dest_au)

	# Don't animate if distance is negligible
	if _travel_origin_pos.distance_to(_travel_dest_pos) < 1.0:
		return

	_travel_elapsed = 0.0
	_is_animating_travel = true

	# Highlight destination POI
	if _poi_markers.has(dest_poi_id):
		_poi_markers[dest_poi_id].set_selected(true)

	# Create path line
	_create_travel_path()

	# Pause polling during the long blocking HTTP call
	NetworkManager.pause_poll()


func _on_travel_ended() -> void:
	if not _is_animating_travel:
		return
	# Snap ship back to origin (new focused POI)
	var own_id: String = StateManager.player.get("id", "")
	if _ships.has(own_id):
		_ships[own_id].global_position = Vector3.ZERO
		_ships[own_id]._prev_pos = Vector3.ZERO
		_ships[own_id]._next_pos = Vector3.ZERO
		_ships[own_id]._tick_t = 1.0
		_ships[own_id].engine_glow.light_energy = 0.8
	_cleanup_travel()
	_rebuild_bubble()
	NetworkManager.resume_poll()


func _on_travel_aborted(_origin_poi_id: String) -> void:
	if not _is_animating_travel:
		return
	# Snap ship back to origin (stayed at original POI)
	var own_id: String = StateManager.player.get("id", "")
	if _ships.has(own_id):
		_ships[own_id].global_position = Vector3.ZERO
		_ships[own_id]._prev_pos = Vector3.ZERO
		_ships[own_id]._next_pos = Vector3.ZERO
		_ships[own_id]._tick_t = 1.0
		_ships[own_id].engine_glow.light_energy = 0.8
	_cleanup_travel()
	NetworkManager.resume_poll()


func _cleanup_travel() -> void:
	_is_animating_travel = false
	_travel_elapsed = 0.0
	# Deselect destination POI marker
	var dest_id := StateManager.travel_dest_poi_id
	if not dest_id.is_empty() and _poi_markers.has(dest_id):
		_poi_markers[dest_id].set_selected(false)
	_remove_travel_path()


# --- Travel path line ---

func _create_travel_path() -> void:
	var mesh_instance := MeshInstance3D.new()
	var mesh := ImmediateMesh.new()
	mesh_instance.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.3, 0.8, 1.0, 0.6)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh_instance.material_override = mat
	add_child(mesh_instance)
	_travel_path_line = mesh_instance


func _update_travel_path(ship_pos: Vector3, dest_pos: Vector3) -> void:
	var mesh := _travel_path_line.mesh as ImmediateMesh
	mesh.clear_surfaces()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	var direction := dest_pos - ship_pos
	var total_dist := direction.length()
	if total_dist < 0.1:
		mesh.surface_end()
		return
	# Scale dash length to the shell distances
	var dash_len := total_dist / 80.0
	var gap_len := dash_len * 0.5
	var segment_len := dash_len + gap_len
	var num_segments := int(total_dist / segment_len)
	var dir_norm := direction.normalized()
	for i in range(num_segments):
		var start := ship_pos + dir_norm * (i * segment_len)
		var end_pt := ship_pos + dir_norm * (i * segment_len + dash_len)
		mesh.surface_set_color(Color(0.3, 0.8, 1.0, 0.6))
		mesh.surface_add_vertex(start + Vector3(0, 0.5, 0))
		mesh.surface_add_vertex(end_pt + Vector3(0, 0.5, 0))
	mesh.surface_end()


func _remove_travel_path() -> void:
	if _travel_path_line:
		_travel_path_line.queue_free()
		_travel_path_line = null


# --- Jump (inter-system) handlers ---

func _on_jump_started() -> void:
	for marker in _poi_markers.values():
		marker.visible = false
	for ship in _ships.values():
		ship.visible = false


func _on_jump_ended() -> void:
	# Everything will rebuild naturally via location_changed + state_updated
	pass
