extends CanvasLayer

signal show_create_player
signal show_auth

@onready var player_list: VBoxContainer = %PlayerList
@onready var create_button: Button = %CreateButton
@onready var sign_out_button: Button = %SignOutButton
@onready var status_label: Label = %StatusLabel

var _players: Array = []


func _ready() -> void:
	create_button.pressed.connect(func() -> void: show_create_player.emit())
	sign_out_button.pressed.connect(_on_sign_out)


func set_players(players: Array) -> void:
	_players = players
	_refresh_list()


func _refresh_list() -> void:
	for child in player_list.get_children():
		child.queue_free()

	for player in _players:
		var btn := Button.new()
		var username: String = player.get("username", "Unknown")
		var empire: String = player.get("empire", "").capitalize()
		btn.text = "%s  [%s]" % [username, empire]
		btn.custom_minimum_size.y = 44
		var player_id: String = player.get("id", "")
		btn.pressed.connect(func() -> void: _on_player_selected(player_id))
		player_list.add_child(btn)


func _on_player_selected(player_id: String) -> void:
	_set_status("Connecting...")
	_set_buttons_disabled(true)
	NetworkManager.select_player(player_id,
		func(_content: Dictionary) -> void:
			pass  # Main.gd handles authenticated signal
		,
		func(_error: Dictionary = {}) -> void:
			_set_status("Failed to connect. Try again.", true)
			_set_buttons_disabled(false)
	)


func _on_sign_out() -> void:
	NetworkManager.clear_auth()
	show_auth.emit()


func _set_buttons_disabled(disabled: bool) -> void:
	create_button.disabled = disabled
	sign_out_button.disabled = disabled
	for child in player_list.get_children():
		if child is Button:
			child.disabled = disabled


func _set_status(text: String, is_error: bool = false) -> void:
	status_label.text = text
	status_label.modulate = Color.RED if is_error else Color.WHITE
