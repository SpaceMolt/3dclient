extends SceneTree
## Offline POI gallery: renders every POI type/class the marker knows how to build,
## one PNG each, without a server. Use it to iterate on looks quickly.
## Usage: bin/godot --windowed --resolution 960x540 -s scripts/tools/poi_gallery.gd
##        (make poi-gallery). Output: screenshots/poi_<type>_<class>.png

const SCREENSHOT_DIR := "res://screenshots"
const TEST_SCENE := "res://scenes/test/visual_test.tscn"
const POI_MARKER_SCENE := preload("res://scenes/game/poi_marker.tscn")
const FocusBubble := preload("res://scripts/game/focus_bubble.gd")
const WAIT_FRAMES := 12
const ENTRIES := [
	["station", ""], ["sun", "G2V"], ["sun", "B3V"], ["sun", "M3III"],
	["planet", "terran"], ["planet", "arid"], ["planet", "scorched"], ["planet", "ice_world"],
	["planet", "jovian"], ["planet", "oceanic"], ["moon", ""],
	["asteroid_belt", "metallic"], ["asteroid_belt", "icy"], ["asteroid_belt", "mixed"],
	["ice_field", "kuiper"], ["gas_cloud", "atmospheric"], ["nebula", ""],
	["relic", "megastructure"], ["relic", ""], ["wormhole", ""], ["jump_gate", ""],
]

var _scene: Node3D
var _camera: Camera3D
var _marker: Node3D = null
var _index := 0
var _frame := 0


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SCREENSHOT_DIR))
	_scene = (ResourceLoader.load(TEST_SCENE) as PackedScene).instantiate()
	root.add_child(_scene)
	_camera = _scene.find_child("Camera3D", true, false) as Camera3D
	_camera.current = true
	_camera.far = 100000.0
	print("POI gallery: %d entries" % ENTRIES.size())


func _process(_delta: float) -> bool:
	if _index >= ENTRIES.size():
		print("Gallery saved to %s" % ProjectSettings.globalize_path(SCREENSHOT_DIR))
		quit()
		return true
	var entry: Array = ENTRIES[_index]
	if _frame == 0:
		if _marker:
			_marker.free()
		_marker = POI_MARKER_SCENE.instantiate() as Node3D
		_scene.add_child(_marker)
		_marker.setup("gallery", "%s %s" % [entry[0], entry[1]], entry[0], Vector3.ZERO, entry[1])
		# Frame the body: camera at ~2.6 radii, slightly above, looking at the center
		var r: float = FocusBubble.poi_radius(entry[0], entry[1])
		_camera.global_position = Vector3(r * 1.6, r * 1.1, r * 1.9)
		_camera.look_at(Vector3.ZERO, Vector3.UP)
	_frame += 1
	if _frame < WAIT_FRAMES:
		return false
	var img := root.get_viewport().get_texture().get_image()
	var name := "poi_%s_%s" % [entry[0], entry[1] if not entry[1].is_empty() else "default"]
	var path := ProjectSettings.globalize_path("%s/%s.png" % [SCREENSHOT_DIR, name])
	print("  [%d/%d] %s -> %s" % [_index + 1, ENTRIES.size(), name, "ok" if img.save_png(path) == OK else "SAVE FAILED"])
	_index += 1
	_frame = 0
	return false
