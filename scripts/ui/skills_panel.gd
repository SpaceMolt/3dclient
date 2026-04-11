extends PanelContainer

## Skills panel — shows all player skills with XP progress, level, and
## expandable details. Fetches the full skill catalog from the server and
## merges it with player skill data from StateManager.

@onready var skills_list: VBoxContainer = %SkillsList
@onready var search_field: LineEdit = %SkillSearch
@onready var category_filter: OptionButton = %SkillCategoryFilter
@onready var status_label: Label = %SkillsStatus

var _catalog: Array = []
var _player_skills: Dictionary = {}
var _categories: Array = []
var _expanded_skill: String = ""  # skill id currently expanded, or ""


func _ready() -> void:
	NetworkManager.request_started.connect(func(): _set_buttons_disabled(true))
	NetworkManager.request_completed.connect(func(): _set_buttons_disabled(false))
	StateManager.state_updated.connect(_on_state_updated)
	search_field.text_changed.connect(_on_search_changed)
	category_filter.item_selected.connect(_on_category_selected)
	_sync_player_skills()
	_fetch_catalog()


func _on_state_updated() -> void:
	_sync_player_skills()
	_refresh()


func _on_search_changed(_text: String) -> void:
	_refresh()


func _on_category_selected(_idx: int) -> void:
	_refresh()


# ---------------------------------------------------------------------------
# Data
# ---------------------------------------------------------------------------

func _sync_player_skills() -> void:
	_player_skills = _normalize_skills(StateManager.skills)


func _fetch_catalog() -> void:
	status_label.text = "Loading skills..."
	NetworkManager.send_catalog_command({"type": "skills", "page": 1, "page_size": 50}, func(content: Dictionary) -> void:
		_catalog = content.get("items", [])
		_extract_categories()
		_setup_category_filter()
		_refresh()
		status_label.text = "%d skills" % _catalog.size()
	)


func _extract_categories() -> void:
	var seen: Dictionary = {}
	for skill in _catalog:
		var cat: String = skill.get("category", "")
		if not cat.is_empty() and not seen.has(cat):
			seen[cat] = true
			_categories.append(cat)
	_categories.sort()


func _setup_category_filter() -> void:
	category_filter.clear()
	category_filter.add_item("All Categories")
	for cat in _categories:
		category_filter.add_item(cat)


# ---------------------------------------------------------------------------
# Rendering
# ---------------------------------------------------------------------------

func _refresh() -> void:
	for child in skills_list.get_children():
		child.queue_free()

	var search_text: String = search_field.text.to_lower() if search_field else ""
	var selected_cat: String = ""
	if category_filter and category_filter.selected > 0:
		selected_cat = category_filter.get_item_text(category_filter.selected)

	# Build a merged list: catalog skills enriched with player progress
	var entries: Array = _build_display_entries()

	# Filter
	var visible_count := 0
	for entry in entries:
		var skill_name: String = entry.get("name", "")
		var skill_cat: String = entry.get("category", "")

		if not search_text.is_empty() and skill_name.to_lower().find(search_text) == -1:
			continue
		if not selected_cat.is_empty() and skill_cat != selected_cat:
			continue

		var row := _make_skill_row(entry)
		skills_list.add_child(row)

		# Expandable detail area
		var skill_id: String = entry.get("id", entry.get("name", ""))
		if _expanded_skill == skill_id:
			var detail := _make_skill_detail(entry)
			skills_list.add_child(detail)

		visible_count += 1

	if visible_count == 0:
		var empty := Label.new()
		if entries.is_empty():
			empty.text = "No skills data available."
		else:
			empty.text = "No skills match filter."
		empty.add_theme_font_size_override("font_size", 12)
		empty.modulate = ThemeColors.TEXT_MUTED
		skills_list.add_child(empty)


func _build_display_entries() -> Array:
	# If we have a catalog, merge with player data
	if not _catalog.is_empty():
		var entries: Array = []
		for skill in _catalog:
			var sid: String = skill.get("id", skill.get("name", ""))
			var entry: Dictionary = skill.duplicate()
			if _player_skills.has(sid):
				entry.merge(_player_skills[sid], true)
				entry["trained"] = true
			else:
				entry["trained"] = false
				entry["level"] = 0
				entry["xp"] = 0
				entry["next_level_xp"] = skill.get("xp_per_level", 0)
			entries.append(entry)
		return entries

	# No catalog — fall back to player skills only
	if _player_skills.is_empty():
		return []

	var entries: Array = []
	for sid in _player_skills:
		var pdata: Dictionary = _player_skills[sid].duplicate()
		pdata["id"] = sid
		if not pdata.has("name"):
			pdata["name"] = _format_skill_name(sid)
		pdata["trained"] = true
		entries.append(pdata)
	return entries


func _make_skill_row(entry: Dictionary) -> VBoxContainer:
	var container := VBoxContainer.new()
	container.add_theme_constant_override("separation", 2)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)

	# Skill name
	var name_label := Label.new()
	name_label.text = entry.get("name", "Unknown")
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.add_theme_font_size_override("font_size", 12)
	if entry.get("trained", false):
		name_label.modulate = ThemeColors.STAR_WHITE
	else:
		name_label.modulate = ThemeColors.TEXT_MUTED
	row.add_child(name_label)

	# Level
	var level: int = entry.get("level", 0)
	var max_level: int = entry.get("max_level", 0)
	var level_label := Label.new()
	if max_level > 0:
		level_label.text = "Lv %d/%d" % [level, max_level]
	else:
		level_label.text = "Lv %d" % level
	level_label.custom_minimum_size.x = 55
	level_label.add_theme_font_size_override("font_size", 11)
	level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	if level > 0 and max_level > 0 and level >= max_level:
		level_label.modulate = ThemeColors.BIO_GREEN
	elif level > 0:
		level_label.modulate = ThemeColors.PLASMA_CYAN
	else:
		level_label.modulate = ThemeColors.TEXT_MUTED
	row.add_child(level_label)

	# Expand/collapse button
	var skill_id: String = entry.get("id", entry.get("name", ""))
	var toggle_btn := Button.new()
	toggle_btn.text = "v" if _expanded_skill != skill_id else "^"
	toggle_btn.add_theme_font_size_override("font_size", 10)
	toggle_btn.custom_minimum_size.x = 24
	toggle_btn.pressed.connect(_on_toggle_detail.bind(skill_id))
	row.add_child(toggle_btn)

	container.add_child(row)

	# XP progress bar (only if skill has progress)
	var xp: float = float(entry.get("xp", 0))
	var next_xp: float = float(entry.get("next_level_xp", 0))
	if level > 0 or xp > 0:
		var bar_row := HBoxContainer.new()
		bar_row.add_theme_constant_override("separation", 4)

		var bar := ProgressBar.new()
		bar.custom_minimum_size = Vector2(120, 12)
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.show_percentage = false
		bar.value = xp_percentage(xp, next_xp)
		bar_row.add_child(bar)

		var xp_label := Label.new()
		if next_xp > 0:
			xp_label.text = "%d/%d XP" % [int(xp), int(next_xp)]
		else:
			xp_label.text = "%d XP" % int(xp)
		xp_label.custom_minimum_size.x = 80
		xp_label.add_theme_font_size_override("font_size", 10)
		xp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		xp_label.modulate = ThemeColors.CHROME_SILVER
		bar_row.add_child(xp_label)

		container.add_child(bar_row)

	return container


func _make_skill_detail(entry: Dictionary) -> MarginContainer:
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 4)
	margin.add_theme_constant_override("margin_top", 2)
	margin.add_theme_constant_override("margin_bottom", 6)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)

	# Description
	var desc: String = entry.get("description", "")
	if not desc.is_empty():
		var desc_label := Label.new()
		desc_label.text = desc
		desc_label.add_theme_font_size_override("font_size", 11)
		desc_label.modulate = ThemeColors.CHROME_SILVER
		desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		vbox.add_child(desc_label)

	# Category
	var cat: String = entry.get("category", "")
	if not cat.is_empty():
		var cat_label := Label.new()
		cat_label.text = "Category: %s" % cat
		cat_label.add_theme_font_size_override("font_size", 11)
		cat_label.modulate = ThemeColors.HULL_GREY
		vbox.add_child(cat_label)

	# Max level
	var max_level: int = entry.get("max_level", 0)
	if max_level > 0:
		var ml_label := Label.new()
		ml_label.text = "Max Level: %d" % max_level
		ml_label.add_theme_font_size_override("font_size", 11)
		ml_label.modulate = ThemeColors.HULL_GREY
		vbox.add_child(ml_label)

	# Bonus per level
	var bonus: String = entry.get("bonus_per_level", "")
	if not bonus.is_empty():
		var bonus_label := Label.new()
		bonus_label.text = "Per Level: %s" % bonus
		bonus_label.add_theme_font_size_override("font_size", 11)
		bonus_label.modulate = ThemeColors.WARNING_YELLOW
		vbox.add_child(bonus_label)

	# Prerequisites
	var prereqs = entry.get("prerequisites", null)
	if prereqs is Dictionary and not prereqs.is_empty():
		var prereq_label := Label.new()
		var parts: PackedStringArray = []
		for key in prereqs:
			parts.append("%s Lv %s" % [_format_skill_name(key), str(prereqs[key])])
		prereq_label.text = "Requires: %s" % ", ".join(parts)
		prereq_label.add_theme_font_size_override("font_size", 11)
		prereq_label.modulate = ThemeColors.HULL_GREY
		vbox.add_child(prereq_label)
	elif prereqs is Array and not prereqs.is_empty():
		var prereq_label := Label.new()
		prereq_label.text = "Requires: %s" % ", ".join(PackedStringArray(prereqs))
		prereq_label.add_theme_font_size_override("font_size", 11)
		prereq_label.modulate = ThemeColors.HULL_GREY
		vbox.add_child(prereq_label)

	# Separator line
	var sep := HSeparator.new()
	sep.modulate = ThemeColors.SEPARATOR
	vbox.add_child(sep)

	margin.add_child(vbox)
	return margin


func _on_toggle_detail(skill_id: String) -> void:
	if _expanded_skill == skill_id:
		_expanded_skill = ""
	else:
		_expanded_skill = skill_id
	_refresh()


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

## Normalize the skills data from StateManager into a consistent Dictionary
## keyed by skill id/name. Handles both dict-of-dicts and array-of-dicts.
static func _normalize_skills(raw) -> Dictionary:
	if raw is Dictionary:
		# Could be {skill_id: {level, xp, ...}} or {"skills": [...]}
		if raw.has("skills"):
			var inner = raw["skills"]
			if inner is Array:
				return _array_to_dict(inner)
			elif inner is Dictionary:
				return inner
		# Assume it is already {skill_id: {level, xp, ...}}
		return raw
	elif raw is Array:
		return _array_to_dict(raw)
	return {}


static func _array_to_dict(arr: Array) -> Dictionary:
	var result: Dictionary = {}
	for item in arr:
		if item is Dictionary:
			var sid: String = item.get("id", item.get("skill_id", item.get("name", "")))
			if not sid.is_empty():
				result[sid] = item
	return result


## Calculate XP percentage toward next level. Exposed as static for testing.
static func xp_percentage(xp: float, next_level_xp: float) -> float:
	if next_level_xp <= 0.0:
		return 100.0 if xp > 0.0 else 0.0
	return clampf((xp / next_level_xp) * 100.0, 0.0, 100.0)


## Convert a snake_case skill id to a readable name (e.g. "shield_tech" -> "Shield Tech")
static func _format_skill_name(skill_id: String) -> String:
	var parts := skill_id.split("_")
	var result: PackedStringArray = []
	for part in parts:
		if part.is_empty():
			continue
		result.append(part.capitalize())
	return " ".join(result)


## Apply search filtering to a list of entries. Static for testing.
static func filter_entries(entries: Array, search_text: String, category: String) -> Array:
	var filtered: Array = []
	var lower_search := search_text.to_lower()
	for entry in entries:
		var skill_name: String = entry.get("name", "")
		var skill_cat: String = entry.get("category", "")
		if not lower_search.is_empty() and skill_name.to_lower().find(lower_search) == -1:
			continue
		if not category.is_empty() and skill_cat != category:
			continue
		filtered.append(entry)
	return filtered


func _set_buttons_disabled(disabled: bool) -> void:
	for child in skills_list.get_children():
		_disable_buttons_recursive(child, disabled)


func _disable_buttons_recursive(node: Node, disabled: bool) -> void:
	if node is Button:
		node.disabled = disabled
	for child in node.get_children():
		_disable_buttons_recursive(child, disabled)
