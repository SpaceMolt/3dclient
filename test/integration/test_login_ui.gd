extends GdUnitTestSuite

# Integration tests for the login screen UI behaviour.
# Uses GdUnit4's scene runner to instantiate the scene and simulate interaction.

const LOGIN_SCENE := preload("res://scenes/ui/login.tscn")

var _runner: GdUnitSceneRunner


func before_test() -> void:
	_runner = scene_runner(LOGIN_SCENE)
	await _runner.scene().ready


func after_test() -> void:
	_runner.free()


func test_login_button_present() -> void:
	var btn := _runner.scene().get_node("%LoginButton")
	assert_object(btn).is_not_null()
	assert_bool(btn.disabled).is_false()


func test_register_link_present() -> void:
	var link := _runner.scene().get_node("%RegisterLink")
	assert_object(link).is_not_null()


func test_status_label_empty_on_load() -> void:
	var label := _runner.scene().get_node("%StatusLabel") as Label
	assert_str(label.text).is_empty()


func test_login_button_disables_during_request() -> void:
	var btn := _runner.scene().get_node("%LoginButton") as Button
	NetworkManager.request_started.emit()
	assert_bool(btn.disabled).is_true()


func test_login_button_re_enables_after_request() -> void:
	var btn := _runner.scene().get_node("%LoginButton") as Button
	NetworkManager.request_started.emit()
	NetworkManager.request_completed.emit()
	assert_bool(btn.disabled).is_false()


func test_error_signal_updates_status_label() -> void:
	var label := _runner.scene().get_node("%StatusLabel") as Label
	UIManager.error_shown.emit("Bad credentials")
	assert_str(label.text).is_equal("Bad credentials")


func test_error_label_is_red() -> void:
	var label := _runner.scene().get_node("%StatusLabel") as Label
	UIManager.error_shown.emit("Something failed")
	assert_object(label.modulate).is_equal(Color.RED)


func test_empty_username_shows_error() -> void:
	var label := _runner.scene().get_node("%StatusLabel") as Label
	var btn := _runner.scene().get_node("%LoginButton") as Button
	_runner.scene().get_node("%Username").text = ""
	_runner.scene().get_node("%Password").text = "password"
	await _runner.simulate_action_pressed(btn)
	assert_str(label.text).is_not_empty()


func test_empty_password_shows_error() -> void:
	var label := _runner.scene().get_node("%StatusLabel") as Label
	var btn := _runner.scene().get_node("%LoginButton") as Button
	_runner.scene().get_node("%Username").text = "user"
	_runner.scene().get_node("%Password").text = ""
	await _runner.simulate_action_pressed(btn)
	assert_str(label.text).is_not_empty()
