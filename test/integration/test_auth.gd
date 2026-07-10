extends GdUnitTestSuite

# Integration tests for the auth screen UI behaviour.
# Uses GdUnit4's scene runner to instantiate the scene and simulate interaction.

var _runner: GdUnitSceneRunner


func before_test() -> void:
	_runner = scene_runner("res://scenes/ui/auth.tscn")


func test_sign_in_button_present() -> void:
	var btn := _runner.scene().get_node("%SignInButton")
	assert_object(btn).is_not_null()
	assert_bool(btn.visible).is_true()


func test_key_field_present() -> void:
	var field := _runner.scene().get_node("%KeyField")
	assert_object(field).is_not_null()


func test_submit_button_present() -> void:
	var btn := _runner.scene().get_node("%SubmitButton")
	assert_object(btn).is_not_null()


func test_status_label_empty_on_load() -> void:
	var label := _runner.scene().get_node("%StatusLabel") as Label
	assert_str(label.text).is_empty()


func test_submit_button_disables_during_request() -> void:
	var btn := _runner.scene().get_node("%SubmitButton") as Button
	NetworkManager.request_started.emit()
	assert_bool(btn.disabled).is_true()


func test_submit_button_re_enables_after_request() -> void:
	var btn := _runner.scene().get_node("%SubmitButton") as Button
	NetworkManager.request_started.emit()
	NetworkManager.request_completed.emit()
	assert_bool(btn.disabled).is_false()


func test_empty_key_shows_validation_error() -> void:
	var label := _runner.scene().get_node("%StatusLabel") as Label
	_runner.scene().get_node("%KeyField").text = ""
	_runner.scene().get_node("%SubmitButton").pressed.emit()
	assert_str(label.text).is_not_empty()


func test_empty_key_shows_error_color() -> void:
	var label := _runner.scene().get_node("%StatusLabel") as Label
	_runner.scene().get_node("%KeyField").text = ""
	_runner.scene().get_node("%SubmitButton").pressed.emit()
	assert_object(label.modulate).is_equal(ThemeColors.TEXT_ERROR)


func test_show_player_select_signal_exists() -> void:
	assert_bool(_runner.scene().has_signal("show_player_select")).is_true()
