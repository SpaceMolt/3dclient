extends Node3D

const SCALE := 30.0  # Godot units per AU
const SHIP_SCENE := preload("res://scenes/game/ship.tscn")
const POI_MARKER_SCENE := preload("res://scenes/game/poi_marker.tscn")

signal poi_selected(poi_id: String, poi_name: String, poi_type: String)
signal poi_deselected
signal ship_selected(ship_id: String, ship_name: String, is_pirate: bool)
signal ship_deselected

const TRAVEL_SPEED_FACTOR := 0.08

var _ships: Dictionary = {}  # player_id -> ShipController node
var _poi_markers: Dictionary = {}  # poi_id -> POIMarker node
var _selected_poi_id: String = ""
var _selected_ship_id: String = ""

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

	# Don't reposition player ship if travel animation is active
	if not _is_animating_travel and _ships.has(own_id):
		var new_pos := _get_player_world_pos()
		_ships[own_id].move_to(new_pos)

	# Fetch fresh nearby data and system data
	NetworkManager.send_command("get_nearby", {}, func(content):
		StateManager.update_nearby(content)
	)
	NetworkManager.send_command("get_system", {}, func(content):
		StateManager.update_system(content)
	)


func _update_player_ship() -> void:
	if _is_animating_travel:
		return  # Don't reposition during travel animation
	var pid: String = StateManager.player.get("id", "")
	if pid.is_empty():
		return

	var pos: Vector3 = _get_player_world_pos()
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


func _sync_nearby_ships() -> void:
	var seen_ids: Array = []

	# Update or create ships for nearby players
	for p in StateManager.nearby_players:
		var pid: String = p.get("player_id", "")
		if pid.is_empty() or pid == StateManager.player.get("id", ""):
			continue
		seen_ids.append(pid)

		var pos: Vector3 = _poi_position_to_world(p.get("position", {}))
		var prim: String = p.get("primary_color", "")
		var sec: String = p.get("secondary_color", "")
		if _ships.has(pid):
			_ships[pid].move_to(pos)
			_ships[pid].update_colors(prim, sec)
		else:
			var ship := SHIP_SCENE.instantiate() as Node3D
			add_child(ship)
			ship.setup(pid, p.get("username", "Unknown"), pos, false, prim, sec)
			ship.selected.connect(_on_ship_selected)
			_ships[pid] = ship

	# Update or create pirate ships
	for pirate in StateManager.nearby_pirates:
		var pid: String = "pirate_" + pirate.get("id", "")
		seen_ids.append(pid)

		var pos: Vector3 = _poi_position_to_world(pirate.get("position", {}))
		if _ships.has(pid):
			_ships[pid].move_to(pos)
		else:
			var ship := SHIP_SCENE.instantiate() as Node3D
			add_child(ship)
			ship.setup(pid, "⚠ " + pirate.get("name", "Pirate"), pos, false, "#cc3333", "#ff0000")
			ship.set_pirate_aura(pirate.get("is_boss", false), pirate.get("tier", "common"))
			ship.selected.connect(_on_ship_selected)
			_ships[pid] = ship

	# Remove ships that are no longer nearby
	var own_id: String = StateManager.player.get("id", "")
	for pid in _ships.keys():
		if pid != own_id and pid not in seen_ids:
			_ships[pid].queue_free()
			_ships.erase(pid)


func _sync_poi_markers() -> void:
	var pois: Array = StateManager.current_system.get("pois", [])
	var seen_ids: Array = []

	for poi in pois:
		var id: String = poi.get("id", "")
		if id.is_empty():
			continue
		seen_ids.append(id)

		if _poi_markers.has(id):
			continue  # POI markers don't move

		var pos: Vector3 = _poi_position_to_world(poi.get("position", {}))
		var marker := POI_MARKER_SCENE.instantiate() as Node3D
		add_child(marker)
		marker.setup(id, poi.get("name", "Unknown"), poi.get("type", ""), pos, poi.get("class", ""))
		marker.selected.connect(_on_poi_marker_selected)
		_poi_markers[id] = marker

	# Remove markers for POIs no longer in the system
	for id in _poi_markers.keys():
		if id not in seen_ids:
			_poi_markers[id].queue_free()
			_poi_markers.erase(id)


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


func _get_player_world_pos() -> Vector3:
	# First try direct position from location (set during initial state)
	var pos: Dictionary = StateManager.location.get("position", {})
	if not pos.is_empty():
		return _poi_position_to_world(pos)

	# Otherwise look up the POI position from system data
	var poi_id: String = StateManager.location.get("poi_id", "")
	for poi in StateManager.current_system.get("pois", []):
		if poi.get("id", "") == poi_id:
			return _poi_position_to_world(poi.get("position", {}))

	return Vector3.ZERO


func _poi_position_to_world(pos: Dictionary) -> Vector3:
	var x: float = pos.get("x", 0.0) * SCALE
	var z: float = pos.get("y", 0.0) * SCALE
	return Vector3(x, 0.0, z)


# --- Travel animation ---

func _on_travel_started(dest_poi_id: String, _dest_poi_name: String) -> void:
	var own_id: String = StateManager.player.get("id", "")
	_travel_origin_pos = _ships[own_id].global_position if _ships.has(own_id) else _get_player_world_pos()

	# Find destination position from system POI data
	_travel_dest_pos = _travel_origin_pos  # fallback
	for poi in StateManager.current_system.get("pois", []):
		if poi.get("id", "") == dest_poi_id:
			_travel_dest_pos = _poi_position_to_world(poi.get("position", {}))
			break

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
	# Snap ship to final destination
	var own_id: String = StateManager.player.get("id", "")
	if _ships.has(own_id):
		var final_pos := _get_player_world_pos()
		_ships[own_id].global_position = final_pos
		_ships[own_id]._prev_pos = final_pos
		_ships[own_id]._next_pos = final_pos
		_ships[own_id]._tick_t = 1.0
		_ships[own_id].engine_glow.light_energy = 0.8
	_cleanup_travel()
	NetworkManager.resume_poll()


func _on_travel_aborted(origin_poi_id: String) -> void:
	if not _is_animating_travel:
		return
	# Snap ship back to origin
	var own_id: String = StateManager.player.get("id", "")
	if _ships.has(own_id):
		_ships[own_id].global_position = _travel_origin_pos
		_ships[own_id]._prev_pos = _travel_origin_pos
		_ships[own_id]._next_pos = _travel_origin_pos
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
	var dash_len := 1.0
	var gap_len := 0.5
	var segment_len := dash_len + gap_len
	var num_segments := int(total_dist / segment_len)
	var dir_norm := direction.normalized()
	for i in range(num_segments):
		var start := ship_pos + dir_norm * (i * segment_len)
		var end_pt := ship_pos + dir_norm * (i * segment_len + dash_len)
		mesh.surface_set_color(Color(0.3, 0.8, 1.0, 0.6))
		mesh.surface_add_vertex(start + Vector3(0, 0.1, 0))
		mesh.surface_add_vertex(end_pt + Vector3(0, 0.1, 0))
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
