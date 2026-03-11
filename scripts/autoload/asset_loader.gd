extends Node

const SHIP_DATA_PATH := "res://scripts/data/ships.json"
const SHIP_WORLD_SPAN_BY_SCALE := {
	1: 4.0,
	2: 8.0,
	3: 14.0,
	4: 22.0,
	5: 34.0,
}

var _ship_scenes: Dictionary = {}
var _placeholder_mesh: BoxMesh
var _ship_class_aliases := {
	"theoria": "theoria",
	"theoria_class": "theoria",
}
var _ship_scene_aliases := {
	"archimedes": "solarian_archimedes",
	"axiom": "solarian_axiom",
	"caravan": "nebula_caravan",
	"liminal": "voidborn_liminal",
}
var _ship_data_aliases := {
	"archimedes": "archimedes",
	"axiom": "axiom",
	"caravan": "caravan",
	"liminal": "liminal",
	"nebula_caravan": "caravan",
	"prospector": "threshold",
	"solarian_archimedes": "archimedes",
	"solarian_axiom": "axiom",
	"voidborn_liminal": "liminal",
}
var _ship_data_by_id: Dictionary = {}


func _ready() -> void:
	_placeholder_mesh = BoxMesh.new()
	_placeholder_mesh.size = Vector3(1.5, 0.4, 2.5)
	_load_ship_data()


func resolve_ship_class_id(class_id: String, ship_class_name: String = "") -> String:
	for raw_value in [class_id, ship_class_name]:
		var normalized := String(raw_value).strip_edges().to_lower()
		if normalized.is_empty():
			continue
		normalized = normalized.replace(" ", "_").replace("-", "_")
		if _ship_class_aliases.has(normalized):
			return _ship_class_aliases[normalized]
		return normalized
	return ""


func resolve_ship_class_from_data(ship_data: Dictionary) -> String:
	for candidate_dict in _ship_data_candidates(ship_data):
		var class_value: Variant = _first_present_value(candidate_dict, [
			"class_id",
			"ship_class_id",
			"ship_class",
			"active_ship_class",
			"stored_ship_class",
			"class",
		])
		var class_name_value: Variant = _first_present_value(candidate_dict, [
			"class_name",
			"ship_class_name",
			"name",
		])
		var resolved := resolve_ship_class_id(
			_stringify_ship_class_value(class_value),
			_stringify_ship_class_value(class_name_value)
		)
		if not resolved.is_empty():
			return resolved
	return ""


func describe_ship_class_from_data(ship_data: Dictionary) -> String:
	var parts: Array[String] = []
	for candidate_dict in _ship_data_candidates(ship_data):
		for key in ["class_id", "ship_class_id", "ship_class", "active_ship_class", "stored_ship_class", "class", "class_name", "ship_class_name", "name"]:
			if not candidate_dict.has(key):
				continue
			var rendered := _stringify_ship_class_value(candidate_dict.get(key, ""))
			if rendered.is_empty():
				continue
			parts.append("%s=%s" % [key, rendered])
	if parts.is_empty():
		return ""
	return ", ".join(parts)


func get_ship_definition(class_id: String, ship_class_name: String = "") -> Dictionary:
	var resolved_class_id: String = resolve_ship_class_id(class_id, ship_class_name)
	if resolved_class_id.is_empty():
		return {}
	if _ship_data_by_id.has(resolved_class_id):
		return _ship_data_by_id[resolved_class_id]
	var aliased_id: String = _ship_data_aliases.get(resolved_class_id, "")
	if not aliased_id.is_empty() and _ship_data_by_id.has(aliased_id):
		return _ship_data_by_id[aliased_id]
	return {}


func get_ship_scale(class_id: String, ship_class_name: String = "") -> float:
	var ship_definition: Dictionary = get_ship_definition(class_id, ship_class_name)
	return float(ship_definition.get("scale", 1.0))


func get_ship_world_span(class_id: String, ship_class_name: String = "") -> float:
	var scale := int(roundi(get_ship_scale(class_id, ship_class_name)))
	return float(SHIP_WORLD_SPAN_BY_SCALE.get(scale, SHIP_WORLD_SPAN_BY_SCALE[1]))


func get_ship_scene(class_id: String, ship_class_name: String = "") -> PackedScene:
	var resolved_class_id := resolve_ship_class_id(class_id, ship_class_name)
	if resolved_class_id.is_empty():
		return null
	if _ship_scenes.has(resolved_class_id):
		return _ship_scenes[resolved_class_id]

	var model_id: String = _ship_scene_aliases.get(resolved_class_id, resolved_class_id)
	var path: String = "res://assets/ships/" + model_id + ".glb"
	if ResourceLoader.exists(path):
		var scene: PackedScene = load(path) as PackedScene
		_ship_scenes[resolved_class_id] = scene
		return scene

	return null


func get_placeholder_mesh() -> BoxMesh:
	return _placeholder_mesh


func _load_ship_data() -> void:
	_ship_data_by_id.clear()
	if not ResourceLoader.exists(SHIP_DATA_PATH):
		return
	var file := FileAccess.open(SHIP_DATA_PATH, FileAccess.READ)
	if file == null:
		return
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	if not (parsed is Dictionary):
		return
	var ship_entries = parsed.get("ships", [])
	if not (ship_entries is Array):
		return
	for ship_entry_variant in ship_entries:
		if not (ship_entry_variant is Dictionary):
			continue
		var ship_entry := ship_entry_variant as Dictionary
		var ship_id: String = ship_entry.get("id", "")
		if ship_id.is_empty():
			continue
		_ship_data_by_id[ship_id] = ship_entry


func _ship_data_candidates(ship_data: Dictionary) -> Array[Dictionary]:
	var candidates: Array[Dictionary] = [ship_data]
	for key in ["ship", "active_ship", "player_ship"]:
		var nested: Variant = ship_data.get(key, null)
		if nested is Dictionary:
			candidates.append(nested)
	return candidates


func _first_present_value(data: Dictionary, keys: Array[String]):
	for key in keys:
		if data.has(key):
			return data.get(key)
	return null


func _stringify_ship_class_value(value) -> String:
	if value == null:
		return ""
	if value is Dictionary:
		var dict_value := value as Dictionary
		for key in ["class_id", "ship_class_id", "ship_class", "id", "name"]:
			var nested_value: Variant = dict_value.get(key, "")
			var rendered := _stringify_ship_class_value(nested_value)
			if not rendered.is_empty():
				return rendered
		return ""
	return String(value)
