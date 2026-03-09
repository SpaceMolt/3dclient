extends MeshInstance3D

## Visual mining beam that stretches from the player ship to the current POI
## when mining is active. Listens to StateManager mining signals.

const BEAM_RADIUS := 0.05
const BEAM_COLOR := Color(0.7, 1.0, 0.3, 0.6)
const EMISSION_COLOR := Color(0.6, 1.0, 0.2)
const EMISSION_ENERGY := 2.5
const FADE_IN_DURATION := 0.3
const FADE_OUT_DURATION := 0.2

var _material: StandardMaterial3D
var _tween: Tween


func _ready() -> void:
	visible = false
	_setup_material()
	_setup_mesh()
	StateManager.mining_started.connect(_on_mining_started)
	StateManager.mining_ended.connect(_on_mining_ended)


func _setup_material() -> void:
	_material = StandardMaterial3D.new()
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.albedo_color = Color(BEAM_COLOR.r, BEAM_COLOR.g, BEAM_COLOR.b, 0.0)
	_material.emission_enabled = true
	_material.emission = EMISSION_COLOR
	_material.emission_energy_multiplier = EMISSION_ENERGY
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.no_depth_test = true


func _setup_mesh() -> void:
	var cyl := CylinderMesh.new()
	cyl.top_radius = BEAM_RADIUS
	cyl.bottom_radius = BEAM_RADIUS
	cyl.height = 1.0  # Will be scaled dynamically
	cyl.radial_segments = 8
	mesh = cyl
	material_override = _material


func _on_mining_started() -> void:
	var from: Variant = _find_player_ship_position()
	var to: Variant = _find_current_poi_position()
	if from == null or to == null:
		return

	_orient_beam(from, to)
	visible = true
	_fade_in()


func _on_mining_ended() -> void:
	_fade_out()


func _orient_beam(from: Vector3, to: Vector3) -> void:
	var midpoint := (from + to) * 0.5
	var direction := to - from
	var length := direction.length()

	if length < 0.001:
		return

	# Position at midpoint between ship and POI
	global_position = midpoint

	# CylinderMesh is Y-axis aligned by default. We need to rotate it to
	# point along the direction vector.
	var up := Vector3.UP
	var dir_norm := direction.normalized()

	# If the beam is nearly vertical, use a different reference axis
	if absf(dir_norm.dot(up)) > 0.99:
		up = Vector3.FORWARD

	look_at(global_position + dir_norm, up)
	# After look_at, the -Z axis points along dir_norm.
	# Rotate 90 degrees around X so the cylinder's Y axis aligns with -Z.
	rotate_object_local(Vector3.RIGHT, deg_to_rad(90.0))

	# Scale the cylinder height to match the distance
	var cyl: CylinderMesh = mesh as CylinderMesh
	if cyl:
		cyl.height = length


func _fade_in() -> void:
	if _tween and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_material.albedo_color.a = 0.0
	_tween.tween_property(_material, "albedo_color:a", BEAM_COLOR.a, FADE_IN_DURATION)


func _fade_out() -> void:
	if _tween and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(_material, "albedo_color:a", 0.0, FADE_OUT_DURATION)
	_tween.tween_callback(func(): visible = false)


func _find_player_ship_position() -> Variant:
	var parent := get_parent()
	if not parent:
		return null
	for child in parent.get_children():
		if child.has_method("move_to") and child.get("is_player_ship") == true:
			return child.global_position
	return null


func _find_current_poi_position() -> Variant:
	var poi_id: String = StateManager.location.get("poi_id", "")
	if poi_id.is_empty():
		return null

	var parent := get_parent()
	if not parent:
		return null

	# Look through sibling POI marker nodes
	for child in parent.get_children():
		if child.get("poi_id") == poi_id:
			return child.global_position

	return null
