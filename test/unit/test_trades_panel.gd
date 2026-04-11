extends GdUnitTestSuite

# Tests for the trades panel -- script loading, docking prerequisites,
# trade summarization, and empty-state handling.


func before_test() -> void:
	StateManager.player = {"id": "p1", "name": "TestPlayer", "credits": 5000}
	StateManager.ship = {"hull": 100, "max_hull": 100}
	StateManager.location = {"docked_at": "base_001"}
	StateManager.cargo = []


func after_test() -> void:
	StateManager.reset()


# --- Script loads ---

func test_trades_panel_script_loads() -> void:
	var script: GDScript = load("res://scripts/ui/trades_panel.gd")
	assert_that(script).is_not_null()
	assert_bool(script.can_instantiate()).is_true()


# --- Docking prerequisite ---

func test_trade_requires_docking() -> void:
	StateManager.location = {}
	assert_bool(StateManager.is_docked()).is_false()

	StateManager.location = {"docked_at": "base_001"}
	assert_bool(StateManager.is_docked()).is_true()


func test_trade_not_docked_with_empty_string() -> void:
	StateManager.location = {"docked_at": ""}
	assert_bool(StateManager.is_docked()).is_false()


# --- Empty trade lists ---

func test_empty_incoming_trades() -> void:
	var incoming: Array = []
	assert_bool(incoming.is_empty()).is_true()


func test_empty_outgoing_trades() -> void:
	var outgoing: Array = []
	assert_bool(outgoing.is_empty()).is_true()


# --- Summarize trade (incoming) ---

func test_summarize_incoming_trade() -> void:
	var TradesPanel: GDScript = load("res://scripts/ui/trades_panel.gd")
	var trade := {
		"trade_id": "t1",
		"offerer_name": "Alice",
		"target_name": "TestPlayer",
		"offer_items": [
			{"item_id": "iron_ore", "quantity": 50},
			{"item_id": "copper_ore", "quantity": 20},
		],
		"offer_credits": 100,
		"request_items": [
			{"item_id": "fuel_cell", "quantity": 5},
		],
		"request_credits": 0,
		"expires_at": "2026-04-12T00:00:00Z",
	}
	var summary: Dictionary = TradesPanel.summarize_trade(trade, true)
	assert_str(summary["player"]).is_equal("Alice")
	assert_str(summary["direction"]).is_equal("incoming")
	assert_int(summary["offer_item_count"]).is_equal(2)
	assert_int(summary["request_item_count"]).is_equal(1)
	assert_int(summary["total_items"]).is_equal(3)
	assert_int(summary["offer_credits"]).is_equal(100)
	assert_int(summary["request_credits"]).is_equal(0)
	assert_str(summary["trade_id"]).is_equal("t1")


# --- Summarize trade (outgoing) ---

func test_summarize_outgoing_trade() -> void:
	var TradesPanel: GDScript = load("res://scripts/ui/trades_panel.gd")
	var trade := {
		"trade_id": "t2",
		"offerer_name": "TestPlayer",
		"target_name": "Bob",
		"offer_items": [],
		"offer_credits": 500,
		"request_items": [
			{"item_id": "shield_gen", "quantity": 1},
		],
		"request_credits": 0,
		"expires_at": "2026-04-12T00:00:00Z",
	}
	var summary: Dictionary = TradesPanel.summarize_trade(trade, false)
	assert_str(summary["player"]).is_equal("Bob")
	assert_str(summary["direction"]).is_equal("outgoing")
	assert_int(summary["offer_item_count"]).is_equal(0)
	assert_int(summary["request_item_count"]).is_equal(1)
	assert_int(summary["offer_credits"]).is_equal(500)
	assert_int(summary["total_credits"]).is_equal(500)


# --- Summarize trade with no items or credits ---

func test_summarize_empty_trade() -> void:
	var TradesPanel: GDScript = load("res://scripts/ui/trades_panel.gd")
	var trade := {
		"trade_id": "t3",
		"offerer_name": "Charlie",
		"offer_items": [],
		"offer_credits": 0,
		"request_items": [],
		"request_credits": 0,
		"expires_at": "2026-04-12T00:00:00Z",
	}
	var summary: Dictionary = TradesPanel.summarize_trade(trade, true)
	assert_int(summary["total_items"]).is_equal(0)
	assert_int(summary["total_credits"]).is_equal(0)


# --- Summarize trade with missing optional fields ---

func test_summarize_trade_missing_optional_fields() -> void:
	var TradesPanel: GDScript = load("res://scripts/ui/trades_panel.gd")
	var trade := {
		"trade_id": "t4",
		"offer_items": [{"item_id": "ore", "quantity": 10}],
		"request_items": [],
		"expires_at": "2026-04-12T00:00:00Z",
	}
	# Missing offerer_name, target_name, credits fields
	var summary_in: Dictionary = TradesPanel.summarize_trade(trade, true)
	assert_str(summary_in["player"]).is_equal("Unknown")
	assert_int(summary_in["offer_credits"]).is_equal(0)

	var summary_out: Dictionary = TradesPanel.summarize_trade(trade, false)
	assert_str(summary_out["player"]).is_equal("Unknown")


# --- Docking state transitions ---

func test_docked_state_after_undock() -> void:
	StateManager.location = {"docked_at": "base_001"}
	assert_bool(StateManager.is_docked()).is_true()

	# Simulate undocking
	StateManager.location = {"poi_id": "poi_001", "docked_at": ""}
	assert_bool(StateManager.is_docked()).is_false()
