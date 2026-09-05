extends PanelContainer
class_name InfoPanel

## Info panel -- Notes (player-created), persistent Action Log, and Help tabs.
## Notes are fetched from the server and can be created/deleted.
## Action Log is the server-side persistent history (not the session event log).
## Help shows in-game documentation fetched from the server.

@onready var tab_container: TabContainer = %InfoTabs
@onready var status_label: Label = %InfoStatus

# Notes tab
@onready var notes_list: VBoxContainer = %NotesList
@onready var new_note_btn: Button = %NewNoteButton

# Log tab
@onready var log_list: VBoxContainer = %LogList
@onready var category_filter: OptionButton = %LogCategoryFilter
@onready var load_more_btn: Button = %LoadMoreButton

# Help tab
@onready var help_text: RichTextLabel = %HelpText

var _notes: Array = []
var _log_entries: Array = []
var _log_page: int = 1
var _log_has_more: bool = false
var _log_category: String = ""
var _help_loaded: bool = false

const LOG_PAGE_SIZE := 20
const LOG_CATEGORIES := ["All", "Combat", "Trading", "Mining", "Crafting", "Travel", "Social", "System"]


func _ready() -> void:
	NetworkManager.request_started.connect(_lock_ui)
	NetworkManager.request_completed.connect(_unlock_ui)
	tab_container.tab_changed.connect(_on_tab_changed)

	new_note_btn.pressed.connect(_show_create_note_dialog)
	load_more_btn.pressed.connect(_load_more_log)
	category_filter.item_selected.connect(_on_category_selected)

	_setup_category_filter()
	_fetch_notes()


func _on_tab_changed(tab: int) -> void:
	match tab:
		0: _fetch_notes()
		1: _reset_and_fetch_log()
		2: _fetch_help()


# ---------------------------------------------------------------------------
# Notes tab
# ---------------------------------------------------------------------------

func _fetch_notes() -> void:
	status_label.text = "Loading notes..."
	NetworkManager.send_social_command("get_notes", {}, func(content: Dictionary) -> void:
		_notes = content.get("notes", [])
		_refresh_notes()
		status_label.text = "%d note%s" % [_notes.size(), "" if _notes.size() == 1 else "s"]
	)


func _refresh_notes() -> void:
	for child in notes_list.get_children():
		child.queue_free()

	if _notes.is_empty():
		var empty := Label.new()
		empty.text = "No notes yet. Create one to get started."
		empty.add_theme_font_size_override("font_size", 12)
		empty.modulate = ThemeColors.TEXT_MUTED
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		notes_list.add_child(empty)
		return

	for note in _notes:
		var card := _make_note_card(note)
		notes_list.add_child(card)


func _make_note_card(note: Dictionary) -> PanelContainer:
	var panel := PanelContainer.new()

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 6)
	margin.add_theme_constant_override("margin_right", 6)
	margin.add_theme_constant_override("margin_top", 4)
	margin.add_theme_constant_override("margin_bottom", 4)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)

	# Title row with delete button
	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 4)

	var title_label := Label.new()
	title_label.text = note.get("title", "Untitled")
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_label.add_theme_font_size_override("font_size", 13)
	title_label.modulate = ThemeColors.PLASMA_CYAN
	title_row.add_child(title_label)

	var created_at: String = note.get("created_at", "")
	if not created_at.is_empty():
		var time_label := Label.new()
		time_label.text = _format_timestamp(created_at)
		time_label.add_theme_font_size_override("font_size", 10)
		time_label.modulate = ThemeColors.TEXT_MUTED
		title_row.add_child(time_label)

	var delete_btn := Button.new()
	delete_btn.text = "X"
	delete_btn.add_theme_font_size_override("font_size", 10)
	delete_btn.custom_minimum_size.x = 24
	delete_btn.modulate = ThemeColors.CLAW_RED
	var note_id: String = note.get("id", "")
	delete_btn.pressed.connect(func(): _delete_note(note_id))
	title_row.add_child(delete_btn)

	vbox.add_child(title_row)

	# Content preview
	var content_text: String = note.get("content", "")
	if not content_text.is_empty():
		var preview := Label.new()
		# Show first 100 chars as preview
		if content_text.length() > 100:
			preview.text = content_text.substr(0, 100) + "..."
		else:
			preview.text = content_text
		preview.add_theme_font_size_override("font_size", 11)
		preview.modulate = ThemeColors.CHROME_SILVER
		preview.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		vbox.add_child(preview)

	margin.add_child(vbox)
	panel.add_child(margin)
	return panel


func _show_create_note_dialog() -> void:
	var dialog := AcceptDialog.new()
	dialog.title = "New Note"
	dialog.size = Vector2i(360, 240)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)

	# Title field
	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 8)
	var title_lbl := Label.new()
	title_lbl.text = "Title:"
	title_lbl.custom_minimum_size.x = 60
	title_lbl.add_theme_font_size_override("font_size", 12)
	title_row.add_child(title_lbl)
	var title_input := LineEdit.new()
	title_input.placeholder_text = "Note title..."
	title_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_input.add_theme_font_size_override("font_size", 12)
	title_row.add_child(title_input)
	vbox.add_child(title_row)

	# Content field
	var content_lbl := Label.new()
	content_lbl.text = "Content:"
	content_lbl.add_theme_font_size_override("font_size", 12)
	vbox.add_child(content_lbl)

	var content_input := TextEdit.new()
	content_input.placeholder_text = "Write your note here..."
	content_input.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content_input.custom_minimum_size.y = 100
	content_input.add_theme_font_size_override("font_size", 12)
	vbox.add_child(content_input)

	dialog.add_child(vbox)

	dialog.confirmed.connect(func():
		var note_title := title_input.text.strip_edges()
		var note_content := content_input.text.strip_edges()
		if note_title.is_empty():
			status_label.text = "Title is required."
			dialog.queue_free()
			return
		_create_note(note_title, note_content)
		dialog.queue_free()
	)
	dialog.canceled.connect(func(): dialog.queue_free())

	add_child(dialog)
	dialog.popup_centered()


func _create_note(title: String, content: String) -> void:
	status_label.text = "Creating note..."
	NetworkManager.send_social_command("create_note", {"title": title, "content": content}, func(_content: Dictionary) -> void:
		status_label.text = "Note created."
		_fetch_notes()
	)


func _delete_note(note_id: String) -> void:
	status_label.text = "Deleting note..."
	NetworkManager.send_social_command("delete_note", {"target": note_id}, func(_content: Dictionary) -> void:
		status_label.text = "Note deleted."
		_fetch_notes()
	)


# ---------------------------------------------------------------------------
# Action Log tab
# ---------------------------------------------------------------------------

func _setup_category_filter() -> void:
	category_filter.clear()
	for cat in LOG_CATEGORIES:
		category_filter.add_item(cat)


func _on_category_selected(idx: int) -> void:
	_log_category = "" if idx == 0 else LOG_CATEGORIES[idx].to_lower()
	_reset_and_fetch_log()


func _reset_and_fetch_log() -> void:
	_log_page = 1
	_log_entries.clear()
	_fetch_log()


func _fetch_log() -> void:
	status_label.text = "Loading action log..."
	var params := {"page": _log_page, "page_size": LOG_PAGE_SIZE}
	if not _log_category.is_empty():
		params["category"] = _log_category
	NetworkManager.send_social_command("get_action_log", params, func(content: Dictionary) -> void:
		var new_entries: Array = content.get("entries", [])
		if _log_page == 1:
			_log_entries = new_entries
		else:
			_log_entries.append_array(new_entries)
		_log_has_more = content.get("has_more", false)
		_refresh_log()
		status_label.text = "%d entr%s" % [_log_entries.size(), "y" if _log_entries.size() == 1 else "ies"]
	)


func _load_more_log() -> void:
	_log_page += 1
	_fetch_log()


func _refresh_log() -> void:
	for child in log_list.get_children():
		child.queue_free()

	if _log_entries.is_empty():
		var empty := Label.new()
		empty.text = "No log entries found."
		empty.add_theme_font_size_override("font_size", 12)
		empty.modulate = ThemeColors.TEXT_MUTED
		log_list.add_child(empty)
		load_more_btn.visible = false
		return

	# Header
	var header := _make_header(["TIME", "TYPE", "EVENT"])
	log_list.add_child(header)

	for entry in _log_entries:
		var row := _make_log_entry_row(entry)
		log_list.add_child(row)

	load_more_btn.visible = _log_has_more
	load_more_btn.text = "Load More"


static func _make_log_entry_row(entry: Dictionary) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)

	# Timestamp
	var ts: String = entry.get("created_at", entry.get("timestamp", ""))
	var time_label := Label.new()
	time_label.text = _format_timestamp(ts)
	time_label.custom_minimum_size.x = 50
	time_label.add_theme_font_size_override("font_size", 11)
	time_label.modulate = ThemeColors.TEXT_MUTED
	row.add_child(time_label)

	# Category tag
	var category: String = entry.get("category", entry.get("type", "system"))
	var cat_label := Label.new()
	cat_label.text = "[%s]" % category.to_upper()
	cat_label.custom_minimum_size.x = 65
	cat_label.add_theme_font_size_override("font_size", 10)
	cat_label.modulate = _get_category_color(category)
	row.add_child(cat_label)

	# Message
	var msg_label := Label.new()
	msg_label.text = entry.get("summary", entry.get("message", ""))
	msg_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	msg_label.add_theme_font_size_override("font_size", 12)
	msg_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(msg_label)

	return row


static func _get_category_color(category: String) -> Color:
	match category.to_lower():
		"combat": return ThemeColors.CAT_COMBAT
		"trading", "trade": return ThemeColors.CAT_TRADE
		"mining": return ThemeColors.SHELL_ORANGE
		"crafting": return ThemeColors.WARNING_YELLOW
		"travel", "navigation": return ThemeColors.CAT_NAVIGATION
		"social": return ThemeColors.CAT_SOCIAL
		"system": return ThemeColors.CAT_SYSTEM
		_: return ThemeColors.CAT_DEFAULT


# ---------------------------------------------------------------------------
# Help tab
# ---------------------------------------------------------------------------

func _fetch_help() -> void:
	if _help_loaded:
		return
	status_label.text = "Loading help..."
	NetworkManager.send_command("help", {}, func(content: Dictionary) -> void:
		var text: String = content.get("text", "No help available.")
		help_text.text = text
		_help_loaded = true
		status_label.text = "Help loaded."
	)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

static func _format_timestamp(ts: String) -> String:
	if ts.is_empty():
		return "--:--"
	# Try to extract just hours:minutes from an ISO timestamp
	# e.g. "2026-04-11T14:30:00Z" -> "14:30"
	var t_pos := ts.find("T")
	if t_pos >= 0 and ts.length() > t_pos + 5:
		return ts.substr(t_pos + 1, 5)
	# Fallback: return last 5 chars or the whole thing
	if ts.length() >= 5:
		return ts.right(5)
	return ts


static func _make_header(cols: Array) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	for i in cols.size():
		var lbl := Label.new()
		lbl.text = cols[i]
		lbl.add_theme_font_size_override("font_size", 10)
		lbl.modulate = ThemeColors.HULL_GREY
		if cols[i] == "TIME":
			lbl.custom_minimum_size.x = 50
		elif cols[i] == "TYPE":
			lbl.custom_minimum_size.x = 65
		else:
			lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(lbl)
	return row


func _lock_ui() -> void:
	_set_buttons_disabled(true)


func _unlock_ui() -> void:
	_set_buttons_disabled(false)


func _set_buttons_disabled(disabled: bool) -> void:
	if new_note_btn:
		new_note_btn.disabled = disabled
	if load_more_btn:
		load_more_btn.disabled = disabled

	for container in [notes_list, log_list]:
		if not container:
			continue
		for child in container.get_children():
			_disable_buttons_recursive(child, disabled)


func _disable_buttons_recursive(node: Node, disabled: bool) -> void:
	if node is Button:
		node.disabled = disabled
	for child in node.get_children():
		_disable_buttons_recursive(child, disabled)
