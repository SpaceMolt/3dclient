extends GdUnitTestSuite

# HUD colour rules and layout: bar colours, empire tint, and where the event log lives.

const HUD_SCENE := preload("res://scenes/ui/hud.tscn")
const Hud := preload("res://scripts/ui/hud.gd")


func test_hull_color_steps_from_green_to_red() -> void:
	assert_object(Hud.hull_color(1.0)).is_equal(ThemeColors.BIO_GREEN)
	assert_object(Hud.hull_color(0.49)).is_equal(ThemeColors.WARNING_YELLOW)
	assert_object(Hud.hull_color(0.1)).is_equal(ThemeColors.CLAW_RED)


func test_empire_color_covers_all_five_and_falls_back() -> void:
	assert_object(ThemeColors.empire_color("solarian")).is_equal(ThemeColors.EMPIRE_SOLARIAN)
	assert_object(ThemeColors.empire_color("voidborn")).is_equal(ThemeColors.EMPIRE_VOIDBORN)
	assert_object(ThemeColors.empire_color("crimson")).is_equal(ThemeColors.EMPIRE_CRIMSON)
	assert_object(ThemeColors.empire_color("nebula")).is_equal(ThemeColors.EMPIRE_NEBULA)
	assert_object(ThemeColors.empire_color("outerrim")).is_equal(ThemeColors.EMPIRE_OUTERRIM)
	assert_object(ThemeColors.empire_color("")).is_equal(ThemeColors.TEXT_ACCENT)


func test_panel_title_is_a_label_variation() -> void:
	assert_str(String(ThemeManager.theme.get_type_variation_base("PanelTitle"))).is_equal("Label")


func test_event_log_is_an_overlay_not_a_column() -> void:
	var hud: Node = HUD_SCENE.instantiate()
	add_child(hud)
	assert_that(hud.get_node_or_null("Layout/MidRow/GameArea/EventLogPanel")).is_not_null()
	# with the log out of the row, side panels are the only children a toggle can add
	assert_int(hud.get_node("Layout/MidRow").get_child_count()).is_equal(1)
	hud.queue_free()


func test_controls_under_the_canvas_layer_get_the_house_theme() -> void:
	var hud: Node = HUD_SCENE.instantiate()
	add_child(hud)
	assert_object(hud.get_node("Layout").theme).is_equal(ThemeManager.theme)
	var title := Label.new()
	title.theme_type_variation = &"PanelTitle"
	hud.get_node("Layout").add_child(title)
	assert_object(title.get_theme_color("font_color")).is_equal(ThemeColors.PLASMA_CYAN)
	hud.queue_free()


func test_each_ship_bar_has_its_own_fill_colour() -> void:
	var hud: Node = HUD_SCENE.instantiate()
	add_child(hud)
	var shield: StyleBoxFlat = hud.shield_bar.get_theme_stylebox("fill")
	var fuel: StyleBoxFlat = hud.fuel_bar.get_theme_stylebox("fill")
	assert_object(shield.bg_color).is_not_equal(fuel.bg_color)
	hud.queue_free()
