extends GdUnitTestSuite

# Unit tests for the dev control server's command handling. The TCP side is not
# exercised here; it is inactive in tests because SPACEMOLT_DEV_PORT is unset.


func test_inactive_without_env() -> void:
	assert_bool(DevServer.is_processing()).is_false()


func test_take_lines_splits_complete_lines_and_keeps_partial() -> void:
	var client := {"buf": '{"cmd":"a"}\n\n{"cmd":"b"}\n{"cmd":'}
	var lines := DevServer.take_lines(client)
	assert_array(lines).contains_exactly(['{"cmd":"a"}', '{"cmd":"b"}'])
	assert_str(client["buf"]).is_equal('{"cmd":')


func test_ping() -> void:
	var reply := DevServer.handle({"cmd": "ping"})
	assert_bool(reply["ok"]).is_true()
	assert_str(reply["godot"]).is_not_empty()


func test_unknown_command_is_an_error() -> void:
	var reply := DevServer.handle({"cmd": "explode"})
	assert_bool(reply["ok"]).is_false()
	assert_str(reply["error"]).contains("explode")


func test_non_object_line_is_an_error() -> void:
	assert_bool(DevServer.handle_line("[1,2]")["ok"]).is_false()
	assert_bool(DevServer.handle_line("not json")["ok"]).is_false()


func test_key_resolves_keycode() -> void:
	var reply := DevServer.handle({"cmd": "key", "key": "D"})
	assert_bool(reply["ok"]).is_true()
	assert_int(reply["keycode"]).is_equal(KEY_D)


func test_key_rejects_unknown_name() -> void:
	var reply := DevServer.handle({"cmd": "key", "key": "NotAKey"})
	assert_bool(reply["ok"]).is_false()


func test_screenshot_requires_path() -> void:
	assert_bool(DevServer.handle({"cmd": "screenshot"})["ok"]).is_false()


func test_state_exposes_state_manager_fields_and_network() -> void:
	var reply := DevServer.handle({"cmd": "state"})
	assert_bool(reply["ok"]).is_true()
	var state: Dictionary = reply["state"]
	assert_bool(state.has("ship")).is_true()
	assert_bool(state.has("location")).is_true()
	assert_bool(state.has("is_traveling")).is_true()
	assert_bool(state["network"].has("is_authenticated")).is_true()


func test_nodes_filters_by_pattern() -> void:
	var button := Button.new()
	button.name = "DevProbeButton"
	button.text = "Probe"
	add_child(button)
	var reply := DevServer.handle({"cmd": "nodes", "pattern": "devprobe"})
	assert_int(reply["nodes"].size()).is_equal(1)
	assert_str(reply["nodes"][0]["text"]).is_equal("Probe")
	button.queue_free()


func test_call_invokes_node_method() -> void:
	var reply := DevServer.handle({"cmd": "call", "node": "/root/NetworkManager", "method": "ws_url", "args": []})
	assert_bool(reply["ok"]).is_true()
	assert_str(reply["result"]).ends_with("/ws/v2")


func test_call_rejects_missing_node_or_method() -> void:
	assert_bool(DevServer.handle({"cmd": "call", "node": "/root/Nope", "method": "x"})["ok"]).is_false()
	assert_bool(DevServer.handle({"cmd": "call", "node": "/root/NetworkManager", "method": "nope"})["ok"]).is_false()
