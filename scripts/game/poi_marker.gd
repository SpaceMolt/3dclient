extends Node3D

var poi_id: String = ""
var poi_name: String = ""
var poi_type: String = ""

@onready var name_label: Label3D = $NameLabel
@onready var mesh_instance: MeshInstance3D = $MeshInstance3D


func _ready() -> void:
	name_label.text = poi_name
	_apply_appearance()


func setup(id: String, pname: String, ptype: String, pos: Vector3) -> void:
	poi_id = id
	poi_name = pname
	poi_type = ptype
	global_position = pos


func _apply_appearance() -> void:
	var mat := StandardMaterial3D.new()
	var mesh: Mesh

	match poi_type:
		"station":
			mesh = BoxMesh.new()
			mesh.size = Vector3(2.0, 2.0, 2.0)
			mat.albedo_color = Color(0.2, 0.6, 1.0, 0.8)
		"asteroid", "asteroid_field":
			mesh = SphereMesh.new()
			mesh.radius = 0.8
			mesh.height = 1.6
			mat.albedo_color = Color(0.6, 0.5, 0.3, 0.8)
		"wormhole", "jump_gate":
			mesh = TorusMesh.new()
			mesh.inner_radius = 0.6
			mesh.outer_radius = 1.2
			mat.albedo_color = Color(0.8, 0.3, 1.0, 0.8)
			mat.emission_enabled = true
			mat.emission = Color(0.5, 0.1, 0.8)
			mat.emission_energy_multiplier = 2.0
		_:
			mesh = CylinderMesh.new()
			mesh.top_radius = 0.5
			mesh.bottom_radius = 0.5
			mesh.height = 1.5
			mat.albedo_color = Color(0.5, 0.5, 0.5, 0.8)

	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh_instance.mesh = mesh
	mesh_instance.material_override = mat
