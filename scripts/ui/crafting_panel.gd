extends PanelContainer

## Crafting panel — browse the item catalog and craft items from recipes.

@onready var catalog_list: VBoxContainer = %CatalogList
@onready var category_filter: OptionButton = %CraftCategoryFilter
@onready var page_label: Label = %PageLabel
@onready var prev_button: Button = %PrevPage
@onready var next_button: Button = %NextPage
@onready var status_label: Label = %CraftStatus

var _items: Array = []
var _current_page: int = 1
var _total_pages: int = 1
var _current_type: String = ""


func _ready() -> void:
	NetworkManager.request_started.connect(func(): _set_buttons_disabled(true))
	NetworkManager.request_completed.connect(func(): _set_buttons_disabled(false))

	category_filter.item_selected.connect(_on_category_selected)
	prev_button.pressed.connect(func(): _load_page(_current_page - 1))
	next_button.pressed.connect(func(): _load_page(_current_page + 1))

	# Set up catalog types
	category_filter.add_item("Items")
	category_filter.add_item("Recipes")
	category_filter.add_item("Ships")
	category_filter.add_item("Skills")

	_load_page(1)


func _on_category_selected(idx: int) -> void:
	_current_type = category_filter.get_item_text(idx).to_lower()
	_load_page(1)


func _load_page(page: int) -> void:
	status_label.text = "Loading catalog..."
	var catalog_type: String = _current_type if not _current_type.is_empty() else "items"
	var params: Dictionary = {"type": catalog_type, "page": page, "page_size": 20}

	NetworkManager.send_catalog_command(params, func(content: Dictionary) -> void:
		_items = content.get("items", [])
		_current_page = content.get("page", page)
		_total_pages = content.get("total_pages", 1)
		_refresh()
		page_label.text = "Page %d/%d" % [_current_page, _total_pages]
		prev_button.disabled = _current_page <= 1
		next_button.disabled = _current_page >= _total_pages
		status_label.text = "%d items (page %d/%d)" % [content.get("total", 0), _current_page, _total_pages]
	)


func _refresh() -> void:
	for child in catalog_list.get_children():
		child.queue_free()

	if _items.is_empty():
		var empty := Label.new()
		empty.text = "No items found."
		empty.add_theme_font_size_override("font_size", 12)
		empty.modulate = ThemeColors.TEXT_MUTED
		catalog_list.add_child(empty)
		return

	for item in _items:
		var card := _make_item_card(item)
		catalog_list.add_child(card)


func _make_item_card(item: Dictionary) -> VBoxContainer:
	var card := VBoxContainer.new()
	card.add_theme_constant_override("separation", 2)

	# Top row: name + category + craft button
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	var name_label := Label.new()
	name_label.text = item.get("name", "Unknown")
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.add_theme_font_size_override("font_size", 12)
	row.add_child(name_label)

	var cat_label := Label.new()
	cat_label.text = item.get("category", "")
	cat_label.custom_minimum_size.x = 70
	cat_label.add_theme_font_size_override("font_size", 11)
	cat_label.modulate = ThemeColors.HULL_GREY
	row.add_child(cat_label)

	var desc: String = item.get("description", "")
	if not desc.is_empty():
		name_label.tooltip_text = desc

	# Recipe-specific: show details, craftability, and craft button
	if _current_type == "recipes":
		var can_craft := true
		var item_id: String = item.get("id", "")

		# Skill requirement
		var req_skill: String = item.get("required_skill", "")
		var req_level: int = item.get("required_level", 0)
		if not req_skill.is_empty() and req_level > 0:
			var player_level: int = _get_player_skill_level(req_skill)
			var has_skill := player_level >= req_level
			if not has_skill:
				can_craft = false

			var skill_label := Label.new()
			skill_label.text = "  Skill: %s Lv%d (you: %d)" % [req_skill, req_level, player_level]
			skill_label.add_theme_font_size_override("font_size", 10)
			skill_label.modulate = ThemeColors.BIO_GREEN if has_skill else ThemeColors.CLAW_RED
			card.add_child(skill_label)

		# Material requirements
		var inputs: Array = item.get("inputs", [])
		for mat in inputs:
			var mat_id: String = mat.get("item_id", "")
			var mat_name: String = mat.get("item_name", mat.get("name", mat_id))
			var needed: int = mat.get("quantity", 1)
			var have: int = _get_cargo_quantity(mat_id)
			var has_enough := have >= needed
			if not has_enough:
				can_craft = false

			var mat_label := Label.new()
			mat_label.text = "  %s: %d/%d" % [mat_name, have, needed]
			mat_label.add_theme_font_size_override("font_size", 10)
			mat_label.modulate = ThemeColors.BIO_GREEN if has_enough else ThemeColors.CLAW_RED
			card.add_child(mat_label)

		# Craftability indicator on the name
		name_label.modulate = ThemeColors.BIO_GREEN if can_craft else ThemeColors.CLAW_RED

		# Craft button
		var craft_btn := Button.new()
		craft_btn.text = "Craft"
		craft_btn.add_theme_font_size_override("font_size", 10)
		craft_btn.custom_minimum_size.x = 45
		craft_btn.pressed.connect(func(): _craft_item(item_id, item.get("name", "?")))
		row.add_child(craft_btn)

	card.add_child(row)
	# Move the row to the top (it was added after skill/mat labels)
	card.move_child(row, 0)

	return card


func _get_player_skill_level(skill_id: String) -> int:
	# Skills dict may have skill data keyed by ID or name
	var skill_data = StateManager.skills.get(skill_id, {})
	if skill_data is Dictionary:
		return skill_data.get("level", 0)
	return 0


func _get_cargo_quantity(item_id: String) -> int:
	for item in StateManager.cargo:
		if item.get("item_id", item.get("id", "")) == item_id:
			return item.get("quantity", 0)
	return 0


func _craft_item(recipe_id: String, item_name: String) -> void:
	status_label.text = "Crafting %s..." % item_name
	NetworkManager.send_command("craft", {"recipe_id": recipe_id}, func(content: Dictionary) -> void:
		var output: String = content.get("output_name", item_name)
		var qty: int = content.get("quantity", 1)
		status_label.text = "Crafted %dx %s!" % [qty, output]
		NetworkManager.send_command("get_status", {})
	)


func _set_buttons_disabled(disabled: bool) -> void:
	prev_button.disabled = disabled or _current_page <= 1
	next_button.disabled = disabled or _current_page >= _total_pages
	for child in catalog_list.get_children():
		if child is VBoxContainer:
			for sub in child.get_children():
				if sub is HBoxContainer:
					for btn in sub.get_children():
						if btn is Button:
							btn.disabled = disabled
		elif child is HBoxContainer:
			for btn in child.get_children():
				if btn is Button:
					btn.disabled = disabled
