extends Node3D

## Renders concentric 3D ring meshes on the ground during combat to visualize
## battle zones. Zone 1 is innermost, zone 5 is outermost. The ring matching
## the player's current zone pulses brighter.

const ZONE_COUNT := 5
const ZONE_RADII: Array[float] = [3.0, 6.0, 9.0, 12.0, 15.0]
const ZONE_COLORS: Array[Color] = [
	Color(1.0, 0.2, 0.2),   # Zone 1 — red
	Color(1.0, 0.6, 0.1),   # Zone 2 — orange
	Color(1.0, 1.0, 0.2),   # Zone 3 — yellow
	Color(0.2, 1.0, 0.3),   # Zone 4 — green
	Color(0.3, 0.5, 1.0),   # Zone 5 — blue
]
const TUBE_RADIUS := 0.04
const BASE_ALPHA := 0.3
const HIGHLIGHT_ALPHA := 0.7
const HIGHLIGHT_EMISSION_ENERGY := 3.0
const BASE_EMISSION_ENERGY := 1.0
const FADE_IN_DURATION := 0.5
const FADE_OUT_DURATION := 0.4
const PULSE_DURATION := 1.2

var _rings: Array[MeshInstance3D] = []
var _materials: Array[StandardMaterial3D] = []
var _fade_tween: Tween
var _pulse_tween: Tween
var _highlighted_zone: int = -1


func _ready() -> void:
	visible = false
	StateManager.combat_started.connect(_on_combat_started)
	StateManager.combat_ended.connect(_on_combat_ended)
	StateManager.battle_updated.connect(_on_battle_updated)

	# If we load into an already-active battle, show rings immediately
	if StateManager.in_combat:
		_create_rings()
		_snap_to_player()
		_update_highlight()
		visible = true
		for mat in _materials:
			mat.albedo_color.a = BASE_ALPHA


func _on_combat_started() -> void:
	_create_rings()
	_snap_to_player()
	_update_highlight()
	visible = true
	_fade_in()


func _on_combat_ended() -> void:
	_fade_out()


func _on_battle_updated() -> void:
	if not StateManager.in_combat:
		return
	_snap_to_player()
	_update_highlight()


func _create_rings() -> void:
	_clear_rings()
	for i in ZONE_COUNT:
		var mat := StandardMaterial3D.new()
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = Color(ZONE_COLORS[i].r, ZONE_COLORS[i].g, ZONE_COLORS[i].b, 0.0)
		mat.emission_enabled = true
		mat.emission = ZONE_COLORS[i]
		mat.emission_energy_multiplier = BASE_EMISSION_ENERGY
		mat.no_depth_test = true

		var torus := TorusMesh.new()
		torus.inner_radius = TUBE_RADIUS
		torus.outer_radius = ZONE_RADII[i]
		torus.rings = 48
		torus.ring_segments = 12

		var ring := MeshInstance3D.new()
		ring.name = "Zone%d" % (i + 1)
		ring.mesh = torus
		ring.material_override = mat
		# TorusMesh stands upright by default; rotate to lay flat on XZ plane
		ring.rotation_degrees.x = -90.0

		add_child(ring)
		_rings.append(ring)
		_materials.append(mat)


func _clear_rings() -> void:
	if _pulse_tween and _pulse_tween.is_valid():
		_pulse_tween.kill()
	_pulse_tween = null
	_highlighted_zone = -1

	for ring in _rings:
		ring.queue_free()
	_rings.clear()
	_materials.clear()


func _snap_to_player() -> void:
	var pos: Variant = _find_player_ship_position()
	if pos != null:
		global_position = Vector3(pos.x, 0.0, pos.z)


func _update_highlight() -> void:
	var participant := StateManager.get_my_participant()
	var zone_value = participant.get("zone", "")
	var zone_num: int = -1

	if zone_value is int:
		zone_num = zone_value
	elif zone_value is float:
		zone_num = int(zone_value)
	elif zone_value is String and not zone_value.is_empty():
		zone_num = zone_value.to_int()

	if zone_num == _highlighted_zone:
		return

	_highlighted_zone = zone_num

	# Reset all rings to base appearance
	for i in _materials.size():
		var mat := _materials[i]
		mat.emission_energy_multiplier = BASE_EMISSION_ENERGY
		if visible and mat.albedo_color.a > 0.0:
			mat.albedo_color.a = BASE_ALPHA

	# Start pulse on the active zone
	if _pulse_tween and _pulse_tween.is_valid():
		_pulse_tween.kill()
	_pulse_tween = null

	if zone_num >= 1 and zone_num <= ZONE_COUNT:
		var idx := zone_num - 1
		var mat := _materials[idx]
		mat.albedo_color.a = HIGHLIGHT_ALPHA
		mat.emission_energy_multiplier = HIGHLIGHT_EMISSION_ENERGY
		_start_pulse(idx)


func _start_pulse(idx: int) -> void:
	if _pulse_tween and _pulse_tween.is_valid():
		_pulse_tween.kill()

	var mat := _materials[idx]
	_pulse_tween = create_tween().set_loops()
	_pulse_tween.tween_property(mat, "albedo_color:a", BASE_ALPHA + 0.1, PULSE_DURATION * 0.5)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_pulse_tween.tween_property(mat, "albedo_color:a", HIGHLIGHT_ALPHA, PULSE_DURATION * 0.5)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _fade_in() -> void:
	if _fade_tween and _fade_tween.is_valid():
		_fade_tween.kill()
	_fade_tween = create_tween()
	for i in _materials.size():
		var mat := _materials[i]
		mat.albedo_color.a = 0.0
		var target_alpha := HIGHLIGHT_ALPHA if (i + 1) == _highlighted_zone else BASE_ALPHA
		_fade_tween.parallel().tween_property(mat, "albedo_color:a", target_alpha, FADE_IN_DURATION)


func _fade_out() -> void:
	if _pulse_tween and _pulse_tween.is_valid():
		_pulse_tween.kill()
	_pulse_tween = null

	if _fade_tween and _fade_tween.is_valid():
		_fade_tween.kill()
	_fade_tween = create_tween()
	for mat in _materials:
		_fade_tween.parallel().tween_property(mat, "albedo_color:a", 0.0, FADE_OUT_DURATION)
	_fade_tween.tween_callback(_on_fade_out_complete)


func _on_fade_out_complete() -> void:
	visible = false
	_clear_rings()


func _find_player_ship_position() -> Variant:
	var parent := get_parent()
	if not parent:
		return null
	for child in parent.get_children():
		if child.has_method("move_to") and child.get("is_player_ship") == true:
			return child.global_position
	return null
