extends CanvasLayer

signal show_register

@onready var username_field: LineEdit = %Username
@onready var password_field: LineEdit = %Password
@onready var login_button: Button = %LoginButton
@onready var status_label: Label = %StatusLabel


func _ready() -> void:
	UIManager.error_shown.connect(_on_error)
	NetworkManager.request_started.connect(_on_request_started)
	NetworkManager.request_completed.connect(_on_request_completed)
	login_button.pressed.connect(_on_login_pressed)
	%RegisterLink.pressed.connect(func(): show_register.emit())
	password_field.gui_input.connect(func(event):
		if event is InputEventKey and event.pressed and event.keycode == KEY_ENTER:
			_on_login_pressed()
	)

	# Pre-fill username from saved session if available
	_prefill_username()


func _on_login_pressed() -> void:
	var username := username_field.text.strip_edges()
	var password := password_field.text

	if username.is_empty() or password.is_empty():
		_set_status("Enter username and password.", true)
		return

	_set_status("Connecting...")
	NetworkManager.create_session(func():
		NetworkManager.login(username, password)
	)


func _on_error(message: String) -> void:
	_set_status(message, true)


func _on_request_started() -> void:
	login_button.disabled = true


func _on_request_completed() -> void:
	login_button.disabled = false


func _prefill_username() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(NetworkManager.SESSION_PATH) == OK:
		var saved_user: String = cfg.get_value("auth", "username", "")
		if not saved_user.is_empty():
			username_field.text = saved_user
			password_field.grab_focus()


func _set_status(text: String, is_error: bool = false) -> void:
	status_label.text = text
	status_label.modulate = Color.RED if is_error else Color.WHITE
