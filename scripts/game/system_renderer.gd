extends Node3D

const SCALE := 30.0  # Godot units per AU
const SHIP_SCENE := preload("res://scenes/game/ship.tscn")
const POI_MARKER_SCENE := preload("res://scenes/game/poi_marker.tscn")

var _ships: Dictionary = {}  # player_id -> ShipController node
var _poi_markers: Dictionary = {}  # poi_id -> POIMarker node


func _ready() -> void:
	StateManager.state_updated.connect(_on_state_updated)
	StateManager.nearby_updated.connect(_on_nearby_updated)
	StateManager.location_changed.connect(_on_location_changed)


func _on_state_updated() -> void:
	_update_player_ship()
	_sync_poi_markers()


func _on_nearby_updated() -> void:
	_sync_nearby_ships()


func _on_location_changed(_old_poi: String, _new_poi: String) -> void:
	# Clear all ships when moving to a new POI
	for ship in _ships.values():
		ship.queue_free()
	_ships.clear()

	# Fetch fresh nearby data and system data
	NetworkManager.send_command("get_nearby", {}, func(content):
		StateManager.update_nearby(content)
	)
	NetworkManager.send_command("get_system", {}, func(content):
		StateManager.update_system(content)
	)


func _update_player_ship() -> void:
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
		if _ships.has(pid):
			_ships[pid].move_to(pos)
		else:
			var ship := SHIP_SCENE.instantiate() as Node3D
			add_child(ship)
			ship.setup(pid, p.get("player_name", "Unknown"), pos)
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
			ship.setup(pid, "⚠ " + pirate.get("name", "Pirate"), pos)
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
		marker.setup(id, poi.get("name", "Unknown"), poi.get("type", ""), pos)
		_poi_markers[id] = marker

	# Remove markers for POIs no longer in the system
	for id in _poi_markers.keys():
		if id not in seen_ids:
			_poi_markers[id].queue_free()
			_poi_markers.erase(id)


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
