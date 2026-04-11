extends PanelContainer
class_name FactionPanel

## Faction panel — four tabs: Info, Members, Intel, Invites.
## Shows faction details, member management, intel entries, and pending invitations.

@onready var tab_container: TabContainer = %FactionTabs
@onready var status_label: Label = %FactionStatus

# Info tab
@onready var info_list: VBoxContainer = %InfoList

# Members tab
@onready var members_list: VBoxContainer = %MembersList

# Intel tab
@onready var intel_list: VBoxContainer = %IntelList
@onready var intel_search: LineEdit = %IntelSearch

# Invites tab
@onready var invites_list: VBoxContainer = %InvitesList

var _faction_data: Dictionary = {}
var _members: Array = []
var _intel_entries: Array = []
var _invites: Array = []


func _ready() -> void:
	NetworkManager.request_started.connect(_lock_ui)
	NetworkManager.request_completed.connect(_unlock_ui)
	tab_container.tab_changed.connect(_on_tab_changed)
	intel_search.text_submitted.connect(_on_intel_search_submitted)

	_fetch_faction_info()
	_fetch_invites()


func _on_tab_changed(tab: int) -> void:
	match tab:
		0: _refresh_info()
		1: _refresh_members()
		2: _refresh_intel()
		3: _refresh_invites()


# ---------------------------------------------------------------------------
# Info tab
# ---------------------------------------------------------------------------

func _fetch_faction_info() -> void:
	status_label.text = "Loading..."
	NetworkManager.send_command("faction_info", {}, func(content: Dictionary) -> void:
		_faction_data = content.get("faction", {})
		_members = _faction_data.get("members", [])
		_refresh_info()
		_refresh_members()
		if _faction_data.is_empty():
			status_label.text = "No faction"
		else:
			status_label.text = _faction_data.get("name", "Faction")
	)


func _refresh_info() -> void:
	for child in info_list.get_children():
		child.queue_free()

	if _faction_data.is_empty() or not _faction_data.has("name"):
		_build_no_faction_view()
		return

	_build_faction_info_view()


func _build_no_faction_view() -> void:
	var msg := Label.new()
	msg.text = "You are not in a faction."
	msg.add_theme_font_size_override("font_size", 12)
	msg.modulate = ThemeColors.TEXT_MUTED
	info_list.add_child(msg)

	var spacer := Control.new()
	spacer.custom_minimum_size.y = 8
	info_list.add_child(spacer)

	# Create faction section
	var create_label := Label.new()
	create_label.text = "CREATE FACTION"
	create_label.add_theme_font_size_override("font_size", 10)
	create_label.modulate = ThemeColors.HULL_GREY
	info_list.add_child(create_label)

	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 4)

	var name_lbl := Label.new()
	name_lbl.text = "Name:"
	name_lbl.custom_minimum_size.x = 40
	name_lbl.add_theme_font_size_override("font_size", 12)
	name_row.add_child(name_lbl)

	var name_field := LineEdit.new()
	name_field.placeholder_text = "Faction name"
	name_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_field.add_theme_font_size_override("font_size", 12)
	name_row.add_child(name_field)
	info_list.add_child(name_row)

	var tag_row := HBoxContainer.new()
	tag_row.add_theme_constant_override("separation", 4)

	var tag_lbl := Label.new()
	tag_lbl.text = "Tag:"
	tag_lbl.custom_minimum_size.x = 40
	tag_lbl.add_theme_font_size_override("font_size", 12)
	tag_row.add_child(tag_lbl)

	var tag_field := LineEdit.new()
	tag_field.placeholder_text = "4-char tag"
	tag_field.max_length = 4
	tag_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tag_field.add_theme_font_size_override("font_size", 12)
	tag_row.add_child(tag_field)
	info_list.add_child(tag_row)

	var create_btn := Button.new()
	create_btn.text = "Create Faction"
	create_btn.add_theme_font_size_override("font_size", 10)
	create_btn.pressed.connect(func():
		var fname: String = name_field.text.strip_edges()
		var ftag: String = tag_field.text.strip_edges()
		if fname.is_empty() or ftag.is_empty():
			status_label.text = "Name and tag required."
			return
		_create_faction(fname, ftag)
	)
	info_list.add_child(create_btn)

	var spacer2 := Control.new()
	spacer2.custom_minimum_size.y = 8
	info_list.add_child(spacer2)

	# Invites hint
	var hint := Label.new()
	hint.text = "Check the Invites tab for pending invitations."
	hint.add_theme_font_size_override("font_size", 11)
	hint.modulate = ThemeColors.CHROME_SILVER
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info_list.add_child(hint)


func _build_faction_info_view() -> void:
	# Faction name + tag
	var name_label := Label.new()
	name_label.text = "%s [%s]" % [
		_faction_data.get("name", "Unknown"),
		_faction_data.get("tag", "????"),
	]
	name_label.add_theme_font_size_override("font_size", 14)
	name_label.modulate = ThemeColors.PLASMA_CYAN
	info_list.add_child(name_label)

	# Member count
	var count_label := Label.new()
	count_label.text = "Members: %d" % _members.size()
	count_label.add_theme_font_size_override("font_size", 12)
	count_label.modulate = ThemeColors.CHROME_SILVER
	info_list.add_child(count_label)

	# Leader
	var leader_name := ""
	for m in _members:
		if m.get("rank", "") == "leader":
			leader_name = m.get("username", "Unknown")
			break
	if not leader_name.is_empty():
		var leader_label := Label.new()
		leader_label.text = "Leader: %s" % leader_name
		leader_label.add_theme_font_size_override("font_size", 12)
		leader_label.modulate = ThemeColors.CHROME_SILVER
		info_list.add_child(leader_label)

	# Description if present
	var desc: String = _faction_data.get("description", "")
	if not desc.is_empty():
		var spacer := Control.new()
		spacer.custom_minimum_size.y = 4
		info_list.add_child(spacer)
		var desc_label := Label.new()
		desc_label.text = desc
		desc_label.add_theme_font_size_override("font_size", 11)
		desc_label.modulate = ThemeColors.CHROME_SILVER
		desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		info_list.add_child(desc_label)

	# Invite player row
	var spacer := Control.new()
	spacer.custom_minimum_size.y = 8
	info_list.add_child(spacer)

	if _is_leader():
		var invite_header := Label.new()
		invite_header.text = "INVITE PLAYER"
		invite_header.add_theme_font_size_override("font_size", 10)
		invite_header.modulate = ThemeColors.HULL_GREY
		info_list.add_child(invite_header)

		var invite_row := HBoxContainer.new()
		invite_row.add_theme_constant_override("separation", 4)

		var invite_field := LineEdit.new()
		invite_field.placeholder_text = "Player ID"
		invite_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		invite_field.add_theme_font_size_override("font_size", 12)
		invite_row.add_child(invite_field)

		var invite_btn := Button.new()
		invite_btn.text = "Invite"
		invite_btn.add_theme_font_size_override("font_size", 10)
		invite_btn.custom_minimum_size.x = 50
		invite_btn.pressed.connect(func():
			var pid: String = invite_field.text.strip_edges()
			if pid.is_empty():
				status_label.text = "Enter a player ID."
				return
			_invite_player(pid)
		)
		invite_row.add_child(invite_btn)
		info_list.add_child(invite_row)

	# Leave faction button
	var spacer2 := Control.new()
	spacer2.custom_minimum_size.y = 8
	info_list.add_child(spacer2)

	var leave_btn := Button.new()
	leave_btn.text = "Leave Faction"
	leave_btn.add_theme_font_size_override("font_size", 10)
	leave_btn.modulate = ThemeColors.CLAW_RED
	leave_btn.pressed.connect(_on_leave_pressed)
	info_list.add_child(leave_btn)


func _create_faction(faction_name: String, tag: String) -> void:
	status_label.text = "Creating faction..."
	NetworkManager.send_command("create_faction", {"name": faction_name, "tag": tag}, func(_content: Dictionary) -> void:
		status_label.text = "Faction created!"
		NetworkManager.send_command("get_status", {}, func(_c): pass)
		_fetch_faction_info()
	)


func _invite_player(player_id: String) -> void:
	status_label.text = "Sending invite..."
	NetworkManager.send_command("faction_invite", {"player_id": player_id}, func(_content: Dictionary) -> void:
		status_label.text = "Invite sent."
	)


func _on_leave_pressed() -> void:
	status_label.text = "Leaving faction..."
	NetworkManager.send_command("leave_faction", {}, func(_content: Dictionary) -> void:
		status_label.text = "Left faction."
		_faction_data = {}
		_members = []
		NetworkManager.send_command("get_status", {}, func(_c): pass)
		_refresh_info()
		_refresh_members()
	)


# ---------------------------------------------------------------------------
# Members tab
# ---------------------------------------------------------------------------

func _refresh_members() -> void:
	for child in members_list.get_children():
		child.queue_free()

	if _members.is_empty():
		var empty := Label.new()
		empty.text = "No members."
		empty.add_theme_font_size_override("font_size", 12)
		empty.modulate = ThemeColors.TEXT_MUTED
		members_list.add_child(empty)
		return

	# Header
	members_list.add_child(_make_header(["PLAYER", "RANK", ""]))

	for member in _members:
		var username: String = member.get("username", "Unknown")
		var rank: String = member.get("rank", "member")
		var member_id: String = member.get("player_id", "")

		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)

		var name_lbl := Label.new()
		name_lbl.text = username
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_lbl.add_theme_font_size_override("font_size", 12)
		row.add_child(name_lbl)

		var rank_lbl := Label.new()
		rank_lbl.text = rank.capitalize()
		rank_lbl.custom_minimum_size.x = 55
		rank_lbl.add_theme_font_size_override("font_size", 11)
		rank_lbl.modulate = ThemeColors.WARNING_YELLOW if rank == "leader" else ThemeColors.CHROME_SILVER
		row.add_child(rank_lbl)

		# Kick button (only for leader, and not for yourself)
		if _is_leader() and member_id != StateManager.player.get("id", ""):
			var kick_btn := Button.new()
			kick_btn.text = "Kick"
			kick_btn.add_theme_font_size_override("font_size", 10)
			kick_btn.custom_minimum_size.x = 40
			kick_btn.modulate = ThemeColors.CLAW_RED
			kick_btn.pressed.connect(_on_kick_pressed.bind(member_id, username))
			row.add_child(kick_btn)
		else:
			# Spacer to keep alignment
			var spacer := Control.new()
			spacer.custom_minimum_size.x = 40
			row.add_child(spacer)

		members_list.add_child(row)


func _on_kick_pressed(player_id: String, username: String) -> void:
	status_label.text = "Kicking %s..." % username
	NetworkManager.send_command("faction_kick", {"player_id": player_id}, func(_content: Dictionary) -> void:
		status_label.text = "Kicked %s." % username
		_fetch_faction_info()
	)


# ---------------------------------------------------------------------------
# Intel tab
# ---------------------------------------------------------------------------

func _on_intel_search_submitted(text: String) -> void:
	_fetch_intel(text.strip_edges())


func _fetch_intel(system_name: String = "") -> void:
	status_label.text = "Loading intel..."
	var params := {}
	if not system_name.is_empty():
		params["system_name"] = system_name
	NetworkManager.send_command("faction_query_intel", params, func(content: Dictionary) -> void:
		_intel_entries = content.get("entries", [])
		_refresh_intel()
		status_label.text = "%d intel entries" % _intel_entries.size()
	)


func _refresh_intel() -> void:
	for child in intel_list.get_children():
		child.queue_free()

	if _intel_entries.is_empty():
		var empty := Label.new()
		empty.text = "No intel entries found."
		empty.add_theme_font_size_override("font_size", 12)
		empty.modulate = ThemeColors.TEXT_MUTED
		intel_list.add_child(empty)
		return

	intel_list.add_child(_make_header(["SYSTEM", "TYPE", "AGE"]))

	for entry in _intel_entries:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)

		var sys_lbl := Label.new()
		sys_lbl.text = entry.get("system_name", entry.get("system_id", "Unknown"))
		sys_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sys_lbl.add_theme_font_size_override("font_size", 12)
		row.add_child(sys_lbl)

		var type_lbl := Label.new()
		type_lbl.text = entry.get("type", entry.get("intel_type", "general"))
		type_lbl.custom_minimum_size.x = 55
		type_lbl.add_theme_font_size_override("font_size", 11)
		type_lbl.modulate = ThemeColors.CHROME_SILVER
		row.add_child(type_lbl)

		var age_lbl := Label.new()
		age_lbl.text = entry.get("age", entry.get("timestamp", ""))
		age_lbl.custom_minimum_size.x = 45
		age_lbl.add_theme_font_size_override("font_size", 11)
		age_lbl.modulate = ThemeColors.TEXT_MUTED
		row.add_child(age_lbl)

		intel_list.add_child(row)


# ---------------------------------------------------------------------------
# Invites tab
# ---------------------------------------------------------------------------

func _fetch_invites() -> void:
	NetworkManager.send_command("faction_get_invites", {}, func(content: Dictionary) -> void:
		_invites = content.get("invites", [])
		_refresh_invites()
	)


func _refresh_invites() -> void:
	for child in invites_list.get_children():
		child.queue_free()

	if _invites.is_empty():
		var empty := Label.new()
		empty.text = "No pending invitations."
		empty.add_theme_font_size_override("font_size", 12)
		empty.modulate = ThemeColors.TEXT_MUTED
		invites_list.add_child(empty)
		return

	invites_list.add_child(_make_header(["FACTION", "", ""]))

	for invite in _invites:
		var faction_name: String = invite.get("faction_name", "Unknown")
		var faction_id: String = invite.get("faction_id", "")

		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)

		var name_lbl := Label.new()
		name_lbl.text = faction_name
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_lbl.add_theme_font_size_override("font_size", 12)
		row.add_child(name_lbl)

		var accept_btn := Button.new()
		accept_btn.text = "Join"
		accept_btn.add_theme_font_size_override("font_size", 10)
		accept_btn.custom_minimum_size.x = 40
		accept_btn.pressed.connect(_on_accept_invite.bind(faction_id, faction_name))
		row.add_child(accept_btn)

		var decline_btn := Button.new()
		decline_btn.text = "X"
		decline_btn.add_theme_font_size_override("font_size", 10)
		decline_btn.custom_minimum_size.x = 30
		decline_btn.modulate = ThemeColors.CLAW_RED
		decline_btn.pressed.connect(_on_decline_invite.bind(faction_id, faction_name))
		row.add_child(decline_btn)

		invites_list.add_child(row)


func _on_accept_invite(faction_id: String, faction_name: String) -> void:
	status_label.text = "Joining %s..." % faction_name
	NetworkManager.send_command("join_faction", {"faction_id": faction_id}, func(_content: Dictionary) -> void:
		status_label.text = "Joined %s!" % faction_name
		NetworkManager.send_command("get_status", {}, func(_c): pass)
		_fetch_faction_info()
		_fetch_invites()
	)


func _on_decline_invite(faction_id: String, faction_name: String) -> void:
	status_label.text = "Declining..."
	NetworkManager.send_command("faction_decline_invite", {"faction_id": faction_id}, func(_content: Dictionary) -> void:
		status_label.text = "Declined %s." % faction_name
		_fetch_invites()
	)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _is_leader() -> bool:
	var my_id: String = StateManager.player.get("id", "")
	for m in _members:
		if m.get("player_id", "") == my_id and m.get("rank", "") == "leader":
			return true
	return false


## Build a list of members from faction data for external use (e.g. tests).
static func get_parsed_members(faction_data: Dictionary) -> Array:
	return faction_data.get("members", [])


## Determine if a given player_id is the faction leader from faction data.
static func is_player_leader(faction_data: Dictionary, player_id: String) -> bool:
	for m in faction_data.get("members", []):
		if m.get("player_id", "") == player_id and m.get("rank", "") == "leader":
			return true
	return false


## Determine visibility state: returns "no_faction" or "has_faction".
static func get_view_state(faction_data: Dictionary) -> String:
	if faction_data.is_empty() or not faction_data.has("name"):
		return "no_faction"
	return "has_faction"


func _make_header(cols: Array) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	for i in cols.size():
		var lbl := Label.new()
		lbl.text = cols[i]
		lbl.add_theme_font_size_override("font_size", 10)
		lbl.modulate = ThemeColors.HULL_GREY
		if i == 0:
			lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		elif cols[i].is_empty():
			lbl.custom_minimum_size.x = 40
		else:
			lbl.custom_minimum_size.x = 55
		row.add_child(lbl)
	return row


func _lock_ui() -> void:
	_set_buttons_disabled(true)


func _unlock_ui() -> void:
	_set_buttons_disabled(false)


func _set_buttons_disabled(disabled: bool) -> void:
	for container in [info_list, members_list, intel_list, invites_list]:
		if not container:
			continue
		for child in container.get_children():
			_disable_buttons_recursive(child, disabled)


func _disable_buttons_recursive(node: Node, disabled: bool) -> void:
	if node is Button:
		node.disabled = disabled
	for child in node.get_children():
		_disable_buttons_recursive(child, disabled)
