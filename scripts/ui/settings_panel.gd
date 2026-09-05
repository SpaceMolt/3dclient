extends CanvasLayer

const SETTINGS_PATH = "user://settings.cfg"

@onready var close_button: Button = $Panel/TopBar/CloseButton
@onready var master_volume_slider: HSlider = %MasterVolumeSlider
@onready var master_volume_label: Label = %MasterVolumeLabel
@onready var mute_checkbox: CheckBox = %MuteCheckbox
@onready var fullscreen_checkbox: CheckBox = %FullscreenCheckbox
@onready var vsync_checkbox: CheckBox = %VSyncCheckbox
@onready var hidpi_checkbox: CheckBox = %HiDPICheckbox
@onready var server_url_field: LineEdit = %ServerUrlField
@onready var tick_slider: HSlider = %TickSlider
@onready var tick_label: Label = %TickLabel

# Player customization controls
@onready var status_field: LineEdit = %StatusField
@onready var set_status_button: Button = %SetStatusButton
@onready var clan_tag_field: LineEdit = %ClanTagField
@onready var set_tag_button: Button = %SetTagButton
@onready var primary_color_field: LineEdit = %PrimaryColorField
@onready var primary_color_preview: ColorRect = %PrimaryColorPreview
@onready var secondary_color_field: LineEdit = %SecondaryColorField
@onready var secondary_color_preview: ColorRect = %SecondaryColorPreview
@onready var set_colors_button: Button = %SetColorsButton
@onready var home_base_label: Label = %HomeBaseLabel
@onready var set_home_base_button: Button = %SetHomeBaseButton
@onready var player_status_label: Label = %PlayerStatusLabel


func _ready() -> void:
	close_button.pressed.connect(hide)
	master_volume_slider.value_changed.connect(_on_master_volume_changed)
	mute_checkbox.toggled.connect(_on_mute_toggled)
	fullscreen_checkbox.toggled.connect(_on_fullscreen_toggled)
	vsync_checkbox.toggled.connect(_on_vsync_toggled)
	hidpi_checkbox.toggled.connect(_on_hidpi_toggled)
	server_url_field.text_submitted.connect(_on_server_url_submitted)
	tick_slider.value_changed.connect(_on_tick_duration_changed)

	# Player customization connections
	set_status_button.pressed.connect(_on_set_status_pressed)
	set_tag_button.pressed.connect(_on_set_tag_pressed)
	set_colors_button.pressed.connect(_on_set_colors_pressed)
	set_home_base_button.pressed.connect(_on_set_home_base_pressed)
	primary_color_field.text_changed.connect(_on_primary_color_text_changed)
	secondary_color_field.text_changed.connect(_on_secondary_color_text_changed)
	clan_tag_field.max_length = 4
	visibility_changed.connect(_on_visibility_changed)

	# Opaque panel background
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.06, 0.07, 0.10, 0.97)
	panel_style.border_color = Color(0.2, 0.5, 0.6, 0.5)
	panel_style.set_border_width_all(1)
	panel_style.set_corner_radius_all(4)
	$Panel.add_theme_stylebox_override("panel", panel_style)

	_load_settings()


func _load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		# Audio
		master_volume_slider.value = cfg.get_value("audio", "master_volume", 100.0)
		mute_checkbox.button_pressed = cfg.get_value("audio", "mute", false)

		# Display
		fullscreen_checkbox.button_pressed = cfg.get_value("display", "fullscreen", true)
		vsync_checkbox.button_pressed = cfg.get_value("display", "vsync", true)
		hidpi_checkbox.button_pressed = cfg.get_value("display", "hidpi", false)

		# Network
		server_url_field.text = cfg.get_value("network", "server_url", NetworkManager.DEFAULT_BASE_URL)
		tick_slider.value = cfg.get_value("network", "tick_duration", NetworkManager.DEFAULT_TICK_DURATION)
	else:
		# Defaults
		master_volume_slider.value = 100.0
		mute_checkbox.button_pressed = false
		fullscreen_checkbox.button_pressed = DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
		vsync_checkbox.button_pressed = DisplayServer.window_get_vsync_mode() != DisplayServer.VSYNC_DISABLED
		hidpi_checkbox.button_pressed = false
		server_url_field.text = NetworkManager.base_url
		tick_slider.value = NetworkManager.tick_duration

	# Apply loaded settings
	_apply_audio()
	_apply_display()
	_apply_network_tick()
	_apply_network_url()
	_update_volume_label()
	_update_tick_label()


func _save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "master_volume", master_volume_slider.value)
	cfg.set_value("audio", "mute", mute_checkbox.button_pressed)
	cfg.set_value("display", "fullscreen", fullscreen_checkbox.button_pressed)
	cfg.set_value("display", "vsync", vsync_checkbox.button_pressed)
	cfg.set_value("display", "hidpi", hidpi_checkbox.button_pressed)
	cfg.set_value("network", "server_url", server_url_field.text)
	cfg.set_value("network", "tick_duration", tick_slider.value)
	cfg.save(SETTINGS_PATH)


func _on_master_volume_changed(_value: float) -> void:
	_update_volume_label()
	_apply_audio()
	_save_settings()


func _on_mute_toggled(_pressed: bool) -> void:
	_apply_audio()
	_save_settings()


func _on_fullscreen_toggled(_pressed: bool) -> void:
	_apply_display()
	_save_settings()


func _on_vsync_toggled(_pressed: bool) -> void:
	_apply_display()
	_save_settings()


func _on_hidpi_toggled(_pressed: bool) -> void:
	_apply_display()
	_save_settings()


func _on_server_url_submitted(_new_text: String) -> void:
	_apply_network_url()
	_save_settings()


func _on_tick_duration_changed(_value: float) -> void:
	_update_tick_label()
	_apply_network_tick()
	_save_settings()


func _apply_audio() -> void:
	var bus_idx := AudioServer.get_bus_index("Master")
	if bus_idx < 0:
		return
	var linear := master_volume_slider.value / 100.0
	AudioServer.set_bus_volume_db(bus_idx, linear_to_db(linear))
	AudioServer.set_bus_mute(bus_idx, mute_checkbox.button_pressed)


func _apply_display() -> void:
	if fullscreen_checkbox.button_pressed:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)

	if vsync_checkbox.button_pressed:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
	else:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)

	# HiDPI rendering — scale resolution on retina displays
	var screen_scale := DisplayServer.screen_get_scale()
	if hidpi_checkbox.button_pressed or screen_scale <= 1.0:
		get_viewport().scaling_3d_scale = 1.0
		get_window().content_scale_factor = screen_scale
	else:
		get_viewport().scaling_3d_scale = 1.0 / screen_scale
		get_window().content_scale_factor = 1.0


func _apply_network_url() -> void:
	var url := server_url_field.text.strip_edges()
	if url.is_empty():
		url = NetworkManager.DEFAULT_BASE_URL
		server_url_field.text = url
	NetworkManager.base_url = url


func _apply_network_tick() -> void:
	NetworkManager.tick_duration = tick_slider.value


func _update_volume_label() -> void:
	master_volume_label.text = "%d%%" % int(master_volume_slider.value)


func _update_tick_label() -> void:
	tick_label.text = "%ds" % int(tick_slider.value)


# --- Player Customization ---

func _populate_player_fields() -> void:
	var p: Dictionary = StateManager.player
	status_field.text = p.get("status_message", "")
	clan_tag_field.text = p.get("clan_tag", "")
	var primary: String = p.get("primary_color", "")
	var secondary: String = p.get("secondary_color", "")
	primary_color_field.text = primary
	secondary_color_field.text = secondary
	_update_color_preview(primary_color_preview, primary)
	_update_color_preview(secondary_color_preview, secondary)

	var home_base: String = p.get("home_base", "")
	if home_base.is_empty():
		home_base_label.text = "Home Base: None"
	else:
		home_base_label.text = "Home Base: %s" % home_base
	set_home_base_button.visible = StateManager.is_docked()
	player_status_label.text = ""


func _on_visibility_changed() -> void:
	if visible:
		_populate_player_fields()


func _set_player_controls_disabled(disabled: bool) -> void:
	set_status_button.disabled = disabled
	set_tag_button.disabled = disabled
	set_colors_button.disabled = disabled
	set_home_base_button.disabled = disabled
	status_field.editable = not disabled
	clan_tag_field.editable = not disabled
	primary_color_field.editable = not disabled
	secondary_color_field.editable = not disabled


func _show_player_status(text: String, is_error: bool = false) -> void:
	player_status_label.text = text
	if is_error:
		player_status_label.modulate = ThemeColors.CLAW_RED
	else:
		player_status_label.modulate = ThemeColors.BIO_GREEN


func _on_set_status_pressed() -> void:
	var text := status_field.text.strip_edges()
	_set_player_controls_disabled(true)
	_show_player_status("Setting status...")
	NetworkManager.send_social_command("set_status", {
		"status_message": text,
		"clan_tag": StateManager.player.get("clan_tag", ""),
	}, func(_content: Dictionary) -> void:
		_refresh_player_state("Status updated.")
	)


func _on_set_tag_pressed() -> void:
	var tag := clan_tag_field.text.strip_edges().left(4)
	_set_player_controls_disabled(true)
	_show_player_status("Setting clan tag...")
	NetworkManager.send_social_command("set_status", {
		"status_message": StateManager.player.get("status_message", ""),
		"clan_tag": tag,
	}, func(_content: Dictionary) -> void:
		_refresh_player_state("Clan tag updated.")
	)


func _on_set_colors_pressed() -> void:
	var primary := _normalize_hex(primary_color_field.text.strip_edges())
	var secondary := _normalize_hex(secondary_color_field.text.strip_edges())
	if not _is_valid_hex(primary) or not _is_valid_hex(secondary):
		_show_player_status("Invalid hex color (use 6-char hex, e.g. FF0000).", true)
		return
	_set_player_controls_disabled(true)
	_show_player_status("Setting colors...")
	NetworkManager.send_social_command("set_colors", {
		"primary_color": primary,
		"secondary_color": secondary,
	}, func(_content: Dictionary) -> void:
		_refresh_player_state("Colors updated.")
	)


func _on_set_home_base_pressed() -> void:
	if not StateManager.is_docked():
		_show_player_status("Must be docked to set home base.", true)
		return
	var base_id: String = StateManager.location.get("docked_at", "")
	if base_id.is_empty():
		_show_player_status("No base found.", true)
		return
	_set_player_controls_disabled(true)
	_show_player_status("Setting home base...")
	NetworkManager.send_salvage_command("set_home", {
		"id": base_id,
	}, func(_content: Dictionary) -> void:
		_refresh_player_state("Home base updated.")
	)


func _refresh_player_state(success_msg: String) -> void:
	NetworkManager.send_command("get_status", {}, func(_content: Dictionary) -> void:
		_set_player_controls_disabled(false)
		_populate_player_fields()
		_show_player_status(success_msg)
	)


func _on_primary_color_text_changed(new_text: String) -> void:
	_update_color_preview(primary_color_preview, new_text.strip_edges())


func _on_secondary_color_text_changed(new_text: String) -> void:
	_update_color_preview(secondary_color_preview, new_text.strip_edges())


func _update_color_preview(rect: ColorRect, hex_str: String) -> void:
	var normalized := _normalize_hex(hex_str)
	if _is_valid_hex(normalized):
		rect.color = Color.html(normalized)
	else:
		rect.color = ThemeColors.DIM_GREY


static func _normalize_hex(hex_str: String) -> String:
	if hex_str.begins_with("#"):
		return hex_str.substr(1)
	return hex_str


static func _is_valid_hex(hex_str: String) -> bool:
	if hex_str.length() != 6:
		return false
	for c in hex_str:
		if c not in "0123456789abcdefABCDEF":
			return false
	return true
