extends GdUnitTestSuite

var _runner: GdUnitSceneRunner


func before_test() -> void:
	_runner = scene_runner("res://scenes/ui/create_player.tscn")


func test_username_field_present() -> void:
	var field := _runner.scene().get_node("%UsernameField")
	assert_object(field).is_not_null()


func test_empire_dropdown_present() -> void:
	var dropdown := _runner.scene().get_node("%EmpireDropdown") as OptionButton
	assert_object(dropdown).is_not_null()
	assert_int(dropdown.item_count).is_equal(5)


func test_create_button_present() -> void:
	var btn := _runner.scene().get_node("%CreateButton")
	assert_object(btn).is_not_null()


func test_back_button_present() -> void:
	var btn := _runner.scene().get_node("%BackButton")
	assert_object(btn).is_not_null()


func test_status_label_empty_on_load() -> void:
	var label := _runner.scene().get_node("%StatusLabel") as Label
	assert_str(label.text).is_empty()


func test_show_player_select_signal_exists() -> void:
	assert_bool(_runner.scene().has_signal("show_player_select")).is_true()


func test_empty_username_shows_error() -> void:
	_runner.scene().get_node("%UsernameField").text = ""
	_runner.scene().get_node("%CreateButton").pressed.emit()
	var label := _runner.scene().get_node("%StatusLabel") as Label
	assert_str(label.text).is_not_empty()


func test_empty_username_shows_error_color() -> void:
	_runner.scene().get_node("%UsernameField").text = ""
	_runner.scene().get_node("%CreateButton").pressed.emit()
	var label := _runner.scene().get_node("%StatusLabel") as Label
	assert_object(label.modulate).is_equal(ThemeColors.TEXT_ERROR)
