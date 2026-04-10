extends Node

const AUTH_SCENE := preload("res://scenes/ui/auth.tscn")
const PLAYER_SELECT_SCENE := preload("res://scenes/ui/player_select.tscn")
const CREATE_PLAYER_SCENE := preload("res://scenes/ui/create_player.tscn")
const GAME_SCENE := preload("res://scenes/game/game.tscn")

var _current: Node = null


func _ready() -> void:
	_apply_saved_display_settings()
	NetworkManager.authenticated.connect(_on_authenticated)
	NetworkManager.session_expired.connect(_on_session_expired)

	# Try restoring saved auth; if valid, go to player select
	NetworkManager.try_restore_auth(
		func(players: Array) -> void:
			_show_player_select(players),
		func() -> void:
			_switch_to(AUTH_SCENE.instantiate())
	)


func _on_authenticated(initial_state: Dictionary) -> void:
	StateManager.set_initial_state(initial_state)
	_switch_to(GAME_SCENE.instantiate())


func _on_session_expired() -> void:
	NetworkManager._delete_saved_auth()
	NetworkManager.api_key = ""
	_switch_to(AUTH_SCENE.instantiate())


func _show_player_select(players: Array) -> void:
	var scene := PLAYER_SELECT_SCENE.instantiate()
	_switch_to(scene)
	scene.set_players(players)


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

	# Wire scene navigation
	if _current.has_signal("show_player_select"):
		_current.show_player_select.connect(func(players: Array) -> void:
			_show_player_select(players)
		)
	if _current.has_signal("show_create_player"):
		_current.show_create_player.connect(func() -> void:
			_switch_to(CREATE_PLAYER_SCENE.instantiate())
		)
	if _current.has_signal("show_auth"):
		_current.show_auth.connect(func() -> void:
			_switch_to(AUTH_SCENE.instantiate())
		)
