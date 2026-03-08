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
		location = {
			"system_id": data.get("system", {}).get("id", ""),
			"poi_id": poi.get("id", ""),
			"docked_at": "",
			# Keep the extra POI fields (name, type, position) for convenience
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
	if data.has("cargo"):
		cargo = data["cargo"]
		cargo_changed.emit()
	if data.has("modules"):
		modules = data["modules"]
	if data.has("skills"):
		skills = data["skills"]
	if data.has("missions"):
		missions = data["missions"]
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
	return not location.get("docked_at", "").is_empty()


func get_current_poi_name() -> String:
	# Try direct name from location (set during initial state)
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
	return _safe_pct(ship.get("hull", 0), ship.get("hull_max", 1))


func shield_pct() -> float:
	return _safe_pct(ship.get("shield", 0), ship.get("shield_max", 1))


func fuel_pct() -> float:
	return _safe_pct(ship.get("fuel", 0), ship.get("fuel_max", 1))


func cargo_pct() -> float:
	return _safe_pct(ship.get("cargo_used", 0), ship.get("cargo_max", 1))


func _safe_pct(value, maximum) -> float:
	var m := float(maximum)
	return float(value) / m if m > 0.0 else 0.0
