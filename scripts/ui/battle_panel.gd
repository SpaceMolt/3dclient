extends PanelContainer

const BATTLE_POLL_INTERVAL := 5.0

@onready var stance_fire: Button = %StanceFire
@onready var stance_evade: Button = %StanceEvade
@onready var stance_brace: Button = %StanceBrace
@onready var stance_flee: Button = %StanceFlee
@onready var advance_button: Button = %AdvanceButton
@onready var retreat_button: Button = %RetreatButton
@onready var zone_label: Label = %ZoneLabel
@onready var stance_label: Label = %StanceLabel
@onready var reload_button: Button = %ReloadButton
@onready var engage_button: MenuButton = %EngageButton
@onready var battle_status: Label = %BattleStatus
@onready var participants_list: VBoxContainer = %ParticipantsList

var _poll_timer: Timer
var _stance_buttons: Array[Button] = []


func _ready() -> void:
	_stance_buttons = [stance_fire, stance_evade, stance_brace, stance_flee]

	stance_fire.pressed.connect(func(): _set_stance("fire"))
	stance_evade.pressed.connect(func(): _set_stance("evade"))
	stance_brace.pressed.connect(func(): _set_stance("brace"))
	stance_flee.pressed.connect(func(): _set_stance("flee"))
	advance_button.pressed.connect(_on_advance)
	retreat_button.pressed.connect(_on_retreat)
	reload_button.pressed.connect(_on_reload)

	NetworkManager.request_started.connect(_lock)
	NetworkManager.request_completed.connect(_unlock)
	StateManager.battle_updated.connect(_refresh)
	StateManager.combat_ended.connect(_on_combat_ended)

	# Start battle polling
	_poll_timer = Timer.new()
	_poll_timer.name = "BattlePollTimer"
	_poll_timer.wait_time = BATTLE_POLL_INTERVAL
	_poll_timer.timeout.connect(_poll_battle)
	add_child(_poll_timer)
	_poll_timer.start()

	# Fetch initial battle status
	_poll_battle()


func _poll_battle() -> void:
	if NetworkManager.is_request_pending:
		return
	NetworkManager.send_battle_command("get_status", {}, func(content: Dictionary) -> void:
		StateManager.update_battle(content)
	)


func _set_stance(stance: String) -> void:
	battle_status.text = "Setting stance: %s..." % stance
	NetworkManager.send_battle_command("stance", {"id": stance}, func(content: Dictionary) -> void:
		StateManager.update_battle(content)
		battle_status.text = "Stance set to %s." % stance
	)


func _on_advance() -> void:
	battle_status.text = "Advancing..."
	NetworkManager.send_battle_command("advance", {}, func(content: Dictionary) -> void:
		StateManager.update_battle(content)
		battle_status.text = "Advanced."
	)


func _on_retreat() -> void:
	battle_status.text = "Retreating..."
	NetworkManager.send_battle_command("retreat", {}, func(content: Dictionary) -> void:
		StateManager.update_battle(content)
		battle_status.text = "Retreated."
	)


func _on_reload() -> void:
	battle_status.text = "Reloading..."
	NetworkManager.send_battle_command("reload", {}, func(content: Dictionary) -> void:
		StateManager.update_battle(content)
		battle_status.text = "Reloaded."
	)


func _setup_engage_menu() -> void:
	var popup := engage_button.get_popup()
	popup.clear()
	for c in popup.id_pressed.get_connections():
		popup.id_pressed.disconnect(c["callable"])

	for side in StateManager.get_battle_sides():
		popup.add_item(side.get("name", "Unknown Side"))
		popup.set_item_metadata(popup.item_count - 1, side.get("side_id", ""))

	popup.id_pressed.connect(func(id: int):
		var side_id: String = popup.get_item_metadata(id)
		var side_name: String = popup.get_item_text(id)
		battle_status.text = "Engaging %s..." % side_name
		NetworkManager.send_battle_command("engage", {"side_id": side_id}, func(content: Dictionary) -> void:
			StateManager.update_battle(content)
			battle_status.text = "Engaged %s." % side_name
		)
	)


func _refresh() -> void:
	var me := StateManager.get_my_participant()
	if me.is_empty():
		zone_label.text = "Zone: —"
		stance_label.text = "Stance: —"
	else:
		zone_label.text = "Zone: %s" % me.get("zone", "?")
		var current_stance: String = me.get("stance", "?")
		stance_label.text = "Stance: %s" % current_stance

		# Highlight active stance button
		for btn in _stance_buttons:
			btn.modulate = Color.WHITE
		match current_stance:
			"fire": stance_fire.modulate = Color.YELLOW
			"evade": stance_evade.modulate = Color.CYAN
			"brace": stance_brace.modulate = Color.GREEN
			"flee": stance_flee.modulate = Color.ORANGE

	_refresh_participants()
	_setup_engage_menu()


func _refresh_participants() -> void:
	# Clear existing entries
	for child in participants_list.get_children():
		child.queue_free()

	var my_id: String = StateManager.player.get("id", "")
	for p in StateManager.get_battle_participants():
		var label := Label.new()
		var pname: String = p.get("player_name", "Unknown")
		var hull: int = p.get("hull_pct", 0)
		var shield: int = p.get("shield_pct", 0)
		var stance: String = p.get("stance", "?")
		var zone: String = p.get("zone", "?")
		label.text = "%s  H:%d%% S:%d%%  [%s] Z:%s" % [pname, hull, shield, stance, zone]
		label.add_theme_font_size_override("font_size", 12)
		if p.get("player_id", "") == my_id:
			label.modulate = Color(0.4, 0.8, 1.0)
		participants_list.add_child(label)


func _on_combat_ended() -> void:
	battle_status.text = "Combat ended."
	_poll_timer.stop()


func _lock() -> void:
	for btn in _stance_buttons:
		btn.disabled = true
	advance_button.disabled = true
	retreat_button.disabled = true
	reload_button.disabled = true
	engage_button.disabled = true


func _unlock() -> void:
	for btn in _stance_buttons:
		btn.disabled = false
	advance_button.disabled = false
	retreat_button.disabled = false
	reload_button.disabled = false
	engage_button.disabled = false
