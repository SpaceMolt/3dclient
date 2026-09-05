extends CanvasLayer

signal show_player_select(players: Array)

@onready var key_field: LineEdit = %KeyField
@onready var submit_button: Button = %SubmitButton
@onready var sign_in_button: Button = %SignInButton
@onready var status_label: Label = %StatusLabel
@onready var title_label: Label = %Title
@onready var subtitle_label: Label = %Subtitle
@onready var key_label: Label = %KeyLabel


func _ready() -> void:
	_apply_theme()
	submit_button.pressed.connect(_on_submit)
	sign_in_button.pressed.connect(_on_sign_in)
	key_field.text_submitted.connect(func(_text: String) -> void: _on_submit())
	NetworkManager.request_started.connect(func() -> void: submit_button.disabled = true)
	NetworkManager.request_completed.connect(func() -> void: submit_button.disabled = false)
	NetworkManager.auth_error.connect(_on_auth_error)


func _apply_theme() -> void:
	# Title uses Orbitron like the www site
	title_label.add_theme_font_override("font", ThemeManager.font_orbitron_bold)
	title_label.modulate = ThemeColors.PLASMA_CYAN

	subtitle_label.modulate = ThemeColors.CHROME_SILVER
	key_label.modulate = ThemeColors.CHROME_SILVER

	# Primary action button — orange gradient style
	_style_primary_button(sign_in_button)


func _style_primary_button(btn: Button) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = ThemeColors.SHELL_ORANGE
	normal.border_color = ThemeColors.SHELL_ORANGE
	normal.set_border_width_all(2)
	normal.set_corner_radius_all(6)
	normal.set_content_margin_all(8)
	btn.add_theme_stylebox_override("normal", normal)

	var hover := StyleBoxFlat.new()
	hover.bg_color = Color(ThemeColors.SHELL_ORANGE, 0.85)
	hover.border_color = ThemeColors.SHELL_ORANGE
	hover.set_border_width_all(2)
	hover.set_corner_radius_all(6)
	hover.set_content_margin_all(8)
	btn.add_theme_stylebox_override("hover", hover)

	var pressed := StyleBoxFlat.new()
	pressed.bg_color = Color(ThemeColors.SHELL_ORANGE, 0.7)
	pressed.border_color = ThemeColors.SHELL_ORANGE
	pressed.set_border_width_all(2)
	pressed.set_corner_radius_all(6)
	pressed.set_content_margin_all(8)
	btn.add_theme_stylebox_override("pressed", pressed)

	btn.add_theme_color_override("font_color", ThemeColors.STAR_WHITE)
	btn.add_theme_color_override("font_hover_color", ThemeColors.STAR_WHITE)
	btn.add_theme_color_override("font_pressed_color", ThemeColors.STAR_WHITE)


func _on_sign_in() -> void:
	sign_in_button.disabled = true
	_set_status("Starting browser login...")
	NetworkManager.start_device_login(_on_device_link, _on_auth_error)


func _on_device_link(url: String, user_code: String) -> void:
	OS.shell_open(url)
	_set_status("Approve the login in your browser.\nCode: %s\n%s" % [user_code, url])


func _on_auth_error(_error = null) -> void:
	sign_in_button.disabled = false
	var message := "Login failed. Try again."
	if _error is String:
		message = _error
	elif _error is Dictionary and _error.has("message"):
		message = str(_error["message"])
	_set_status(message, true)


func _on_submit() -> void:
	var key := key_field.text.strip_edges()
	if key.is_empty():
		_set_status("Paste your API key from the browser.", true)
		return

	_set_status("Validating...")
	NetworkManager.set_api_key(key)
	var on_success := func(players: Array) -> void:
		show_player_select.emit(players)
	var on_error := func(_error: Dictionary = {}) -> void:
		_set_status("Invalid key. Try signing in again.", true)
		NetworkManager.clear_auth()
		key_field.text = ""
	NetworkManager.get_players(on_success, on_error)


func _set_status(text: String, is_error: bool = false) -> void:
	status_label.text = text
	status_label.modulate = ThemeColors.TEXT_ERROR if is_error else ThemeColors.TEXT_PRIMARY
