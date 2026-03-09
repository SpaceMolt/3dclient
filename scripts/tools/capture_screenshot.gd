extends SceneTree
## Visual testing tool — captures screenshots of the focus bubble scale system.
## Usage: ./bin/godot --windowed --resolution 800x600 -s scripts/tools/capture_screenshot.gd
##
## Creates a mini-scene with actual POI markers and ship at the correct scale
## to validate the focus bubble architecture visually.

const SCREENSHOT_DIR := "res://screenshots"
const TEST_SCENE := "res://scenes/test/visual_test.tscn"
const WAIT_FRAMES := 15
const POI_MARKER_SCENE := preload("res://scenes/game/poi_marker.tscn")
const FocusBubble := preload("res://scripts/game/focus_bubble.gd")

var _frame_count := 0
var _captures: Array[Dictionary] = []
var _capture_index := 0
var _camera: Camera3D = null
var _target: Node3D = null
var _scene: Node3D = null


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SCREENSHOT_DIR))

	var scene_res := ResourceLoader.load(TEST_SCENE) as PackedScene
	_scene = scene_res.instantiate()
	root.add_child(_scene)

	_camera = _scene.find_child("Camera3D", true, false) as Camera3D
	_camera.current = true
	_camera.far = 12000.0

	# Target at origin (where the player ship would be)
	_target = Node3D.new()
	_target.name = "Target"
	_scene.add_child(_target)
	_target.global_position = Vector3.ZERO

	# Player ship marker at origin
	_add_ship_marker(Vector3.ZERO)

	# Create focused POI — a terran planet below the ship
	var planet := POI_MARKER_SCENE.instantiate() as Node3D
	var planet_offset: Vector3 = FocusBubble.focused_poi_offset("planet", "terran")
	_scene.add_child(planet)
	planet.setup("p1", "Earth", "planet", planet_offset, "terran")

	# Create some impostors at compressed distances
	var player_au := Vector2(1.0, 2.0)

	# Mars impostor
	var mars := POI_MARKER_SCENE.instantiate() as Node3D
	var mars_pos: Vector3 = FocusBubble.impostor_position(player_au, Vector2(5.0, 8.0))
	_scene.add_child(mars)
	mars.setup("p2", "Mars", "planet", mars_pos, "arid")
	mars.set_mode(true)

	# Station impostor
	var station := POI_MARKER_SCENE.instantiate() as Node3D
	var station_pos: Vector3 = FocusBubble.impostor_position(player_au, Vector2(-2.0, 0.5))
	_scene.add_child(station)
	station.setup("s1", "Alpha Station", "station", station_pos)
	station.set_mode(true)

	# Star impostor
	var star := POI_MARKER_SCENE.instantiate() as Node3D
	var star_pos: Vector3 = FocusBubble.impostor_position(player_au, Vector2(0.0, 0.0))
	_scene.add_child(star)
	star.setup("star1", "Sol", "sun", star_pos, "G")
	star.set_mode(true)

	# Also create a focused station scene for comparison
	var station_full := POI_MARKER_SCENE.instantiate() as Node3D
	var station_offset: Vector3 = FocusBubble.focused_poi_offset("station", "")
	# Put it offset to the side so we can capture separately
	_scene.add_child(station_full)
	station_full.setup("s2", "Beta Hub", "station", station_offset + Vector3(500, 0, 0))

	_define_captures()
	print("Screenshot capture: %d captures using focus bubble scale" % [_captures.size()])


func _add_ship_marker(pos: Vector3) -> void:
	var mesh_inst := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.6, 0.3, 1.2)  # Small ship at scale 1
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.4, 0.8, 1.0)
	mat.emission_enabled = true
	mat.emission = Color(0.2, 0.5, 0.8)
	mat.emission_energy_multiplier = 1.5
	box.material = mat
	mesh_inst.mesh = box
	mesh_inst.global_position = pos
	_scene.add_child(mesh_inst)

	# Engine glow
	var light := OmniLight3D.new()
	light.light_color = Color(0.3, 0.7, 1.0)
	light.light_energy = 2.0
	light.omni_range = 3.0
	light.position = Vector3(0, 0, 0.6)
	mesh_inst.add_child(light)


func _define_captures() -> void:
	_captures = [
		# Ship + planet at cinematic scale — default view
		{"name": "01_planet_orbit_default", "orbit": 0.0, "tilt": 0.4, "zoom": 150.0,
			"target": Vector3.ZERO},
		# Close up on ship near planet surface
		{"name": "02_planet_orbit_close", "orbit": 0.3, "tilt": 0.6, "zoom": 20.0,
			"target": Vector3.ZERO},
		# Pull back to see planet size
		{"name": "03_planet_wide", "orbit": 0.0, "tilt": 0.3, "zoom": 600.0,
			"target": Vector3(0, -150, 0)},
		# Low angle showing planet horizon
		{"name": "04_planet_horizon", "orbit": 1.0, "tilt": 1.0, "zoom": 80.0,
			"target": Vector3.ZERO},
		# Zoomed way out to see impostors
		{"name": "05_system_overview", "orbit": 0.0, "tilt": 0.2, "zoom": 4000.0,
			"target": Vector3.ZERO},
		# Looking toward the star impostor
		{"name": "06_toward_star", "orbit": 2.5, "tilt": 0.5, "zoom": 2000.0,
			"target": Vector3.ZERO},
		# Top-down system view
		{"name": "07_topdown_system", "orbit": 0.0, "tilt": 0.05, "zoom": 6000.0,
			"target": Vector3.ZERO},
		# Station focused (offset scene)
		{"name": "08_station_close", "orbit": 0.2, "tilt": 0.5, "zoom": 80.0,
			"target": Vector3(500, 0, 0)},
	]


func _apply_camera_state(orbit: float, tilt: float, zoom: float, target_pos: Vector3) -> void:
	var height := cos(tilt) * zoom
	var horiz := sin(tilt) * zoom
	_camera.global_position = Vector3(
		target_pos.x + sin(orbit) * horiz,
		target_pos.y + height,
		target_pos.z + cos(orbit) * horiz
	)
	_camera.look_at(target_pos, Vector3.UP)


func _process(_delta: float) -> bool:
	_frame_count += 1

	if _capture_index >= _captures.size():
		print("\nAll %d captures saved to: %s" % [_captures.size(), ProjectSettings.globalize_path(SCREENSHOT_DIR)])
		quit()
		return true

	var cap: Dictionary = _captures[_capture_index]

	if _frame_count == 1:
		var target_pos: Vector3 = cap.get("target", Vector3.ZERO)
		_apply_camera_state(cap["orbit"], cap["tilt"], cap["zoom"], target_pos)
		print("  [%d/%d] %s (zoom=%.0f)" % [_capture_index + 1, _captures.size(), cap["name"], cap["zoom"]])

	if _frame_count < WAIT_FRAMES:
		return false

	if _frame_count == WAIT_FRAMES:
		_take_screenshot(cap["name"])
		_capture_index += 1
		_frame_count = 0

	return false


func _take_screenshot(capture_name: String) -> void:
	var img := root.get_viewport().get_texture().get_image()
	var path := "%s/%s.png" % [SCREENSHOT_DIR, capture_name]
	var global_path := ProjectSettings.globalize_path(path)
	var err := img.save_png(global_path)
	if err == OK:
		print("    -> %s (%dx%d)" % [global_path, img.get_width(), img.get_height()])
	else:
		print("    ERROR saving: %s (code %d)" % [global_path, err])
