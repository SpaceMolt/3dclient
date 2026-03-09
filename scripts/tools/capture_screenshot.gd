extends SceneTree
## Visual testing tool — captures screenshots using the actual game environment.
## Usage: ./bin/godot --windowed --resolution 800x600 -s scripts/tools/capture_screenshot.gd
##
## Uses scenes/test/visual_test.tscn which has the real sky shader, lighting,
## and environment — same as game_view.tscn but without autoload-dependent scripts.
## Screenshots saved to res://screenshots/

const SCREENSHOT_DIR := "res://screenshots"
const TEST_SCENE := "res://scenes/test/visual_test.tscn"
const WAIT_FRAMES := 15

var _frame_count := 0
var _captures: Array[Dictionary] = []
var _capture_index := 0
var _camera: Camera3D = null
var _target: Node3D = null
var _scene: Node3D = null


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SCREENSHOT_DIR))

	# Load the visual test scene (real sky, lighting, environment)
	var scene_res := ResourceLoader.load(TEST_SCENE) as PackedScene
	_scene = scene_res.instantiate()
	root.add_child(_scene)

	_camera = _scene.find_child("Camera3D", true, false) as Camera3D
	_camera.current = true

	# Target at origin
	_target = Node3D.new()
	_target.name = "Target"
	_scene.add_child(_target)
	_target.global_position = Vector3.ZERO

	# Reference marker so we have something visible
	_add_marker(Vector3.ZERO, Color(0.4, 0.8, 1.0), 0.5)

	_define_captures()
	print("Screenshot capture: %d captures using %s" % [_captures.size(), TEST_SCENE])


func _add_marker(pos: Vector3, color: Color, radius: float) -> void:
	var mesh_inst := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 2.0
	sphere.material = mat
	mesh_inst.mesh = sphere
	mesh_inst.global_position = pos
	_scene.add_child(mesh_inst)


func _define_captures() -> void:
	_captures = [
		{"name": "01_default", "orbit": 0.0, "tilt": 0.4, "zoom": 20.0},
		{"name": "02_orbit_90deg", "orbit": PI / 2, "tilt": 0.4, "zoom": 20.0},
		{"name": "03_orbit_180deg", "orbit": PI, "tilt": 0.4, "zoom": 20.0},
		{"name": "04_orbit_270deg", "orbit": 3 * PI / 2, "tilt": 0.4, "zoom": 20.0},
		{"name": "05_tilt_low_angle", "orbit": 0.0, "tilt": 1.0, "zoom": 20.0},
		{"name": "06_tilt_topdown", "orbit": 0.0, "tilt": 0.15, "zoom": 20.0},
		{"name": "07_zoomed_in", "orbit": 0.0, "tilt": 0.4, "zoom": 8.0},
		{"name": "08_zoomed_out", "orbit": 0.0, "tilt": 0.4, "zoom": 60.0},
		# Sky-focused: near-horizontal views in 4 directions
		{"name": "09_sky_north", "orbit": 0.0, "tilt": 1.3, "zoom": 5.0},
		{"name": "10_sky_east", "orbit": PI / 2, "tilt": 1.3, "zoom": 5.0},
		{"name": "11_sky_south", "orbit": PI, "tilt": 1.3, "zoom": 5.0},
		{"name": "12_sky_west", "orbit": 3 * PI / 2, "tilt": 1.3, "zoom": 5.0},
		# Straight down — check for pole artifacts
		{"name": "13_looking_down", "orbit": 0.0, "tilt": 0.05, "zoom": 10.0},
	]


func _apply_camera_state(orbit: float, tilt: float, zoom: float) -> void:
	var target_pos := _target.global_position
	var height := cos(tilt) * zoom
	var horiz := sin(tilt) * zoom
	_camera.global_position = Vector3(
		target_pos.x + sin(orbit) * horiz,
		target_pos.y + height,
		target_pos.z + cos(orbit) * horiz
	)
	_camera.look_at(_target.global_position, Vector3.UP)


func _process(delta: float) -> bool:
	_frame_count += 1

	if _capture_index >= _captures.size():
		print("\nAll %d captures saved to: %s" % [_captures.size(), ProjectSettings.globalize_path(SCREENSHOT_DIR)])
		quit()
		return true

	var cap: Dictionary = _captures[_capture_index]

	if _frame_count == 1:
		_apply_camera_state(cap["orbit"], cap["tilt"], cap["zoom"])
		print("  [%d/%d] %s" % [_capture_index + 1, _captures.size(), cap["name"]])

	if _frame_count < WAIT_FRAMES:
		return false

	if _frame_count == WAIT_FRAMES:
		var pos := _camera.global_position
		var fwd := -_camera.global_transform.basis.z
		var angle_from_down := rad_to_deg(acos(clampf(-fwd.y, -1.0, 1.0)))
		print("    pos=(%.2f, %.2f, %.2f) fwd=(%.3f, %.3f, %.3f) angle_from_down=%.1f°" % [
			pos.x, pos.y, pos.z, fwd.x, fwd.y, fwd.z, angle_from_down
		])
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
