extends GdUnitTestSuite

# Tests for the skills panel — script loading, XP calculations, normalization,
# search filtering, and empty-state handling.


func before_test() -> void:
	StateManager.player = {"id": "p1", "name": "Test"}
	StateManager.ship = {"hull": 100, "max_hull": 100}
	StateManager.location = {"poi_id": "poi_001", "docked_at": ""}
	StateManager.current_system = {"pois": []}
	StateManager.cargo = []
	StateManager.skills = {
		"mining": {"level": 3, "xp": 450, "next_level_xp": 1000},
		"combat": {"level": 1, "xp": 50, "next_level_xp": 200},
	}


func after_test() -> void:
	StateManager.reset()


# --- Script loads ---

func test_skills_panel_script_loads() -> void:
	var script: GDScript = load("res://scripts/ui/skills_panel.gd")
	assert_that(script).is_not_null()
	assert_bool(script.can_instantiate()).is_true()


# --- XP percentage calculation ---

func test_xp_percentage_normal() -> void:
	var SkillsPanel: GDScript = load("res://scripts/ui/skills_panel.gd")
	# 450 / 1000 = 45%
	assert_float(SkillsPanel.xp_percentage(450.0, 1000.0)).is_equal_approx(45.0, 0.01)


func test_xp_percentage_zero_xp() -> void:
	var SkillsPanel: GDScript = load("res://scripts/ui/skills_panel.gd")
	assert_float(SkillsPanel.xp_percentage(0.0, 200.0)).is_equal_approx(0.0, 0.01)


func test_xp_percentage_full() -> void:
	var SkillsPanel: GDScript = load("res://scripts/ui/skills_panel.gd")
	assert_float(SkillsPanel.xp_percentage(1000.0, 1000.0)).is_equal_approx(100.0, 0.01)


func test_xp_percentage_exceeds_cap() -> void:
	var SkillsPanel: GDScript = load("res://scripts/ui/skills_panel.gd")
	# XP exceeding next_level should clamp to 100
	assert_float(SkillsPanel.xp_percentage(1500.0, 1000.0)).is_equal_approx(100.0, 0.01)


func test_xp_percentage_zero_next_level_with_xp() -> void:
	var SkillsPanel: GDScript = load("res://scripts/ui/skills_panel.gd")
	# Max level reached (next_level_xp = 0, but has xp) -> 100%
	assert_float(SkillsPanel.xp_percentage(500.0, 0.0)).is_equal_approx(100.0, 0.01)


func test_xp_percentage_zero_everything() -> void:
	var SkillsPanel: GDScript = load("res://scripts/ui/skills_panel.gd")
	assert_float(SkillsPanel.xp_percentage(0.0, 0.0)).is_equal_approx(0.0, 0.01)


func test_xp_percentage_small_fraction() -> void:
	var SkillsPanel: GDScript = load("res://scripts/ui/skills_panel.gd")
	# 50 / 200 = 25%
	assert_float(SkillsPanel.xp_percentage(50.0, 200.0)).is_equal_approx(25.0, 0.01)


# --- Skills normalization ---

func test_normalize_dict_of_dicts() -> void:
	var SkillsPanel: GDScript = load("res://scripts/ui/skills_panel.gd")
	var raw := {
		"mining": {"level": 3, "xp": 450, "next_level_xp": 1000},
		"combat": {"level": 1, "xp": 50, "next_level_xp": 200},
	}
	var result: Dictionary = SkillsPanel._normalize_skills(raw)
	assert_int(result.size()).is_equal(2)
	assert_bool(result.has("mining")).is_true()
	assert_int(result["mining"]["level"]).is_equal(3)


func test_normalize_array_of_dicts() -> void:
	var SkillsPanel: GDScript = load("res://scripts/ui/skills_panel.gd")
	var raw := [
		{"id": "mining", "level": 5, "xp": 800, "next_level_xp": 2000},
		{"id": "navigation", "level": 2, "xp": 100, "next_level_xp": 500},
	]
	var result: Dictionary = SkillsPanel._normalize_skills(raw)
	assert_int(result.size()).is_equal(2)
	assert_bool(result.has("mining")).is_true()
	assert_int(result["mining"]["level"]).is_equal(5)
	assert_bool(result.has("navigation")).is_true()


func test_normalize_nested_skills_key() -> void:
	var SkillsPanel: GDScript = load("res://scripts/ui/skills_panel.gd")
	var raw := {
		"skills": [
			{"id": "mining", "level": 1, "xp": 10, "next_level_xp": 100},
		]
	}
	var result: Dictionary = SkillsPanel._normalize_skills(raw)
	assert_int(result.size()).is_equal(1)
	assert_bool(result.has("mining")).is_true()


func test_normalize_empty_dict() -> void:
	var SkillsPanel: GDScript = load("res://scripts/ui/skills_panel.gd")
	var result: Dictionary = SkillsPanel._normalize_skills({})
	assert_int(result.size()).is_equal(0)


func test_normalize_empty_array() -> void:
	var SkillsPanel: GDScript = load("res://scripts/ui/skills_panel.gd")
	var result: Dictionary = SkillsPanel._normalize_skills([])
	assert_int(result.size()).is_equal(0)


# --- Search / filter ---

func test_filter_entries_by_name() -> void:
	var SkillsPanel: GDScript = load("res://scripts/ui/skills_panel.gd")
	var entries := [
		{"name": "Mining", "category": "Resource"},
		{"name": "Combat", "category": "Warfare"},
		{"name": "Shield Tech", "category": "Defense"},
	]
	var result: Array = SkillsPanel.filter_entries(entries, "min", "")
	assert_int(result.size()).is_equal(1)
	assert_str(result[0]["name"]).is_equal("Mining")


func test_filter_entries_by_category() -> void:
	var SkillsPanel: GDScript = load("res://scripts/ui/skills_panel.gd")
	var entries := [
		{"name": "Mining", "category": "Resource"},
		{"name": "Combat", "category": "Warfare"},
		{"name": "Shield Tech", "category": "Defense"},
	]
	var result: Array = SkillsPanel.filter_entries(entries, "", "Warfare")
	assert_int(result.size()).is_equal(1)
	assert_str(result[0]["name"]).is_equal("Combat")


func test_filter_entries_combined() -> void:
	var SkillsPanel: GDScript = load("res://scripts/ui/skills_panel.gd")
	var entries := [
		{"name": "Mining", "category": "Resource"},
		{"name": "Mineral Processing", "category": "Resource"},
		{"name": "Combat", "category": "Warfare"},
	]
	var result: Array = SkillsPanel.filter_entries(entries, "min", "Resource")
	assert_int(result.size()).is_equal(2)


func test_filter_entries_no_match() -> void:
	var SkillsPanel: GDScript = load("res://scripts/ui/skills_panel.gd")
	var entries := [
		{"name": "Mining", "category": "Resource"},
	]
	var result: Array = SkillsPanel.filter_entries(entries, "zzz", "")
	assert_int(result.size()).is_equal(0)


func test_filter_entries_empty_search_returns_all() -> void:
	var SkillsPanel: GDScript = load("res://scripts/ui/skills_panel.gd")
	var entries := [
		{"name": "Mining", "category": "Resource"},
		{"name": "Combat", "category": "Warfare"},
	]
	var result: Array = SkillsPanel.filter_entries(entries, "", "")
	assert_int(result.size()).is_equal(2)


func test_filter_is_case_insensitive() -> void:
	var SkillsPanel: GDScript = load("res://scripts/ui/skills_panel.gd")
	var entries := [
		{"name": "Shield Tech", "category": "Defense"},
	]
	var result: Array = SkillsPanel.filter_entries(entries, "SHIELD", "")
	assert_int(result.size()).is_equal(1)


# --- Empty state ---

func test_empty_skills_state() -> void:
	StateManager.skills = {}
	var SkillsPanel: GDScript = load("res://scripts/ui/skills_panel.gd")
	var result: Dictionary = SkillsPanel._normalize_skills(StateManager.skills)
	assert_int(result.size()).is_equal(0)


# --- Format skill name ---

func test_format_skill_name_snake_case() -> void:
	var SkillsPanel: GDScript = load("res://scripts/ui/skills_panel.gd")
	var result: String = SkillsPanel._format_skill_name("shield_tech")
	assert_str(result).is_equal("Shield Tech")


func test_format_skill_name_single_word() -> void:
	var SkillsPanel: GDScript = load("res://scripts/ui/skills_panel.gd")
	var result: String = SkillsPanel._format_skill_name("mining")
	assert_str(result).is_equal("Mining")
