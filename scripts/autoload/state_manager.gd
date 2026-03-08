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

signal state_updated
signal ship_updated
signal location_changed(old_poi_id: String, new_poi_id: String)
signal nearby_updated


func set_initial_state(data: Dictionary) -> void:
	# Called with LoginResponse or RegisterResponse structuredContent
	if data.has("player"):
		player = data["player"]
	if data.has("ship"):
		ship = data["ship"]
	if data.has("system"):
		current_system = data["system"]
	if data.has("poi"):
		location = data["poi"]
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
	if data.has("modules"):
		modules = data["modules"]
	if data.has("skills"):
		skills = data["skills"]
	if data.has("missions"):
		missions = data["missions"]
	if data.has("hints"):
		hints = data["hints"]

	state_updated.emit()


func update_nearby(data: Dictionary) -> void:
	nearby_players = data.get("nearby", [])
	nearby_pirates = data.get("pirates", [])
	nearby_updated.emit()


func update_system(data: Dictionary) -> void:
	if data.has("system"):
		current_system = data["system"]


# --- Convenience helpers ---

func is_docked() -> bool:
	return not location.get("docked_at", "").is_empty()


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
