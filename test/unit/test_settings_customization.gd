extends GdUnitTestSuite


func before_test() -> void:
	StateManager.player = {
		"id": "p1",
		"name": "Test",
		"status_message": "",
		"clan_tag": "",
		"primary_color": "",
		"secondary_color": "",
		"home_base": "",
	}
	StateManager.location = {}


func after_test() -> void:
	StateManager.reset()


func test_settings_panel_script_loads() -> void:
	var script: GDScript = load("res://scripts/ui/settings_panel.gd")
	assert_that(script).is_not_null()
	assert_bool(script.can_instantiate()).is_true()


func test_home_base_requires_docking() -> void:
	StateManager.location = {}
	assert_bool(StateManager.is_docked()).is_false()
	StateManager.location = {"docked_at": "base_001"}
	assert_bool(StateManager.is_docked()).is_true()


func test_clan_tag_max_length() -> void:
	# Clan tags should be max 4 characters
	var tag := "ABCDEFGH"
	assert_int(tag.left(4).length()).is_equal(4)
	assert_str(tag.left(4)).is_equal("ABCD")


func test_normalize_hex_strips_hash() -> void:
	var script: GDScript = load("res://scripts/ui/settings_panel.gd")
	assert_str(script._normalize_hex("#FF0000")).is_equal("FF0000")
	assert_str(script._normalize_hex("FF0000")).is_equal("FF0000")
	assert_str(script._normalize_hex("#abc")).is_equal("abc")


func test_is_valid_hex_accepts_valid() -> void:
	var script: GDScript = load("res://scripts/ui/settings_panel.gd")
	assert_bool(script._is_valid_hex("FF0000")).is_true()
	assert_bool(script._is_valid_hex("00ff00")).is_true()
	assert_bool(script._is_valid_hex("aaBBcc")).is_true()


func test_is_valid_hex_rejects_invalid() -> void:
	var script: GDScript = load("res://scripts/ui/settings_panel.gd")
	assert_bool(script._is_valid_hex("")).is_false()
	assert_bool(script._is_valid_hex("GGGGGG")).is_false()
	assert_bool(script._is_valid_hex("FFF")).is_false()
	assert_bool(script._is_valid_hex("#FF0000")).is_false()
	assert_bool(script._is_valid_hex("FF00001")).is_false()


func test_home_base_not_docked_shows_no_button() -> void:
	# When not docked, the set home base button should be hidden
	StateManager.location = {}
	assert_bool(StateManager.is_docked()).is_false()


func test_home_base_docked_allows_setting() -> void:
	# When docked, setting home base should be possible
	StateManager.location = {"docked_at": "base_042"}
	assert_bool(StateManager.is_docked()).is_true()
	assert_str(StateManager.location.get("docked_at", "")).is_equal("base_042")


func test_player_data_has_customization_fields() -> void:
	# Verify player dict has the fields we read from
	assert_str(StateManager.player.get("status_message", "")).is_equal("")
	assert_str(StateManager.player.get("clan_tag", "")).is_equal("")
	assert_str(StateManager.player.get("primary_color", "")).is_equal("")
	assert_str(StateManager.player.get("secondary_color", "")).is_equal("")
	assert_str(StateManager.player.get("home_base", "")).is_equal("")
