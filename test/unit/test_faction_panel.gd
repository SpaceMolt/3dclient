extends GdUnitTestSuite

# Tests for faction panel logic — script loading, data parsing,
# view state determination, and leader detection.
# Uses static methods on FactionPanel class_name.


func before_test() -> void:
	StateManager.player = {"id": "p1", "name": "TestPlayer", "faction_id": "f1"}
	StateManager.ship = {}
	StateManager.location = {}
	StateManager.cargo = []
	StateManager.current_system = {}


func after_test() -> void:
	StateManager.reset()


# --- Script loading ---

func test_faction_panel_script_loads() -> void:
	var script: GDScript = load("res://scripts/ui/faction_panel.gd")
	assert_that(script).is_not_null()
	assert_bool(script.can_instantiate()).is_true()


# --- Data parsing helpers ---

func test_get_parsed_members_returns_member_list() -> void:
	var faction_data := {
		"name": "TestFaction",
		"tag": "TEST",
		"members": [
			{"player_id": "p1", "username": "Alice", "rank": "leader"},
			{"player_id": "p2", "username": "Bob", "rank": "member"},
			{"player_id": "p3", "username": "Carol", "rank": "member"},
		]
	}
	var members: Array = FactionPanel.get_parsed_members(faction_data)
	assert_int(members.size()).is_equal(3)
	assert_str(members[0].get("username")).is_equal("Alice")
	assert_str(members[1].get("username")).is_equal("Bob")
	assert_str(members[2].get("username")).is_equal("Carol")


func test_get_parsed_members_returns_empty_when_no_members() -> void:
	var faction_data := {"name": "EmptyFaction", "tag": "EMPT"}
	var members: Array = FactionPanel.get_parsed_members(faction_data)
	assert_int(members.size()).is_equal(0)


func test_get_parsed_members_returns_empty_for_empty_data() -> void:
	var members: Array = FactionPanel.get_parsed_members({})
	assert_int(members.size()).is_equal(0)


# --- Leader detection ---

func test_is_player_leader_true_when_leader() -> void:
	var faction_data := {
		"name": "TestFaction",
		"tag": "TEST",
		"members": [
			{"player_id": "p1", "username": "Alice", "rank": "leader"},
			{"player_id": "p2", "username": "Bob", "rank": "member"},
		]
	}
	assert_bool(FactionPanel.is_player_leader(faction_data, "p1")).is_true()


func test_is_player_leader_false_when_member() -> void:
	var faction_data := {
		"name": "TestFaction",
		"tag": "TEST",
		"members": [
			{"player_id": "p1", "username": "Alice", "rank": "leader"},
			{"player_id": "p2", "username": "Bob", "rank": "member"},
		]
	}
	assert_bool(FactionPanel.is_player_leader(faction_data, "p2")).is_false()


func test_is_player_leader_false_when_not_in_faction() -> void:
	var faction_data := {
		"name": "TestFaction",
		"tag": "TEST",
		"members": [
			{"player_id": "p1", "username": "Alice", "rank": "leader"},
		]
	}
	assert_bool(FactionPanel.is_player_leader(faction_data, "p99")).is_false()


func test_is_player_leader_false_for_empty_data() -> void:
	assert_bool(FactionPanel.is_player_leader({}, "p1")).is_false()


# --- View state ---

func test_view_state_no_faction_when_empty() -> void:
	assert_str(FactionPanel.get_view_state({})).is_equal("no_faction")


func test_view_state_no_faction_when_no_name() -> void:
	assert_str(FactionPanel.get_view_state({"tag": "TEST"})).is_equal("no_faction")


func test_view_state_has_faction_when_name_present() -> void:
	assert_str(FactionPanel.get_view_state({"name": "TestFaction", "tag": "TEST"})).is_equal("has_faction")


func test_view_state_has_faction_with_full_data() -> void:
	var faction_data := {
		"name": "BigFaction",
		"tag": "BIG",
		"members": [
			{"player_id": "p1", "username": "Alice", "rank": "leader"},
		]
	}
	assert_str(FactionPanel.get_view_state(faction_data)).is_equal("has_faction")
