extends Node

const LOGIN_SCENE := preload("res://scenes/ui/login.tscn")
const REGISTER_SCENE := preload("res://scenes/ui/register.tscn")
const GAME_SCENE := preload("res://scenes/game/game.tscn")

var _current: Node = null


func _ready() -> void:
	_apply_saved_display_settings()
	NetworkManager.authenticated.connect(_on_authenticated)
	NetworkManager.session_expired.connect(_on_session_expired)

	# Always show login screen first; auto-login replaces it on success
	_switch_to(LOGIN_SCENE.instantiate())

	if NetworkManager.has_saved_session():
		NetworkManager.try_restore_session(
			func(content: Dictionary) -> void:
				_on_authenticated(content),
			func() -> void:
				pass  # Already showing login screen
		)


func _on_authenticated(initial_state: Dictionary) -> void:
	StateManager.set_initial_state(initial_state)
	_switch_to(GAME_SCENE.instantiate())


func _on_session_expired() -> void:
	NetworkManager._delete_saved_session()
	_switch_to(LOGIN_SCENE.instantiate())




func _apply_saved_display_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load("user://settings.cfg") != OK:
		return  # No saved settings; project.godot defaults (fullscreen windowed) apply
	var fullscreen: bool = cfg.get_value("display", "fullscreen", true)
	if fullscreen:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	var vsync: bool = cfg.get_value("display", "vsync", true)
	if vsync:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
	else:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)


func _switch_to(node: Node) -> void:
	if _current:
		_current.queue_free()
	_current = node
	add_child(_current)

	# Wire login ↔ register navigation
	if _current.has_signal("show_register"):
		_current.show_register.connect(func():
			_switch_to(REGISTER_SCENE.instantiate())
		)
	if _current.has_signal("show_login"):
		_current.show_login.connect(func():
			_switch_to(LOGIN_SCENE.instantiate())
		)
