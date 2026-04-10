extends CanvasLayer

const AUTH_LINK_URL = "https://game.spacemolt.com/auth/link"

signal show_player_select(players: Array)

@onready var key_field: LineEdit = %KeyField
@onready var submit_button: Button = %SubmitButton
@onready var sign_in_button: Button = %SignInButton
@onready var status_label: Label = %StatusLabel


func _ready() -> void:
	submit_button.pressed.connect(_on_submit)
	sign_in_button.pressed.connect(_on_sign_in)
	key_field.text_submitted.connect(func(_text: String) -> void: _on_submit())
	NetworkManager.request_started.connect(func() -> void: submit_button.disabled = true)
	NetworkManager.request_completed.connect(func() -> void: submit_button.disabled = false)


func _on_sign_in() -> void:
	OS.shell_open(AUTH_LINK_URL)
	_set_status("Sign in via your browser, then paste the key here.")


func _on_submit() -> void:
	var key := key_field.text.strip_edges()
	if key.is_empty():
		_set_status("Paste your API key from the browser.", true)
		return

	_set_status("Validating...")
	NetworkManager.set_api_key(key)
	NetworkManager.get_players(
		func(players: Array) -> void:
			show_player_select.emit(players)
		,
		func(_error: Dictionary = {}) -> void:
			_set_status("Invalid key. Try signing in again.", true)
			NetworkManager.api_key = ""
	)


func _set_status(text: String, is_error: bool = false) -> void:
	status_label.text = text
	status_label.add_theme_color_override("font_color", Color.RED if is_error else Color.WHITE)
