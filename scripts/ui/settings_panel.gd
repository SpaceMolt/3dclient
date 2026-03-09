extends CanvasLayer

const SETTINGS_PATH = "user://settings.cfg"

@onready var close_button: Button = $Panel/TopBar/CloseButton
@onready var master_volume_slider: HSlider = %MasterVolumeSlider
@onready var master_volume_label: Label = %MasterVolumeLabel
@onready var mute_checkbox: CheckBox = %MuteCheckbox
@onready var fullscreen_checkbox: CheckBox = %FullscreenCheckbox
@onready var vsync_checkbox: CheckBox = %VSyncCheckbox
@onready var server_url_field: LineEdit = %ServerUrlField
@onready var tick_slider: HSlider = %TickSlider
@onready var tick_label: Label = %TickLabel


func _ready() -> void:
	close_button.pressed.connect(hide)
	master_volume_slider.value_changed.connect(_on_master_volume_changed)
	mute_checkbox.toggled.connect(_on_mute_toggled)
	fullscreen_checkbox.toggled.connect(_on_fullscreen_toggled)
	vsync_checkbox.toggled.connect(_on_vsync_toggled)
	server_url_field.text_submitted.connect(_on_server_url_submitted)
	tick_slider.value_changed.connect(_on_tick_duration_changed)
	_load_settings()


func _load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		# Audio
		master_volume_slider.value = cfg.get_value("audio", "master_volume", 100.0)
		mute_checkbox.button_pressed = cfg.get_value("audio", "mute", false)

		# Display
		fullscreen_checkbox.button_pressed = cfg.get_value("display", "fullscreen", false)
		vsync_checkbox.button_pressed = cfg.get_value("display", "vsync", true)

		# Network
		server_url_field.text = cfg.get_value("network", "server_url", NetworkManager.DEFAULT_BASE_URL)
		tick_slider.value = cfg.get_value("network", "tick_duration", NetworkManager.DEFAULT_TICK_DURATION)
	else:
		# Defaults
		master_volume_slider.value = 100.0
		mute_checkbox.button_pressed = false
		fullscreen_checkbox.button_pressed = DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
		vsync_checkbox.button_pressed = DisplayServer.window_get_vsync_mode() != DisplayServer.VSYNC_DISABLED
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


func _apply_network_url() -> void:
	var url := server_url_field.text.strip_edges()
	if url.is_empty():
		url = NetworkManager.DEFAULT_BASE_URL
		server_url_field.text = url
	NetworkManager.base_url = url


func _apply_network_tick() -> void:
	NetworkManager.tick_duration = tick_slider.value
	var poll_timer := NetworkManager.get_node_or_null("PollTimer") as Timer
	if poll_timer:
		poll_timer.wait_time = tick_slider.value


func _update_volume_label() -> void:
	master_volume_label.text = "%d%%" % int(master_volume_slider.value)


func _update_tick_label() -> void:
	tick_label.text = "%ds" % int(tick_slider.value)
