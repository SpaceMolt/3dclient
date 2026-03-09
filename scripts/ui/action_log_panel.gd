extends PanelContainer

## Action Log panel — shows the player's recent action history from the server.

@onready var category_filter: OptionButton = %CategoryFilter
@onready var entries_list: VBoxContainer = %EntriesList
@onready var load_more_button: Button = %LoadMoreButton
@onready var status_label: Label = %ActionLogStatus

const CATEGORY_MAP := {
	0: "",           # All
	1: "combat",
	2: "trading",
	3: "mining",
	4: "navigation",
	5: "social",
}

const CATEGORY_COLORS := {
	"combat": Color(1.0, 0.3, 0.3),
	"trading": Color(1.0, 0.84, 0.0),
	"mining": Color(1.0, 0.6, 0.2),
	"navigation": Color(0.4, 0.9, 1.0),
	"social": Color(0.4, 1.0, 0.5),
}

const CATEGORY_TAGS := {
	"combat": "[CMB]",
	"trading": "[TRD]",
	"mining": "[MIN]",
	"navigation": "[NAV]",
	"social": "[SOC]",
}

var _entries: Array = []
var _has_more: bool = false
var _current_category: String = ""


func _ready() -> void:
	category_filter.item_selected.connect(_on_category_selected)
	load_more_button.pressed.connect(_load_more)
	load_more_button.hide()

	# Set up category options
	category_filter.add_item("All")
	category_filter.add_item("Combat")
	category_filter.add_item("Trading")
	category_filter.add_item("Mining")
	category_filter.add_item("Navigation")
	category_filter.add_item("Social")

	_fetch_entries()


func _on_category_selected(idx: int) -> void:
	_current_category = CATEGORY_MAP.get(idx, "")
	_entries.clear()
	_fetch_entries()


func _fetch_entries() -> void:
	status_label.text = "Loading..."
	var params := {"limit": 25}
	if not _current_category.is_empty():
		params["category"] = _current_category

	NetworkManager.send_social_command("get_action_log", params, func(content: Dictionary) -> void:
		_entries = content.get("entries", [])
		_has_more = content.get("has_more", false)
		_refresh_list()
		status_label.text = "%d entries" % _entries.size() if not _entries.is_empty() else ""
	)


func _load_more() -> void:
	if _entries.is_empty():
		return

	var last_id: String = str(_entries[-1].get("id", ""))
	var params := {"limit": 25, "before_id": last_id}
	if not _current_category.is_empty():
		params["category"] = _current_category

	status_label.text = "Loading more..."
	NetworkManager.send_social_command("get_action_log", params, func(content: Dictionary) -> void:
		var new_entries: Array = content.get("entries", [])
		_entries.append_array(new_entries)
		_has_more = content.get("has_more", false)
		_refresh_list()
		status_label.text = "%d entries" % _entries.size()
	)


func _refresh_list() -> void:
	for child in entries_list.get_children():
		child.queue_free()

	if _entries.is_empty():
		var empty := Label.new()
		empty.text = "No actions recorded."
		empty.add_theme_font_size_override("font_size", 12)
		empty.modulate = Color(0.5, 0.5, 0.5)
		entries_list.add_child(empty)
		load_more_button.hide()
		return

	for entry in _entries:
		var row := _make_entry_row(entry)
		entries_list.add_child(row)

	load_more_button.visible = _has_more


func _make_entry_row(entry: Dictionary) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)

	# Timestamp — extract just the time portion
	var time_str := _format_time(entry.get("created_at", ""))
	var time_label := Label.new()
	time_label.text = time_str
	time_label.add_theme_font_size_override("font_size", 11)
	time_label.modulate = Color(0.5, 0.5, 0.5)
	time_label.custom_minimum_size.x = 50
	row.add_child(time_label)

	# Category tag
	var category: String = entry.get("category", "").to_lower()
	var tag_label := Label.new()
	tag_label.text = CATEGORY_TAGS.get(category, "[???]")
	tag_label.add_theme_font_size_override("font_size", 11)
	tag_label.modulate = CATEGORY_COLORS.get(category, Color(0.6, 0.6, 0.6))
	tag_label.custom_minimum_size.x = 40
	row.add_child(tag_label)

	# Summary text
	var summary_label := Label.new()
	summary_label.text = entry.get("summary", "")
	summary_label.add_theme_font_size_override("font_size", 12)
	summary_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	summary_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(summary_label)

	return row


func _format_time(timestamp: String) -> String:
	# Expect ISO 8601 like "2026-03-08T14:30:00Z" — extract HH:MM
	if timestamp.is_empty():
		return "--:--"
	var t_idx := timestamp.find("T")
	if t_idx < 0:
		# Try space-separated "2026-03-08 14:30:00"
		t_idx = timestamp.find(" ")
	if t_idx < 0 or t_idx + 6 > timestamp.length():
		return timestamp.left(5)
	return timestamp.substr(t_idx + 1, 5)
