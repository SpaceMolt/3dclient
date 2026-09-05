extends Camera3D

## Camera for the stable world-space system view.
##
## Close zoom stays readable around the player ship and the local orbiting body.
## The max zoom and far clip are large enough to inspect a much wider system.

const ZOOM_MIN := 30.0
const ZOOM_MAX := 300000.0
const ZOOM_SPEED := 0.15
const ZOOM_SMOOTH := 12.0
const PAN_SPEED := 0.05
const ROTATE_SPEED := 0.005
const PITCH_SPEED := 0.003
const FOLLOW_SMOOTH := 12.0
const COMBAT_ZOOM := 45.0
const COMBAT_ZOOM_DURATION := 1.0

const DEFAULT_ORBIT := 0.0
const DEFAULT_TILT := 0.85  # low angle so the docked station towers behind the ship
const MIN_TILT := 0.15      # nearly top-down
const MAX_TILT := 1.2       # low angle

const DEFAULT_ZOOM := 70.0  # close enough that the player ship reads as a ship
const FAR_CLIP_DISTANCE := 5000000.0

var _target: Node3D = null
var _following: bool = true
var _panning: bool = false
var _rotating: bool = false
var _zoom: float = DEFAULT_ZOOM
var _target_zoom: float = DEFAULT_ZOOM
var _orbit: float = DEFAULT_ORBIT   # horizontal orbit (radians around Y)
var _tilt: float = DEFAULT_TILT     # vertical tilt (higher = more horizontal)
var _pre_combat_zoom: float = 0.0
var _in_combat_zoom: bool = false
var _zoom_tween: Tween = null
var _right_press_pos: Vector2 = Vector2.ZERO
var _right_was_drag: bool = false
var _rotate_skip_first: bool = false  # skip first motion event after right-click
var _first_follow: bool = true


func _ready() -> void:
	StateManager.combat_started.connect(_on_combat_started)
	StateManager.combat_ended.connect(_on_combat_ended)
	# A larger far clip is required now that all POIs use one stable world scale.
	near = 1.0
	far = FAR_CLIP_DISTANCE


func follow(node: Node3D) -> void:
	_target = node
	_following = true
	if _first_follow:
		_first_follow = false
		# Snap camera to correct position immediately on first follow
		_update_camera_position(1.0)


func stop_following() -> void:
	_following = false


## Swings the orbit so the camera looks along direction (in the XZ plane), e.g. toward the star.
func face_direction(direction: Vector3) -> void:
	var flat := Vector2(direction.x, direction.z)
	if flat.length_squared() < 0.0001:
		return
	# The camera sits at (sin(orbit), cos(orbit)) * horiz from the target and looks back at it.
	_orbit = atan2(-flat.x, -flat.y)
	if _following and _target:
		_update_camera_position(1.0)


func snap_to_target() -> void:
	if _target and _following:
		_update_camera_position(1.0)


func _process(delta: float) -> void:
	# Frame-rate-independent smoothing factor (can't exceed 1.0)
	var t := 1.0 - exp(-FOLLOW_SMOOTH * delta)

	# Smooth zoom
	if not is_equal_approx(_zoom, _target_zoom):
		_zoom = lerpf(_zoom, _target_zoom, t)
		if absf(_zoom - _target_zoom) < 0.01:
			_zoom = _target_zoom

	if _following and _target:
		var follow_t := t
		if _rotating or StateManager.is_traveling:
			follow_t = 1.0
		_update_camera_position(follow_t)
	elif not _following:
		# Free camera — just apply zoom height
		var zt := 1.0 - exp(-ZOOM_SMOOTH * delta)
		global_position.y = lerpf(global_position.y, _zoom, zt)


func _update_camera_position(t: float) -> void:
	# Spherical coordinates: zoom = radius, tilt = polar angle from vertical,
	# orbit = azimuth. Camera stays at constant distance from target while
	# tilting along an arc.
	var height := cos(_tilt) * _zoom
	var horiz := sin(_tilt) * _zoom
	var target_pos := Vector3(
		_target.global_position.x + sin(_orbit) * horiz,
		_target.global_position.y + height,
		_target.global_position.z + cos(_orbit) * horiz
	)
	global_position = global_position.lerp(target_pos, t)
	look_at(_target.global_position, Vector3.UP)


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_target_zoom = clampf(_target_zoom - _target_zoom * ZOOM_SPEED, ZOOM_MIN, ZOOM_MAX)
			_kill_zoom_tween()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_target_zoom = clampf(_target_zoom + _target_zoom * ZOOM_SPEED, ZOOM_MIN, ZOOM_MAX)
			_kill_zoom_tween()
		elif event.button_index == MOUSE_BUTTON_MIDDLE:
			_panning = event.pressed
			if event.pressed:
				stop_following()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			if event.pressed:
				_right_press_pos = event.position
				_right_was_drag = false
				_rotating = true
				_rotate_skip_first = true
			else:
				_rotating = false
				if event.double_click and _target:
					_following = true

	elif event is InputEventMouseMotion:
		if _panning:
			var scale_factor := _zoom / 100.0
			var pan_delta: Vector2 = event.relative * PAN_SPEED * scale_factor
			var right := global_transform.basis.x.normalized()
			var forward := Vector3(-right.z, 0.0, right.x).normalized()
			global_position += right * -pan_delta.x + forward * -pan_delta.y
		elif _rotating:
			# Skip the first motion event — its relative is from the previous
			# mouse position, not from where the right-click started.
			if _rotate_skip_first:
				_rotate_skip_first = false
				return
			var drag_dist: float = event.position.distance_to(_right_press_pos)
			if drag_dist > 4.0:
				_right_was_drag = true
			_orbit -= event.relative.x * ROTATE_SPEED
			# Dragging down lowers the camera toward the horizon (more tilt); up goes top-down.
			_tilt = clampf(_tilt + event.relative.y * PITCH_SPEED, MIN_TILT, MAX_TILT)
			if _following and _target:
				_update_camera_position(1.0)


func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.is_echo()):
		return
	match (event as InputEventKey).keycode:
		KEY_HOME:
			if _target:
				_following = true
				_orbit = DEFAULT_ORBIT
				_tilt = DEFAULT_TILT
				_target_zoom = DEFAULT_ZOOM
				get_viewport().set_input_as_handled()


func _on_combat_started() -> void:
	_pre_combat_zoom = _target_zoom
	_in_combat_zoom = true
	if _target:
		_following = true
	_tween_zoom_to(COMBAT_ZOOM)


func _on_combat_ended() -> void:
	_in_combat_zoom = false
	_tween_zoom_to(_pre_combat_zoom)


func _tween_zoom_to(target: float) -> void:
	_kill_zoom_tween()
	_zoom_tween = create_tween()
	_zoom_tween.tween_method(func(v: float):
		_zoom = v
		_target_zoom = v
	, _zoom, target, COMBAT_ZOOM_DURATION) \
		.set_ease(Tween.EASE_IN_OUT) \
		.set_trans(Tween.TRANS_CUBIC)


func _kill_zoom_tween() -> void:
	if _zoom_tween and _zoom_tween.is_valid():
		_zoom_tween.kill()
	_zoom_tween = null
