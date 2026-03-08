extends Node

const LOGIN_SCENE := preload("res://scenes/ui/login.tscn")
const REGISTER_SCENE := preload("res://scenes/ui/register.tscn")
const GAME_SCENE := preload("res://scenes/game/game.tscn")

var _current: Node = null


func _ready() -> void:
	NetworkManager.authenticated.connect(_on_authenticated)
	NetworkManager.session_expired.connect(_on_session_expired)

	# Try to restore a saved session before showing login
	if NetworkManager.has_saved_session():
		NetworkManager.try_restore_session(
			func(content: Dictionary) -> void:
				_on_authenticated(content),
			func() -> void:
				_switch_to(LOGIN_SCENE.instantiate())
		)
	else:
		_switch_to(LOGIN_SCENE.instantiate())


func _on_authenticated(initial_state: Dictionary) -> void:
	StateManager.set_initial_state(initial_state)
	_switch_to(GAME_SCENE.instantiate())


func _on_session_expired() -> void:
	NetworkManager._delete_saved_session()
	_switch_to(LOGIN_SCENE.instantiate())


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
