extends Node

var _ship_scenes: Dictionary = {}
var _placeholder_mesh: BoxMesh


func _ready() -> void:
	_placeholder_mesh = BoxMesh.new()
	_placeholder_mesh.size = Vector3(1.5, 0.4, 2.5)


func get_ship_scene(class_id: String) -> PackedScene:
	if _ship_scenes.has(class_id):
		return _ship_scenes[class_id]

	var path := "res://assets/ships/" + class_id + ".glb"
	if ResourceLoader.exists(path):
		var scene := load(path) as PackedScene
		_ship_scenes[class_id] = scene
		return scene

	return null


func get_placeholder_mesh() -> BoxMesh:
	return _placeholder_mesh
