extends PanelContainer

## Missions panel — view available missions, accept, track active, complete.

@onready var tab_container: TabContainer = %MissionTabs
@onready var available_list: VBoxContainer = %AvailableList
@onready var active_list: VBoxContainer = %ActiveList
@onready var status_label: Label = %MissionStatus

var _available_missions: Array = []
var _active_missions: Array = []


func _ready() -> void:
	NetworkManager.request_started.connect(func(): _set_all_disabled(true))
	NetworkManager.request_completed.connect(func(): _set_all_disabled(false))
	tab_container.tab_changed.connect(_on_tab_changed)

	_fetch_available()
	_fetch_active()


func _on_tab_changed(tab: int) -> void:
	if tab == 0:
		_fetch_available()
	else:
		_fetch_active()


func _fetch_available() -> void:
	status_label.text = "Loading missions..."
	NetworkManager.send_command("get_missions", {}, func(content: Dictionary) -> void:
		_available_missions = content.get("missions", [])
		_refresh_available()
		status_label.text = "%d available" % _available_missions.size()
	)


func _fetch_active() -> void:
	status_label.text = "Loading active..."
	NetworkManager.send_command("get_active_missions", {}, func(content: Dictionary) -> void:
		_active_missions = content.get("missions", content.get("active_missions", []))
		_refresh_active()
		status_label.text = "%d active" % _active_missions.size()
	)


func _refresh_available() -> void:
	for child in available_list.get_children():
		child.queue_free()

	if _available_missions.is_empty():
		var empty := Label.new()
		empty.text = "No missions available at this location."
		empty.add_theme_font_size_override("font_size", 12)
		empty.modulate = ThemeColors.TEXT_MUTED
		available_list.add_child(empty)
		return

	for mission in _available_missions:
		var card := _make_mission_card(mission, true)
		available_list.add_child(card)


func _refresh_active() -> void:
	for child in active_list.get_children():
		child.queue_free()

	if _active_missions.is_empty():
		var empty := Label.new()
		empty.text = "No active missions."
		empty.add_theme_font_size_override("font_size", 12)
		empty.modulate = ThemeColors.TEXT_MUTED
		active_list.add_child(empty)
		return

	for mission in _active_missions:
		var card := _make_mission_card(mission, false)
		active_list.add_child(card)


func _make_mission_card(mission: Dictionary, is_available: bool) -> PanelContainer:
	var panel := PanelContainer.new()

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_bottom", 6)

	# Title row
	var title_row := HBoxContainer.new()
	var title := Label.new()
	title.text = mission.get("title", mission.get("name", "Unknown Mission"))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 13)
	title_row.add_child(title)

	var mtype := Label.new()
	mtype.text = "[%s]" % mission.get("type", "?")
	mtype.add_theme_font_size_override("font_size", 11)
	mtype.modulate = ThemeColors.CHROME_SILVER
	title_row.add_child(mtype)
	vbox.add_child(title_row)

	# Description
	var desc: String = mission.get("description", mission.get("objective", ""))
	if not desc.is_empty():
		var desc_label := Label.new()
		desc_label.text = desc
		desc_label.add_theme_font_size_override("font_size", 11)
		desc_label.modulate = ThemeColors.CHROME_SILVER
		desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		vbox.add_child(desc_label)

	# Rewards
	var reward_text := ""
	var credits: int = mission.get("reward_credits", mission.get("credits_reward", 0))
	if credits > 0:
		reward_text += "¢%d" % credits
	var xp: int = mission.get("reward_xp", mission.get("xp_reward", 0))
	if xp > 0:
		reward_text += "  +%d XP" % xp
	if not reward_text.is_empty():
		var reward_label := Label.new()
		reward_label.text = "Reward: %s" % reward_text
		reward_label.add_theme_font_size_override("font_size", 11)
		reward_label.modulate = ThemeColors.WARNING_YELLOW
		vbox.add_child(reward_label)

	# Progress (for active missions)
	if not is_available:
		var progress: String = mission.get("progress", "")
		var status: String = mission.get("status", "")
		if not progress.is_empty() or not status.is_empty():
			var prog_label := Label.new()
			prog_label.text = progress if not progress.is_empty() else status
			prog_label.add_theme_font_size_override("font_size", 11)
			prog_label.modulate = ThemeColors.TEXT_ACCENT
			vbox.add_child(prog_label)

	# Action buttons
	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 8)

	var mission_id: String = mission.get("mission_id", mission.get("id", ""))

	if is_available:
		var accept_btn := Button.new()
		accept_btn.text = "Accept"
		accept_btn.add_theme_font_size_override("font_size", 11)
		accept_btn.pressed.connect(func(): _accept_mission(mission_id))
		btn_row.add_child(accept_btn)
	else:
		var completable: bool = mission.get("completable", mission.get("can_complete", false))
		if completable:
			var complete_btn := Button.new()
			complete_btn.text = "Complete"
			complete_btn.add_theme_font_size_override("font_size", 11)
			complete_btn.pressed.connect(func(): _complete_mission(mission_id))
			btn_row.add_child(complete_btn)

		var abandon_btn := Button.new()
		abandon_btn.text = "Abandon"
		abandon_btn.add_theme_font_size_override("font_size", 11)
		abandon_btn.modulate = ThemeColors.CLAW_RED
		abandon_btn.pressed.connect(func(): _abandon_mission(mission_id))
		btn_row.add_child(abandon_btn)

	vbox.add_child(btn_row)
	margin.add_child(vbox)
	panel.add_child(margin)
	return panel


func _accept_mission(mission_id: String) -> void:
	status_label.text = "Accepting mission..."
	NetworkManager.send_command("accept_mission", {"mission_id": mission_id}, func(content: Dictionary) -> void:
		status_label.text = "Mission accepted!"
		_fetch_available()
		_fetch_active()
	)


func _complete_mission(mission_id: String) -> void:
	status_label.text = "Completing mission..."
	NetworkManager.send_command("complete_mission", {"mission_id": mission_id}, func(content: Dictionary) -> void:
		var earned: int = content.get("credits_earned", 0)
		status_label.text = "Mission complete! +¢%d" % earned if earned > 0 else "Mission complete!"
		_fetch_active()
		NetworkManager.send_command("get_status", {})
	)


func _abandon_mission(mission_id: String) -> void:
	status_label.text = "Abandoning mission..."
	NetworkManager.send_command("abandon_mission", {"mission_id": mission_id}, func(content: Dictionary) -> void:
		status_label.text = "Mission abandoned."
		_fetch_active()
	)


func _set_all_disabled(disabled: bool) -> void:
	for container in [available_list, active_list]:
		if not container:
			continue
		for child in container.get_children():
			_disable_buttons_recursive(child, disabled)


func _disable_buttons_recursive(node: Node, disabled: bool) -> void:
	if node is Button:
		node.disabled = disabled
	for child in node.get_children():
		_disable_buttons_recursive(child, disabled)
