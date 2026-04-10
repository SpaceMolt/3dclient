extends GdUnitTestSuite

const AUTH_SCENE := preload("res://scenes/ui/auth.tscn")

var _runner: SceneRunner


func before_test() -> void:
	_runner = scene_runner(AUTH_SCENE)


func test_sign_in_button_exists() -> void:
	var btn = _runner.find_child("SignInButton")
	assert_that(btn).is_not_null()
	assert_bool(btn.visible).is_true()


func test_key_field_exists() -> void:
	var field = _runner.find_child("KeyField")
	assert_that(field).is_not_null()


func test_submit_button_exists() -> void:
	var btn = _runner.find_child("SubmitButton")
	assert_that(btn).is_not_null()


func test_status_label_empty_on_load() -> void:
	var label = _runner.find_child("StatusLabel")
	assert_str(label.text).is_equal("")


func test_submit_with_empty_key_shows_error() -> void:
	var field = _runner.find_child("KeyField") as LineEdit
	field.text = ""
	_runner.find_child("SubmitButton").emit_signal("pressed")
	await _runner.await_idle_frame()
	var label = _runner.find_child("StatusLabel") as Label
	assert_str(label.text).is_not_equal("")


func test_show_player_select_signal_exists() -> void:
	var scene = _runner.scene()
	assert_bool(scene.has_signal("show_player_select")).is_true()
