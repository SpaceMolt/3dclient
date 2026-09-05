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

	# Scripted dev runs log in from the environment (see scripts/tools/dev_run.sh):
	# SPACEMOLT_USERNAME + SPACEMOLT_PASSWORD log straight in; SPACEMOLT_API_KEY
	# opens the dashboard player list, and SPACEMOLT_PLAYER picks one by username.
	var dev_user := OS.get_environment("SPACEMOLT_USERNAME")
	var dev_pass := OS.get_environment("SPACEMOLT_PASSWORD")
	var dev_key := OS.get_environment("SPACEMOLT_API_KEY")
	var show_auth := func(_error: Dictionary = {}) -> void:
		_switch_to(AUTH_SCENE.instantiate())
	if not dev_user.is_empty() and not dev_pass.is_empty():
		NetworkManager.login_password(dev_user, dev_pass, show_auth)
		return
	if not dev_key.is_empty():
		NetworkManager.api_key = dev_key
		var dev_player := OS.get_environment("SPACEMOLT_PLAYER")
		NetworkManager.get_players(func(players: Array) -> void:
			for player in players:
				if player.get("username", "") == dev_player:
					NetworkManager.select_player(player.get("id", ""), func(_c: Dictionary) -> void: pass, show_auth)
					return
			_show_player_select(players)
		, show_auth)
		return

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
	NetworkManager.clear_auth()
	_switch_to(AUTH_SCENE.instantiate())


func _show_player_select(players: Array) -> void:
	var scene := PLAYER_SELECT_SCENE.instantiate()
	_switch_to(scene)
	scene.set_players(players)


func _apply_saved_display_settings() -> void:
	var cfg := ConfigFile.new()
	var has_config := cfg.load("user://settings.cfg") == OK
	if has_config:
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
	# HiDPI: default off for performance on retina displays
	var hidpi: bool = cfg.get_value("display", "hidpi", false) if has_config else false
	var screen_scale := DisplayServer.screen_get_scale()
	if hidpi or screen_scale <= 1.0:
		get_viewport().scaling_3d_scale = 1.0
		get_window().content_scale_factor = screen_scale
	else:
		get_viewport().scaling_3d_scale = 1.0 / screen_scale
		get_window().content_scale_factor = 1.0


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
