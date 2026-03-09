extends Node

# Mirrors V2GameState from the server. Updated on every command response and poll.
var player: Dictionary = {}
var ship: Dictionary = {}
var location: Dictionary = {}
var cargo: Array = []
var modules: Array = []
var skills: Dictionary = {}
var missions: Dictionary = {}
var hints: Array = []

# System data — loaded separately via get_system
var current_system: Dictionary = {}
var nearby_players: Array = []
var nearby_pirates: Array = []

# Server-side pending actions
var has_pending: bool = false

# Galaxy map data — cached locally after first fetch
var galaxy_map: Dictionary = {}  # {systems: Array, total_count: int}

# Travel state
var travel_dest_poi_id: String = ""
var travel_dest_poi_name: String = ""
var travel_origin_poi_id: String = ""

var is_traveling: bool = false:
	set(value):
		if is_traveling == value:
			return
		is_traveling = value
		if value:
			travel_started.emit(travel_dest_poi_id, travel_dest_poi_name)
		else:
			travel_ended.emit()

# Mining state
var is_mining: bool = false:
	set(value):
		if is_mining == value:
			return
		is_mining = value
		if value:
			mining_started.emit()
		else:
			mining_ended.emit()

# Docking / undocking state
var is_docking: bool = false:
	set(value):
		if is_docking == value:
			return
		is_docking = value
		if value:
			docking_started.emit()
		else:
			docking_ended.emit()

var is_undocking: bool = false:
	set(value):
		if is_undocking == value:
			return
		is_undocking = value
		if value:
			undocking_started.emit()
		else:
			undocking_ended.emit()

# Jump state (inter-system travel)
var is_jumping: bool = false:
	set(value):
		if is_jumping == value:
			return
		is_jumping = value
		if value:
			jump_started.emit()
		else:
			jump_ended.emit()

# Battle state — loaded via spacemolt_battle/get_status
var in_combat: bool = false
var battle: Dictionary = {}

signal state_updated
signal ship_updated
signal location_changed(old_poi_id: String, new_poi_id: String)
signal cargo_changed
signal nearby_updated
signal battle_updated
signal combat_started
signal combat_ended
signal galaxy_map_loaded
signal travel_started(dest_poi_id: String, dest_poi_name: String)
signal travel_ended
signal travel_aborted(origin_poi_id: String)
signal mining_started
signal mining_ended
signal docking_started
signal docking_ended
signal undocking_started
signal undocking_ended
signal jump_started
signal jump_ended


const MAP_CACHE_PATH := "user://galaxy_map.json"


func begin_travel(dest_poi_id: String, dest_poi_name: String) -> void:
	travel_origin_poi_id = location.get("poi_id", "")
	travel_dest_poi_id = dest_poi_id
	travel_dest_poi_name = dest_poi_name
	is_traveling = true  # emits travel_started with dest info


func end_travel() -> void:
	travel_dest_poi_id = ""
	travel_dest_poi_name = ""
	travel_origin_poi_id = ""
	is_traveling = false  # emits travel_ended


func abort_travel() -> void:
	var origin := travel_origin_poi_id
	travel_dest_poi_id = ""
	travel_dest_poi_name = ""
	travel_origin_poi_id = ""
	is_traveling = false  # emits travel_ended
	travel_aborted.emit(origin)


func reset() -> void:
	player = {}
	ship = {}
	location = {}
	cargo = []
	modules = []
	skills = {}
	missions = {}
	hints = []
	has_pending = false
	current_system = {}
	nearby_players = []
	nearby_pirates = []
	in_combat = false
	battle = {}
	travel_dest_poi_id = ""
	travel_dest_poi_name = ""
	travel_origin_poi_id = ""
	is_traveling = false
	is_mining = false
	is_docking = false
	is_undocking = false
	is_jumping = false


func set_initial_state(data: Dictionary) -> void:
	# Called with LoginResponse or RegisterResponse structuredContent
	if data.has("player"):
		player = data["player"]
	if data.has("ship"):
		ship = data["ship"]
	if data.has("system"):
		current_system = data["system"]
	if data.has("poi"):
		# LoginResponse gives a full POI object; normalize to the same format
		# that get_status returns so the rest of the code can use one format.
		var poi: Dictionary = data["poi"]
		var docked_at: String = data.get("player", {}).get("docked_at_base", "")
		location = {
			"system_id": data.get("system", {}).get("id", ""),
			"poi_id": poi.get("id", ""),
			"poi_name": poi.get("name", ""),
			"poi_type": poi.get("type", ""),
			"docked_at": docked_at,
			# Keep the extra POI fields for convenience
			"name": poi.get("name", ""),
			"type": poi.get("type", ""),
			"position": poi.get("position", {}),
		}
	state_updated.emit()


func update_state(data: Dictionary) -> void:
	# Called with V2GameState structuredContent from get_status or any command response
	if data.is_empty():
		return

	var old_poi: String = location.get("poi_id", "")

	if data.has("player"):
		player = data["player"]
	if data.has("ship"):
		ship = data["ship"]
		ship_updated.emit()
	if data.has("location"):
		location = data["location"]
		var new_poi: String = location.get("poi_id", "")
		if new_poi != old_poi:
			location_changed.emit(old_poi, new_poi)
		# get_status embeds nearby data in location — extract it
		if location.has("nearby_players"):
			nearby_players = location.get("nearby_players", [])
			nearby_pirates = location.get("nearby_pirates", [])
			nearby_updated.emit()
	if data.has("cargo"):
		cargo = data["cargo"]
		cargo_changed.emit()
	if data.has("modules"):
		modules = data["modules"]
	if data.has("skills"):
		skills = data["skills"]
	if data.has("missions"):
		var m = data["missions"]
		if m is Dictionary:
			missions = m
		elif m is Array:
			missions = {"list": m}
		else:
			missions = {}
	if data.has("hints"):
		hints = data["hints"]
	if data.has("queue"):
		has_pending = data["queue"].get("has_pending", false)

	state_updated.emit()


func update_nearby(data: Dictionary) -> void:
	nearby_players = data.get("nearby", [])
	nearby_pirates = data.get("pirates", [])
	nearby_updated.emit()


func update_system(data: Dictionary) -> void:
	if data.has("system"):
		current_system = data["system"]
		state_updated.emit()
	elif data.has("pois"):
		# get_system may return system data directly at the top level
		current_system = data
		state_updated.emit()


func update_battle(data: Dictionary) -> void:
	battle = data
	var was_in_combat := in_combat
	in_combat = data.get("is_participant", false)

	if in_combat and not was_in_combat:
		combat_started.emit()
	elif not in_combat and was_in_combat:
		combat_ended.emit()

	battle_updated.emit()


func clear_battle() -> void:
	battle = {}
	var was_in_combat := in_combat
	in_combat = false
	if was_in_combat:
		combat_ended.emit()
	battle_updated.emit()


func get_my_participant() -> Dictionary:
	var my_id: String = player.get("id", "")
	for p in battle.get("participants", []):
		if p.get("player_id", "") == my_id:
			return p
	return {}


func get_battle_participants() -> Array:
	return battle.get("participants", [])


func get_battle_sides() -> Array:
	return battle.get("sides", [])


# --- Convenience helpers ---

func is_docked() -> bool:
	var docked_at = location.get("docked_at", "")
	return docked_at is String and not docked_at.is_empty()


func get_current_poi_name() -> String:
	# Try poi_name from get_status location
	var poi_name: String = location.get("poi_name", "")
	if not poi_name.is_empty():
		return poi_name
	# Try direct name from location (set during initial state normalization)
	var name_val: String = location.get("name", "")
	if not name_val.is_empty():
		return name_val
	# Look up from system POI data
	var poi_id: String = location.get("poi_id", "")
	for poi in current_system.get("pois", []):
		if poi.get("id", "") == poi_id:
			return poi.get("name", "")
	return ""


func hull_pct() -> float:
	return _safe_pct(ship.get("hull", 0), ship.get("max_hull", 1))


func shield_pct() -> float:
	return _safe_pct(ship.get("shield", 0), ship.get("max_shield", 1))


func fuel_pct() -> float:
	return _safe_pct(ship.get("fuel", 0), ship.get("max_fuel", 1))


func cargo_pct() -> float:
	return _safe_pct(ship.get("cargo_used", 0), ship.get("cargo_capacity", 1))


func _safe_pct(value, maximum) -> float:
	var m := float(maximum)
	return float(value) / m if m > 0.0 else 0.0


# --- Galaxy Map ---

func set_galaxy_map(data: Dictionary) -> void:
	galaxy_map = data
	_save_map_cache(data)
	galaxy_map_loaded.emit()


func load_cached_map() -> bool:
	if not FileAccess.file_exists(MAP_CACHE_PATH):
		return false
	var f := FileAccess.open(MAP_CACHE_PATH, FileAccess.READ)
	if not f:
		return false
	var text := f.get_as_text()
	f.close()
	var data = JSON.parse_string(text)
	if data is Dictionary and data.has("systems"):
		galaxy_map = data
		galaxy_map_loaded.emit()
		return true
	return false


func _save_map_cache(data: Dictionary) -> void:
	var f := FileAccess.open(MAP_CACHE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data))
		f.close()


func get_system_by_id(system_id: String) -> Dictionary:
	for s in galaxy_map.get("systems", []):
		if s.get("system_id", "") == system_id:
			return s
	return {}


func get_current_system_id() -> String:
	return current_system.get("id", location.get("system_id", ""))
