extends Node3D

## Stable world-space renderer.
##
## All POIs live at one consistent world position derived from system AU coordinates.
## The player ship moves through that same space instead of warping the scene.

const FocusBubble := preload("res://scripts/game/focus_bubble.gd")
const SHIP_SCENE := preload("res://scenes/game/ship.tscn")
const POI_MARKER_SCENE := preload("res://scenes/game/poi_marker.tscn")

signal poi_selected(poi_id: String, poi_name: String, poi_type: String)
signal poi_deselected
signal ship_selected(ship_id: String, ship_name: String, is_pirate: bool)
signal ship_deselected

const SHIP_HIT_RADIUS := 3.0
const AU_TO_WORLD := 100000.0
const PRELAUNCH_ALIGN_TIME := 1.0
const STAR_CLEARANCE_PADDING := 2000.0
const STATION_BERTH_MARGIN := 6.0
const STATION_RING_CLEARANCE := 18.0
const STATION_LAYER_SPACING := 18.0
const STATION_BASE_LAYERS := 9
const STATION_BERTH_REFERENCE_SPAN := 34.0
const BELT_SHIP_RING_RADIUS := 900.0
const BELT_SHIP_VERTICAL_SPAN := 220.0
const BELT_SHIP_CLEARANCE := 140.0

var _ships: Dictionary = {}
var _poi_markers: Dictionary = {}
var _selected_poi_id: String = ""
var _selected_ship_id: String = ""
# Travel animation state
var _is_animating_travel: bool = false
var _travel_elapsed: float = 0.0
var _travel_origin_au: Vector2 = Vector2.ZERO
var _travel_dest_au: Vector2 = Vector2.ZERO
var _travel_duration: float = 0.0
var _travel_align_duration: float = 0.0
var _travel_move_duration: float = 0.0
var _travel_dest_poi_id: String = ""
var _travel_ship_start_pos: Vector3 = Vector3.ZERO
var _travel_ship_end_pos: Vector3 = Vector3.ZERO
var _travel_uses_orbital_arc: bool = false
var _travel_arc_center_xz: Vector2 = Vector2.ZERO
var _travel_arc_entry_xz: Vector2 = Vector2.ZERO
var _travel_arc_exit_xz: Vector2 = Vector2.ZERO
var _travel_arc_radius: float = 0.0
var _travel_arc_start_angle: float = 0.0
var _travel_arc_delta_angle: float = 0.0
var _travel_entry_length: float = 0.0
var _travel_arc_length: float = 0.0
var _travel_exit_length: float = 0.0
var _travel_total_path_length: float = 0.0
var _travel_ship_start_basis: Basis = Basis.IDENTITY
var _travel_ship_end_basis: Basis = Basis.IDENTITY
var _travel_ship_arrival_basis: Basis = Basis.IDENTITY


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


static func travel_curve(progress: float) -> float:
	var t := clampf(progress, 0.0, 1.0)
	if t <= 0.5:
		return 2.0 * t * t
	var remaining := 1.0 - t
	return 1.0 - 2.0 * remaining * remaining


static func ship_travel_basis(from_pos: Vector3, to_pos: Vector3) -> Basis:
	var dir := to_pos - from_pos
	if dir.length_squared() < 0.0001:
		return Basis.IDENTITY
	return Basis.looking_at(dir.normalized(), Vector3.UP)


static func travel_path_progress(elapsed: float, total_duration: float, align_duration: float) -> float:
	if total_duration <= 0.0:
		return 1.0
	var move_duration := maxf(total_duration - align_duration, 0.001)
	var move_progress := clampf((elapsed - align_duration) / move_duration, 0.0, 1.0)
	return travel_curve(move_progress)


static func shortest_angle_delta(from_angle: float, to_angle: float) -> float:
	var delta := wrapf(to_angle - from_angle, -PI, PI)
	if is_equal_approx(absf(delta), PI):
		return PI
	return delta


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
		var current_scale: float = marker_node.scale.x
		var hit_r: float = FocusBubble.hit_radius(
			marker_node.poi_type, marker_node.poi_class, current_scale)
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
	if _travel_duration <= 0.0:
		return
	_travel_elapsed += delta
	var align_progress := 1.0
	if _travel_align_duration > 0.0:
		align_progress = clampf(_travel_elapsed / _travel_align_duration, 0.0, 1.0)
	var curved_progress := travel_path_progress(_travel_elapsed, _travel_duration, _travel_align_duration)
	var own_id: String = StateManager.player.get("id", "")
	if _ships.has(own_id):
		var ship: Node3D = _ships[own_id]
		var ship_pos := _travel_path_world_pos(curved_progress)
		if _travel_elapsed < _travel_align_duration:
			ship_pos = _travel_ship_start_pos
		ship.global_position = ship_pos
		if _travel_elapsed < _travel_align_duration:
			ship.basis = _travel_ship_start_basis.slerp(_travel_ship_end_basis, align_progress)
		else:
			var tangent := _travel_path_tangent(curved_progress)
			ship.basis = ship_travel_basis(ship_pos, ship_pos + tangent)
		ship._prev_pos = ship_pos
		ship._next_pos = ship_pos
		ship._tick_t = 1.0
		ship.engine_glow.light_energy = lerpf(3.0, 1.5, curved_progress)
		var camera := get_viewport().get_camera_3d()
		if camera and camera.has_method("snap_to_target"):
			camera.snap_to_target()


func _on_state_updated() -> void:
	if _is_animating_travel:
		return
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

	if not _is_animating_travel:
		_update_player_ship()
		_recompute_poi_positions()

	_refresh_remote_state()


func _recompute_poi_positions() -> void:
	for id in _poi_markers:
		var marker: Node3D = _poi_markers[id]
		marker.global_position = _poi_world_pos(_get_poi_au_pos(id))
		marker.scale = Vector3.ONE
		marker.visible = true


func _update_player_ship() -> void:
	if _is_animating_travel:
		return
	var pid: String = StateManager.player.get("id", "")
	if pid.is_empty():
		return

	var pos := _current_ship_world_pos()

	if _ships.has(pid):
		_ships[pid].update_ship_class(
			AssetLoader.resolve_ship_class_from_data(StateManager.ship),
			_player_ship_class_name(StateManager.ship)
		)
		_ships[pid].move_to(pos)
	else:
		var ship := SHIP_SCENE.instantiate() as Node3D
		add_child(ship)
		ship.setup(
			pid,
			StateManager.player.get("name", "You"),
			pos,
			true,
			"",
			"",
			AssetLoader.resolve_ship_class_from_data(StateManager.ship),
			_player_ship_class_name(StateManager.ship)
		)
		_ships[pid] = ship

		var camera := get_viewport().get_camera_3d()
		if camera and camera.has_method("follow"):
			camera.follow(ship)
			if camera.has_method("snap_to_target"):
				camera.snap_to_target()


func _sync_nearby_ships() -> void:
	var seen_ids: Array = []
	var default_center: Vector3 = _current_ship_world_pos()
	var layout_positions: Dictionary = _nearby_ship_layout_positions()

	for p in StateManager.nearby_players:
		var pid: String = p.get("player_id", "")
		if pid.is_empty() or pid == StateManager.player.get("id", ""):
			continue
		seen_ids.append(pid)

		var offset: Vector3 = layout_positions.get(pid, default_center + _nearby_ship_offset(pid))
		var prim: String = p.get("primary_color", "")
		var sec: String = p.get("secondary_color", "")
		if _ships.has(pid):
			_ships[pid].move_to(offset)
			_ships[pid].update_colors(prim, sec)
			_ships[pid].update_ship_class(
				AssetLoader.resolve_ship_class_from_data(p),
				_player_ship_class_name(p)
			)
		else:
			var ship := SHIP_SCENE.instantiate() as Node3D
			add_child(ship)
			ship.setup(
				pid,
				_player_display_name(p),
				offset,
				false,
				prim,
				sec,
				AssetLoader.resolve_ship_class_from_data(p),
				_player_ship_class_name(p)
			)
			ship.selected.connect(_on_ship_selected)
			_ships[pid] = ship

	for pirate in StateManager.nearby_pirates:
		var pid: String = "pirate_" + pirate.get("id", "")
		seen_ids.append(pid)

		var offset: Vector3 = layout_positions.get(pid, default_center + _nearby_ship_offset(pid))
		if _ships.has(pid):
			_ships[pid].move_to(offset)
		else:
			var ship := SHIP_SCENE.instantiate() as Node3D
			add_child(ship)
			ship.setup(pid, "⚠ " + pirate.get("name", "Pirate"), offset, false, "#cc3333", "#ff0000")
			ship.set_pirate_aura(pirate.get("is_boss", false), pirate.get("tier", "common"))
			ship.selected.connect(_on_ship_selected)
			_ships[pid] = ship

	var own_id: String = StateManager.player.get("id", "")
	for pid in _ships.keys():
		if pid != own_id and pid not in seen_ids:
			_ships[pid].queue_free()
			_ships.erase(pid)


func _nearby_ship_offset(pid: String) -> Vector3:
	var h := pid.hash()
	var angle := fmod(float(h), TAU)
	var dist := 3.0 + fmod(float(h) / 1000.0, 5.0)
	return Vector3(cos(angle) * dist, 0.0, sin(angle) * dist)


func _nearby_ship_layout_positions() -> Dictionary:
	var current_poi := _get_current_poi()
	var ship_entries: Array[Dictionary] = []
	for player_data_variant in StateManager.nearby_players:
		var player_data := player_data_variant as Dictionary
		var pid: String = player_data.get("player_id", "")
		if pid.is_empty() or pid == StateManager.player.get("id", ""):
			continue
		ship_entries.append({
			"id": pid,
			"class_id": AssetLoader.resolve_ship_class_from_data(player_data),
			"class_name": String(player_data.get("class_name", player_data.get("name", ""))),
		})

	for pirate_data_variant in StateManager.nearby_pirates:
		var pirate_data := pirate_data_variant as Dictionary
		var pirate_id: String = pirate_data.get("id", "")
		if pirate_id.is_empty():
			continue
		ship_entries.append({
			"id": "pirate_" + pirate_id,
			"class_id": AssetLoader.resolve_ship_class_from_data(pirate_data),
			"class_name": String(pirate_data.get("class_name", pirate_data.get("name", ""))),
		})

	ship_entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["id"] < b["id"])
	match current_poi.get("type", ""):
		"station":
			return _station_ship_layout_positions(current_poi, ship_entries)
		"asteroid", "asteroid_field", "asteroid_belt", "ice_field":
			return _belt_ship_layout_positions(current_poi, ship_entries)
		_:
			return {}


func _player_display_name(player_data: Dictionary) -> String:
	for key in ["username", "player_name", "name"]:
		var value := String(player_data.get(key, "")).strip_edges()
		if not value.is_empty():
			return value
	if bool(player_data.get("anonymous", false)):
		return "Anonymous"
	return "Unknown"


func _player_ship_class_name(player_data: Dictionary) -> String:
	for candidate in [player_data, player_data.get("ship", null), player_data.get("active_ship", null), player_data.get("player_ship", null)]:
		if not (candidate is Dictionary):
			continue
		var candidate_dict := candidate as Dictionary
		for key in ["class_name", "ship_class_name", "ship_class", "name"]:
			var value := String(candidate_dict.get(key, "")).strip_edges()
			if not value.is_empty():
				return value
	return ""


func _station_ship_layout_positions(station_poi: Dictionary, ship_entries: Array[Dictionary]) -> Dictionary:
	var positions := {}
	if ship_entries.is_empty():
		return positions

	var station_radius := FocusBubble.poi_radius("station", station_poi.get("class", ""))
	var ring_radius := station_radius + STATION_RING_CLEARANCE + STATION_BERTH_REFERENCE_SPAN * 0.5
	var berth_spacing := STATION_BERTH_REFERENCE_SPAN + STATION_BERTH_MARGIN
	var ring_capacity := _station_ring_capacity(ring_radius, berth_spacing)
	var layer_count := maxi(STATION_BASE_LAYERS, int(ceili(float(ship_entries.size()) / float(maxi(ring_capacity, 1)))))
	var total_slots := ring_capacity * layer_count
	var center := _poi_world_pos(FocusBubble.poi_au_pos(station_poi))
	var angle_offset := fmod(float(String(station_poi.get("id", "")).hash()), TAU)
	var occupied_slots := {}

	for ship_entry in ship_entries:
		var slot_index := _station_berth_slot_index(ship_entry.get("id", ""), total_slots, occupied_slots)
		var local_offset := _station_ring_offset(slot_index, ring_capacity, ring_radius, STATION_LAYER_SPACING, angle_offset)
		positions[ship_entry.get("id", "")] = center + local_offset
	return positions


func _belt_ship_layout_positions(field_poi: Dictionary, ship_entries: Array[Dictionary]) -> Dictionary:
	var positions := {}
	if ship_entries.is_empty():
		return positions
	var center := _poi_world_pos(FocusBubble.poi_au_pos(field_poi))
	var field_radius := FocusBubble.poi_radius(field_poi.get("type", ""), field_poi.get("class", ""))
	var ring_radius := maxf(field_radius * 0.8, BELT_SHIP_RING_RADIUS)
	var layers := maxi(int(ceili(float(ship_entries.size()) / 18.0)), 1)
	var per_layer := maxi(int(ceili(float(ship_entries.size()) / float(layers))), 1)
	for index in ship_entries.size():
		var ship_entry := ship_entries[index]
		var layer_index := int(index / per_layer)
		var slot_index := index % per_layer
		var layer_y := (float(layer_index) - float(layers - 1) * 0.5) * BELT_SHIP_VERTICAL_SPAN
		var angle := TAU * float(slot_index) / float(per_layer)
		var radial_jitter := _stable_unit_value(ship_entry.get("id", ""), 17) * BELT_SHIP_CLEARANCE
		var y_jitter := (_stable_unit_value(ship_entry.get("id", ""), 31) - 0.5) * BELT_SHIP_VERTICAL_SPAN * 0.5
		var local_offset := Vector3(
			cos(angle) * (ring_radius + radial_jitter),
			layer_y + y_jitter,
			sin(angle) * (ring_radius + radial_jitter)
		)
		positions[ship_entry.get("id", "")] = center + local_offset
	return positions


static func _station_ring_capacity(ring_radius: float, berth_spacing: float) -> int:
	if berth_spacing <= 0.001:
		return 1
	return maxi(int(floor((TAU * ring_radius) / berth_spacing)), 1)


static func _station_ring_layer_offset(layer_index: int) -> int:
	if layer_index <= 0:
		return 0
	var band := int((layer_index + 1) / 2)
	return band if layer_index % 2 == 1 else -band


static func _station_berth_slot_index(ship_id: String, total_slots: int, occupied_slots: Dictionary) -> int:
	var clamped_total_slots := maxi(total_slots, 1)
	var preferred_slot := int(posmod(ship_id.hash(), clamped_total_slots))
	for probe in range(clamped_total_slots):
		var slot_index := (preferred_slot + probe) % clamped_total_slots
		if occupied_slots.has(slot_index):
			continue
		occupied_slots[slot_index] = true
		return slot_index
	occupied_slots[0] = true
	return 0


static func _station_ring_offset(
	index: int,
	ring_capacity: int,
	ring_radius: float,
	layer_spacing: float,
	angle_offset: float
) -> Vector3:
	var clamped_capacity := maxi(ring_capacity, 1)
	var layer_index := int(index / clamped_capacity)
	var slot_index := index % clamped_capacity
	var angle := angle_offset + TAU * float(slot_index) / float(clamped_capacity)
	var y := float(_station_ring_layer_offset(layer_index)) * layer_spacing
	return Vector3(cos(angle) * ring_radius, y, sin(angle) * ring_radius)


static func _stable_unit_value(seed_text: String, salt: int) -> float:
	var hashed: int = abs(seed_text.hash() + salt * 7919)
	return fmod(float(hashed), 1000.0) / 1000.0


func _sync_poi_markers() -> void:
	if _is_animating_travel:
		return
	var pois: Array = StateManager.current_system.get("pois", [])
	var seen_ids: Array = []

	for poi in pois:
		var id: String = poi.get("id", "")
		if id.is_empty():
			continue
		seen_ids.append(id)

		if _poi_markers.has(id):
			continue  # Repositioned by _recompute_poi_positions

		var poi_au := FocusBubble.poi_au_pos(poi)
		var pos := _poi_world_pos(poi_au)

		var marker := POI_MARKER_SCENE.instantiate() as Node3D
		add_child(marker)
		marker.setup(id, poi.get("name", "Unknown"), poi.get("type", ""), pos, poi.get("class", ""))
		marker.selected.connect(_on_poi_marker_selected)
		_poi_markers[id] = marker

	for id in _poi_markers.keys():
		if id not in seen_ids:
			_poi_markers[id].queue_free()
			_poi_markers.erase(id)

	_recompute_poi_positions()


func _on_poi_marker_selected(marker: Node3D) -> void:
	if _selected_poi_id and _poi_markers.has(_selected_poi_id):
		_poi_markers[_selected_poi_id].set_selected(false)

	if _selected_ship_id:
		deselect_ship()

	if marker.poi_id == _selected_poi_id:
		_selected_poi_id = ""
		poi_deselected.emit()
	else:
		_selected_poi_id = marker.poi_id
		marker.set_selected(true)
		poi_selected.emit(marker.poi_id, marker.poi_name, marker.poi_type)


func _on_ship_selected(ship_node: Node3D) -> void:
	if _selected_ship_id and _ships.has(_selected_ship_id):
		_ships[_selected_ship_id].set_selected(false)

	if _selected_poi_id:
		deselect_poi()

	if ship_node.player_id == _selected_ship_id:
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


func _get_player_au_pos() -> Vector2:
	var poi_id: String = StateManager.location.get("poi_id", "")
	if not poi_id.is_empty():
		for poi in StateManager.current_system.get("pois", []):
			if poi.get("id", "") == poi_id:
				return FocusBubble.poi_au_pos(poi)
	var pos: Dictionary = StateManager.location.get("position", {})
	return Vector2(pos.get("x", 0.0), pos.get("y", 0.0))


func _get_current_poi() -> Dictionary:
	var poi_id: String = StateManager.location.get("poi_id", "")
	if poi_id.is_empty():
		return {}
	for poi_variant in StateManager.current_system.get("pois", []):
		var poi := poi_variant as Dictionary
		if poi.get("id", "") == poi_id:
			return poi
	return {}


func _get_poi_au_pos(poi_id: String) -> Vector2:
	for poi in StateManager.current_system.get("pois", []):
		if poi.get("id", "") == poi_id:
			return FocusBubble.poi_au_pos(poi)
	return Vector2.ZERO


func _poi_world_pos(poi_au: Vector2) -> Vector3:
	return Vector3(poi_au.x * AU_TO_WORLD, 0.0, poi_au.y * AU_TO_WORLD)


func _ship_orbit_offset_for_poi(poi_id: String) -> Vector3:
	for poi in StateManager.current_system.get("pois", []):
		if poi.get("id", "") == poi_id:
			var poi_type: String = poi.get("type", "")
			var radius := FocusBubble.poi_radius(poi_type, poi.get("class", ""))
			var orbit_distance := radius * FocusBubble.ORBIT_MARGIN
			match poi_type:
				"sun", "star", "planet", "moon":
					return Vector3(0.0, orbit_distance, 0.0)
				_:
					return Vector3(0.0, 0.0, orbit_distance)
	return Vector3(0.0, 0.0, FocusBubble.SCALE_PLANET_SMALL * FocusBubble.ORBIT_MARGIN)


func _ship_world_pos_for_poi(poi_id: String) -> Vector3:
	return _poi_world_pos(_get_poi_au_pos(poi_id)) + _ship_orbit_offset_for_poi(poi_id)


func _current_ship_world_pos() -> Vector3:
	var poi_id: String = StateManager.location.get("poi_id", "")
	if not poi_id.is_empty():
		return _ship_world_pos_for_poi(poi_id)
	var pos: Dictionary = StateManager.location.get("position", {})
	return _poi_world_pos(Vector2(pos.get("x", 0.0), pos.get("y", 0.0)))


func _travel_endpoint_for_poi(poi_id: String) -> Vector3:
	return _ship_world_pos_for_poi(poi_id)


static func _distance_point_to_segment(point: Vector2, start: Vector2, end: Vector2) -> float:
	var segment := end - start
	var segment_len_sq := segment.length_squared()
	if segment_len_sq <= 0.0001:
		return point.distance_to(start)
	var t := clampf((point - start).dot(segment) / segment_len_sq, 0.0, 1.0)
	return point.distance_to(start + segment * t)


static func _tangent_points_to_circle(point: Vector2, center: Vector2, radius: float) -> Array:
	var rel := point - center
	var dist := rel.length()
	if dist <= radius:
		return []
	var base_angle := atan2(rel.y, rel.x)
	var offset := acos(radius / dist)
	return [
		center + Vector2(cos(base_angle + offset), sin(base_angle + offset)) * radius,
		center + Vector2(cos(base_angle - offset), sin(base_angle - offset)) * radius,
	]


func _best_transfer_anchor(origin_world: Vector3, dest_world: Vector3) -> Array:
	var midpoint := (Vector2(origin_world.x, origin_world.z) + Vector2(dest_world.x, dest_world.z)) * 0.5
	var best_dist := INF
	var best_anchor := Vector2.ZERO
	var best_radius := 0.0
	var found := false
	for poi in StateManager.current_system.get("pois", []):
		var poi_type: String = poi.get("type", "")
		if poi_type != "sun" and poi_type != "star":
			continue
		var poi_au := FocusBubble.poi_au_pos(poi)
		var anchor_3d := _poi_world_pos(poi_au)
		var anchor := Vector2(anchor_3d.x, anchor_3d.z)
		var dist := anchor.distance_squared_to(midpoint)
		if dist < best_dist:
			best_dist = dist
			best_anchor = anchor
			best_radius = FocusBubble.poi_radius(poi_type, poi.get("class", "")) + STAR_CLEARANCE_PADDING
			found = true
	return [found, best_anchor, best_radius]


func _travel_orbital_arc_params(origin_world: Vector3, dest_world: Vector3) -> Array:
	var anchor_result := _best_transfer_anchor(origin_world, dest_world)
	var has_anchor: bool = anchor_result[0]
	if not has_anchor:
		return [false]

	var center: Vector2 = anchor_result[1]
	var clearance_radius: float = anchor_result[2]
	var start_xz := Vector2(origin_world.x, origin_world.z)
	var end_xz := Vector2(dest_world.x, dest_world.z)
	if _distance_point_to_segment(center, start_xz, end_xz) >= clearance_radius:
		return [false]

	var start_tangents := _tangent_points_to_circle(start_xz, center, clearance_radius)
	var end_tangents := _tangent_points_to_circle(end_xz, center, clearance_radius)
	if start_tangents.is_empty() or end_tangents.is_empty():
		return [false]

	var best_total_length := INF
	var best_entry := Vector2.ZERO
	var best_exit := Vector2.ZERO
	var best_start_angle := 0.0
	var best_delta_angle := 0.0
	var best_entry_length := 0.0
	var best_arc_length := 0.0
	var best_exit_length := 0.0

	for start_tangent_variant in start_tangents:
		var start_tangent: Vector2 = start_tangent_variant
		var start_angle := atan2(start_tangent.y - center.y, start_tangent.x - center.x)
		var entry_length := start_xz.distance_to(start_tangent)
		for end_tangent_variant in end_tangents:
			var end_tangent: Vector2 = end_tangent_variant
			var end_angle := atan2(end_tangent.y - center.y, end_tangent.x - center.x)
			var delta_angle := shortest_angle_delta(start_angle, end_angle)
			var arc_length := absf(delta_angle) * clearance_radius
			var exit_length := end_tangent.distance_to(end_xz)
			var total_length := entry_length + arc_length + exit_length
			if total_length < best_total_length:
				best_total_length = total_length
				best_entry = start_tangent
				best_exit = end_tangent
				best_start_angle = start_angle
				best_delta_angle = delta_angle
				best_entry_length = entry_length
				best_arc_length = arc_length
				best_exit_length = exit_length

	if not is_finite(best_total_length):
		return [false]

	return [
		true,
		center,
		clearance_radius,
		best_entry,
		best_exit,
		best_start_angle,
		best_delta_angle,
		best_entry_length,
		best_arc_length,
		best_exit_length,
		best_total_length,
	]


func _travel_path_world_pos(progress: float) -> Vector3:
	if _travel_uses_orbital_arc:
		var distance_along_path := _travel_total_path_length * clampf(progress, 0.0, 1.0)
		var world_pos := Vector3.ZERO
		if distance_along_path <= _travel_entry_length:
			var entry_t := 0.0 if _travel_entry_length <= 0.001 else distance_along_path / _travel_entry_length
			var xz := Vector2(_travel_ship_start_pos.x, _travel_ship_start_pos.z).lerp(_travel_arc_entry_xz, entry_t)
			world_pos = Vector3(xz.x, 0.0, xz.y)
		elif distance_along_path <= _travel_entry_length + _travel_arc_length:
			var arc_distance := distance_along_path - _travel_entry_length
			var arc_t := 0.0 if _travel_arc_length <= 0.001 else arc_distance / _travel_arc_length
			var angle := _travel_arc_start_angle + _travel_arc_delta_angle * arc_t
			var xz := _travel_arc_center_xz + Vector2(cos(angle), sin(angle)) * _travel_arc_radius
			world_pos = Vector3(xz.x, 0.0, xz.y)
		else:
			var exit_distance := distance_along_path - _travel_entry_length - _travel_arc_length
			var exit_t := 1.0 if _travel_exit_length <= 0.001 else clampf(exit_distance / _travel_exit_length, 0.0, 1.0)
			var xz := _travel_arc_exit_xz.lerp(Vector2(_travel_ship_end_pos.x, _travel_ship_end_pos.z), exit_t)
			world_pos = Vector3(xz.x, 0.0, xz.y)

		world_pos.y = lerpf(_travel_ship_start_pos.y, _travel_ship_end_pos.y, progress)
		return world_pos
	return _travel_ship_start_pos.lerp(_travel_ship_end_pos, progress)


func _travel_path_tangent(progress: float) -> Vector3:
	if _travel_uses_orbital_arc:
		var t0 := clampf(progress - 0.001, 0.0, 1.0)
		var t1 := clampf(progress + 0.001, 0.0, 1.0)
		return _travel_path_world_pos(t1) - _travel_path_world_pos(t0)
	return _travel_ship_end_pos - _travel_ship_start_pos


func _refresh_remote_state() -> void:
	if not NetworkManager.is_authenticated:
		return
	NetworkManager.send_command("get_nearby", {}, func(content):
		StateManager.update_nearby(content)
	)
	NetworkManager.send_command("get_system", {}, func(content):
		StateManager.update_system(content)
	)


# --- Travel animation ---

func _on_travel_started(dest_poi_id: String, _dest_poi_name: String) -> void:
	_travel_dest_poi_id = dest_poi_id
	_travel_origin_au = _get_player_au_pos()
	_travel_dest_au = _get_poi_au_pos(dest_poi_id)

	if _travel_origin_au.distance_to(_travel_dest_au) < 0.001:
		_travel_dest_poi_id = ""
		return

	# Compute exact travel duration from game formula:
	# ticks = ceil(distance / ship.speed), minimum 1
	var distance := _travel_origin_au.distance_to(_travel_dest_au)
	var ship_speed := maxf(float(StateManager.ship.get("speed", 1)), 0.1)
	var ticks := maxi(ceili(distance / ship_speed), 1)
	_travel_duration = ticks * NetworkManager.tick_duration
	_travel_align_duration = minf(PRELAUNCH_ALIGN_TIME, _travel_duration)
	_travel_move_duration = maxf(_travel_duration - _travel_align_duration, 0.001)

	_travel_elapsed = 0.0
	_is_animating_travel = true

	var own_id: String = StateManager.player.get("id", "")
	_travel_ship_start_pos = _current_ship_world_pos()
	if _ships.has(own_id):
		_travel_ship_start_basis = _ships[own_id].basis
		_ships[own_id].global_position = _travel_ship_start_pos
		_ships[own_id]._prev_pos = _travel_ship_start_pos
		_ships[own_id]._next_pos = _travel_ship_start_pos
		_ships[own_id]._tick_t = 1.0
	else:
		_travel_ship_start_basis = Basis.IDENTITY
	_travel_ship_end_pos = _travel_endpoint_for_poi(dest_poi_id)
	var arc_result := _travel_orbital_arc_params(_travel_ship_start_pos, _travel_ship_end_pos)
	_travel_uses_orbital_arc = arc_result[0]
	if _travel_uses_orbital_arc:
		_travel_arc_center_xz = arc_result[1]
		_travel_arc_radius = arc_result[2]
		_travel_arc_entry_xz = arc_result[3]
		_travel_arc_exit_xz = arc_result[4]
		_travel_arc_start_angle = arc_result[5]
		_travel_arc_delta_angle = arc_result[6]
		_travel_entry_length = arc_result[7]
		_travel_arc_length = arc_result[8]
		_travel_exit_length = arc_result[9]
		_travel_total_path_length = arc_result[10]
	else:
		_travel_arc_center_xz = Vector2.ZERO
		_travel_arc_radius = 0.0
		_travel_arc_entry_xz = Vector2.ZERO
		_travel_arc_exit_xz = Vector2.ZERO
		_travel_arc_start_angle = 0.0
		_travel_arc_delta_angle = 0.0
		_travel_entry_length = 0.0
		_travel_arc_length = 0.0
		_travel_exit_length = 0.0
		_travel_total_path_length = 0.0
	_travel_ship_end_basis = ship_travel_basis(
		_travel_ship_start_pos, _travel_ship_start_pos + _travel_path_tangent(0.0))
	_travel_ship_arrival_basis = ship_travel_basis(
		_travel_ship_end_pos - _travel_path_tangent(1.0), _travel_ship_end_pos)

	if _poi_markers.has(dest_poi_id):
		_poi_markers[dest_poi_id].set_selected(true)


func _on_travel_ended() -> void:
	if not _is_animating_travel:
		return
	var dest_id := _travel_dest_poi_id
	_is_animating_travel = false
	_travel_elapsed = 0.0
	_travel_duration = 0.0
	_travel_align_duration = 0.0
	_travel_move_duration = 0.0

	if not dest_id.is_empty() and _poi_markers.has(dest_id):
		_poi_markers[dest_id].set_selected(false)

	var own_id: String = StateManager.player.get("id", "")
	if _ships.has(own_id):
		var pos := _current_ship_world_pos()
		_ships[own_id].global_position = pos
		_ships[own_id].basis = _travel_ship_arrival_basis
		_ships[own_id]._prev_pos = pos
		_ships[own_id]._next_pos = pos
		_ships[own_id]._tick_t = 1.0
		_ships[own_id].engine_glow.light_energy = 0.8

	_travel_dest_poi_id = ""
	_travel_ship_start_pos = Vector3.ZERO
	_travel_ship_end_pos = Vector3.ZERO
	_travel_uses_orbital_arc = false
	_travel_arc_center_xz = Vector2.ZERO
	_travel_arc_entry_xz = Vector2.ZERO
	_travel_arc_exit_xz = Vector2.ZERO
	_travel_arc_radius = 0.0
	_travel_arc_start_angle = 0.0
	_travel_arc_delta_angle = 0.0
	_travel_entry_length = 0.0
	_travel_arc_length = 0.0
	_travel_exit_length = 0.0
	_travel_total_path_length = 0.0
	_travel_ship_start_basis = Basis.IDENTITY
	_travel_ship_end_basis = Basis.IDENTITY
	_travel_ship_arrival_basis = Basis.IDENTITY

	_recompute_poi_positions()



func _on_travel_aborted(_origin_poi_id: String) -> void:
	if not _is_animating_travel:
		return
	var dest_id := _travel_dest_poi_id
	_is_animating_travel = false
	_travel_elapsed = 0.0
	_travel_duration = 0.0
	_travel_align_duration = 0.0
	_travel_move_duration = 0.0

	# Deselect destination marker
	if not dest_id.is_empty() and _poi_markers.has(dest_id):
		_poi_markers[dest_id].set_selected(false)

	var own_id: String = StateManager.player.get("id", "")
	if _ships.has(own_id):
		var pos := _current_ship_world_pos()
		_ships[own_id].global_position = pos
		_ships[own_id].basis = _travel_ship_start_basis
		_ships[own_id]._prev_pos = pos
		_ships[own_id]._next_pos = pos
		_ships[own_id]._tick_t = 1.0
		_ships[own_id].engine_glow.light_energy = 0.8

	_travel_dest_poi_id = ""
	_travel_ship_start_pos = Vector3.ZERO
	_travel_ship_end_pos = Vector3.ZERO
	_travel_uses_orbital_arc = false
	_travel_arc_center_xz = Vector2.ZERO
	_travel_arc_entry_xz = Vector2.ZERO
	_travel_arc_exit_xz = Vector2.ZERO
	_travel_arc_radius = 0.0
	_travel_arc_start_angle = 0.0
	_travel_arc_delta_angle = 0.0
	_travel_entry_length = 0.0
	_travel_arc_length = 0.0
	_travel_exit_length = 0.0
	_travel_total_path_length = 0.0
	_travel_ship_start_basis = Basis.IDENTITY
	_travel_ship_end_basis = Basis.IDENTITY
	_travel_ship_arrival_basis = Basis.IDENTITY

	_recompute_poi_positions()



# --- Jump (inter-system) handlers ---

func _on_jump_started() -> void:
	for marker in _poi_markers.values():
		marker.visible = false
	for ship in _ships.values():
		ship.visible = false


func _on_jump_ended() -> void:
	pass
