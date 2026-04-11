extends GdUnitTestSuite

# Tests for the Info Panel -- timestamp formatting, category colors,
# constants, and header/log entry building via static methods on InfoPanel.


func before_test() -> void:
	StateManager.player = {"id": "p1", "name": "Test"}
	StateManager.ship = {"hull": 100, "max_hull": 100}
	StateManager.location = {"poi_id": "poi_001", "docked_at": "base_001"}
	StateManager.cargo = []


func after_test() -> void:
	StateManager.reset()


# --- Script loading ---

func test_info_panel_script_loads() -> void:
	var script: GDScript = load("res://scripts/ui/info_panel.gd")
	assert_that(script).is_not_null()
	assert_bool(script.can_instantiate()).is_true()


# --- Timestamp formatting (static) ---

func test_format_timestamp_iso() -> void:
	var result: String = InfoPanel._format_timestamp("2026-04-11T14:30:00Z")
	assert_str(result).is_equal("14:30")


func test_format_timestamp_empty() -> void:
	var result: String = InfoPanel._format_timestamp("")
	assert_str(result).is_equal("--:--")


func test_format_timestamp_short_string() -> void:
	var result: String = InfoPanel._format_timestamp("abc")
	assert_str(result).is_equal("abc")


# --- Category colors (static) ---

func test_category_color_combat() -> void:
	var color: Color = InfoPanel._get_category_color("combat")
	assert_object(color).is_equal(ThemeColors.CAT_COMBAT)


func test_category_color_trading() -> void:
	var color: Color = InfoPanel._get_category_color("trading")
	assert_object(color).is_equal(ThemeColors.CAT_TRADE)


func test_category_color_trade_alias() -> void:
	var color: Color = InfoPanel._get_category_color("trade")
	assert_object(color).is_equal(ThemeColors.CAT_TRADE)


func test_category_color_navigation() -> void:
	var color: Color = InfoPanel._get_category_color("navigation")
	assert_object(color).is_equal(ThemeColors.CAT_NAVIGATION)


func test_category_color_travel() -> void:
	var color: Color = InfoPanel._get_category_color("travel")
	assert_object(color).is_equal(ThemeColors.CAT_NAVIGATION)


func test_category_color_unknown_returns_default() -> void:
	var color: Color = InfoPanel._get_category_color("unknown_type")
	assert_object(color).is_equal(ThemeColors.CAT_DEFAULT)


func test_category_color_case_insensitive() -> void:
	var color: Color = InfoPanel._get_category_color("COMBAT")
	assert_object(color).is_equal(ThemeColors.CAT_COMBAT)


# --- Log constants ---

func test_log_page_size_is_reasonable() -> void:
	assert_int(InfoPanel.LOG_PAGE_SIZE).is_equal(20)


func test_log_categories_include_all() -> void:
	assert_bool(InfoPanel.LOG_CATEGORIES.has("All")).is_true()
	assert_bool(InfoPanel.LOG_CATEGORIES.has("Combat")).is_true()
	assert_bool(InfoPanel.LOG_CATEGORIES.has("Trading")).is_true()
	assert_bool(InfoPanel.LOG_CATEGORIES.has("Mining")).is_true()


# --- Header builder (static) ---

func test_make_header_creates_labels() -> void:
	var header: HBoxContainer = InfoPanel._make_header(["COL1", "COL2", "COL3"])
	assert_int(header.get_child_count()).is_equal(3)
	var first_label: Label = header.get_child(0) as Label
	assert_str(first_label.text).is_equal("COL1")
	header.free()


# --- Log entry row builder (static) ---

func test_make_log_entry_row_structure() -> void:
	var entry := {
		"timestamp": "2026-04-11T09:15:00Z",
		"type": "combat",
		"message": "You attacked Pirate Bob."
	}
	var row: HBoxContainer = InfoPanel._make_log_entry_row(entry)
	assert_int(row.get_child_count()).is_equal(3)

	var time_label: Label = row.get_child(0) as Label
	assert_str(time_label.text).is_equal("09:15")

	var cat_label: Label = row.get_child(1) as Label
	assert_str(cat_label.text).is_equal("[COMBAT]")

	var msg_label: Label = row.get_child(2) as Label
	assert_str(msg_label.text).is_equal("You attacked Pirate Bob.")

	row.free()


# --- Note content truncation ---

func test_long_content_truncation_logic() -> void:
	var long_content := "A".repeat(200)
	# The note card truncates at 100 chars + "..."
	var preview: String
	if long_content.length() > 100:
		preview = long_content.substr(0, 100) + "..."
	else:
		preview = long_content
	assert_int(preview.length()).is_equal(103)
	assert_bool(preview.ends_with("...")).is_true()


func test_short_content_not_truncated() -> void:
	var short_content := "Hello world"
	var preview: String
	if short_content.length() > 100:
		preview = short_content.substr(0, 100) + "..."
	else:
		preview = short_content
	assert_str(preview).is_equal("Hello world")
