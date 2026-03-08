extends CanvasLayer

signal show_login

const EMPIRES := ["solarian", "voidborn", "crimson", "nebula", "outerrim"]
const EMPIRE_LABELS := ["Solarian", "Voidborn", "Crimson", "Nebula Trade", "Outer Rim"]

@onready var username_field: LineEdit = %Username
@onready var empire_option: OptionButton = %EmpireOption
@onready var code_field: LineEdit = %RegistrationCode
@onready var register_button: Button = %RegisterButton
@onready var status_label: Label = %StatusLabel
@onready var password_display: Label = %PasswordDisplay
@onready var password_panel: Panel = %PasswordPanel


func _ready() -> void:
	for label in EMPIRE_LABELS:
		empire_option.add_item(label)

	UIManager.error_shown.connect(_on_error)
	NetworkManager.request_started.connect(_on_request_started)
	NetworkManager.request_completed.connect(_on_request_completed)
	register_button.pressed.connect(_on_register_pressed)
	%BackToLogin.pressed.connect(func(): show_login.emit())

	password_panel.hide()


func _on_register_pressed() -> void:
	var username := username_field.text.strip_edges()
	var code := code_field.text.strip_edges()
	var empire := EMPIRES[empire_option.selected]

	if username.is_empty() or code.is_empty():
		_set_status("All fields are required.", true)
		return

	_set_status("Registering...")
	NetworkManager.create_session(func():
		NetworkManager.register(username, empire, code)
	)

	# Listen for the full response to extract the generated password
	NetworkManager.authenticated.connect(_on_registered, CONNECT_ONE_SHOT)


func _on_registered(content: Dictionary) -> void:
	var password: String = content.get("password", "")
	if password.is_empty():
		return
	# Show the generated password — user must save this
	password_display.text = password
	password_panel.show()


func _on_error(message: String) -> void:
	_set_status(message, true)


func _on_request_started() -> void:
	register_button.disabled = true


func _on_request_completed() -> void:
	register_button.disabled = false


func _set_status(text: String, is_error: bool = false) -> void:
	status_label.text = text
	status_label.modulate = Color.RED if is_error else Color.WHITE
