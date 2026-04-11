extends CanvasLayer

const EMPIRES := ["solarian", "voidborn", "crimson", "nebula", "outerrim"]

signal show_player_select(players: Array)

@onready var username_field: LineEdit = %UsernameField
@onready var empire_dropdown: OptionButton = %EmpireDropdown
@onready var create_button: Button = %CreateButton
@onready var back_button: Button = %BackButton
@onready var status_label: Label = %StatusLabel


func _ready() -> void:
	for empire in EMPIRES:
		empire_dropdown.add_item(empire.capitalize())
	create_button.pressed.connect(_on_create)
	back_button.pressed.connect(_on_back)
	username_field.text_submitted.connect(func(_text: String) -> void: _on_create())


func _on_back() -> void:
	_set_status("Loading...")
	back_button.disabled = true
	var on_success := func(players: Array) -> void:
		show_player_select.emit(players)
	var on_error := func(_error: Dictionary = {}) -> void:
		_set_status("Failed to load players.", true)
		back_button.disabled = false
	NetworkManager.get_players(on_success, on_error)


func _on_create() -> void:
	var username := username_field.text.strip_edges()
	if username.is_empty():
		_set_status("Enter a username.", true)
		return

	var empire: String = EMPIRES[empire_dropdown.selected]
	_set_status("Creating player...")
	create_button.disabled = true
	back_button.disabled = true

	var on_created := func(_content: Dictionary) -> void:
		pass  # authenticated signal handled by Main.gd
	var on_create_error := func(error: Dictionary = {}) -> void:
		var msg: String = error.get("message", "Failed to create player.")
		_set_status(msg, true)
		create_button.disabled = false
		back_button.disabled = false
	NetworkManager.create_player(username, empire, on_created, on_create_error)


func _set_status(text: String, is_error: bool = false) -> void:
	status_label.text = text
	status_label.modulate = Color.RED if is_error else Color.WHITE
