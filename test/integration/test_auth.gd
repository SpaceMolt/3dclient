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


func test_link_box_hidden_on_load() -> void:
	var box := _runner.scene().get_node("%LinkBox") as Control
	assert_bool(box.visible).is_false()


func test_device_link_shows_copyable_link_and_code() -> void:
	var scene := _runner.scene()
	scene._on_device_link("https://spacemolt.com/link?code=ABCD-EFGH", "ABCD-EFGH")
	var field := scene.get_node("%LinkField") as LineEdit
	assert_str(field.text).is_equal("https://spacemolt.com/link?code=ABCD-EFGH")
	assert_bool(field.editable).is_false()
	assert_bool(scene.get_node("%LinkBox").visible).is_true()
	assert_str(scene.get_node("%StatusLabel").text).contains("ABCD-EFGH")


func test_auth_error_hides_link_and_reenables_sign_in() -> void:
	var scene := _runner.scene()
	scene._on_device_link("https://spacemolt.com/link?code=ABCD-EFGH", "ABCD-EFGH")
	scene._on_auth_error("Login link expired. Try again.")
	assert_bool(scene.get_node("%LinkBox").visible).is_false()
	assert_bool(scene.get_node("%SignInButton").disabled).is_false()
	assert_str(scene.get_node("%StatusLabel").text).is_equal("Login link expired. Try again.")
