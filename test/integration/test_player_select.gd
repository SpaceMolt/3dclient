extends GdUnitTestSuite

var _runner: GdUnitSceneRunner


func before_test() -> void:
	_runner = scene_runner("res://scenes/ui/player_select.tscn")


func test_create_button_present() -> void:
	var btn := _runner.scene().get_node("%CreateButton")
	assert_object(btn).is_not_null()
	assert_bool(btn.visible).is_true()


func test_sign_out_button_present() -> void:
	var btn := _runner.scene().get_node("%SignOutButton")
	assert_object(btn).is_not_null()


func test_player_list_container_present() -> void:
	var container := _runner.scene().get_node("%PlayerList")
	assert_object(container).is_not_null()


func test_status_label_empty_on_load() -> void:
	var label := _runner.scene().get_node("%StatusLabel") as Label
	assert_str(label.text).is_empty()


func test_show_create_player_signal_exists() -> void:
	assert_bool(_runner.scene().has_signal("show_create_player")).is_true()


func test_show_auth_signal_exists() -> void:
	assert_bool(_runner.scene().has_signal("show_auth")).is_true()


func test_set_players_creates_buttons() -> void:
	var scene := _runner.scene()
	scene.set_players([
		{"id": "p1", "username": "Alice", "empire": "solarian"},
		{"id": "p2", "username": "Bob", "empire": "voidborn"},
	])
	await await_idle_frame()
	var list := _runner.scene().get_node("%PlayerList") as VBoxContainer
	assert_int(list.get_child_count()).is_equal(2)


func test_set_players_button_text() -> void:
	var scene := _runner.scene()
	scene.set_players([
		{"id": "p1", "username": "Alice", "empire": "solarian"},
	])
	await await_idle_frame()
	var list := _runner.scene().get_node("%PlayerList") as VBoxContainer
	var btn := list.get_child(0) as Button
	assert_str(btn.text).is_equal("Alice  [Solarian]")
