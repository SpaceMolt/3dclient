extends Node

# Builds and applies a global Godot Theme matching the www.spacemolt.com design.
# Loaded as an autoload so the theme is ready before any UI scenes.

var theme: Theme

# Font resources (loaded once, reused across the theme)
var font_jetbrains: FontFile
var font_jetbrains_bold: FontFile
var font_jetbrains_medium: FontFile
var font_jetbrains_light: FontFile
var font_orbitron_bold: FontFile
var font_orbitron_medium: FontFile
var font_space_grotesk: FontFile
var font_space_grotesk_medium: FontFile
var font_space_grotesk_bold: FontFile


func _ready() -> void:
	_load_fonts()
	_build_theme()
	_apply_theme()



func _load_fonts() -> void:
	font_jetbrains = load("res://assets/fonts/JetBrainsMono-Regular.ttf")
	font_jetbrains_bold = load("res://assets/fonts/JetBrainsMono-Bold.ttf")
	font_jetbrains_medium = load("res://assets/fonts/JetBrainsMono-Medium.ttf")
	font_jetbrains_light = load("res://assets/fonts/JetBrainsMono-Light.ttf")
	font_orbitron_bold = load("res://assets/fonts/Orbitron-Bold.ttf")
	font_orbitron_medium = load("res://assets/fonts/Orbitron-Medium.ttf")
	font_space_grotesk = load("res://assets/fonts/SpaceGrotesk-Regular.ttf")
	font_space_grotesk_medium = load("res://assets/fonts/SpaceGrotesk-Medium.ttf")
	font_space_grotesk_bold = load("res://assets/fonts/SpaceGrotesk-Bold.ttf")


func _build_theme() -> void:
	theme = Theme.new()

	# Default font for the entire UI is JetBrains Mono (matches www nav/stats style)
	theme.default_font = font_jetbrains
	theme.default_font_size = ThemeColors.FONT_SIZE_MD

	_theme_label()
	_theme_panel_title()
	_theme_button()
	_theme_line_edit()
	_theme_text_edit()
	_theme_panel()
	_theme_panel_container()
	_theme_tab_container()
	_theme_scroll_container()
	_theme_h_scroll_bar()
	_theme_v_scroll_bar()
	_theme_option_button()
	_theme_check_button()
	_theme_item_list()
	_theme_popup_menu()
	_theme_tooltip()
	_theme_separator()
	_theme_progress_bar()


func _apply_theme() -> void:
	get_tree().root.theme = theme
	# A theme flows down through Control and Window parents only. A Control under a
	# CanvasLayer or a plain Node, which is every HUD panel, falls back to the engine
	# default, so those get the theme directly as they enter the tree.
	get_tree().node_added.connect(_adopt_orphan_control)


func _adopt_orphan_control(node: Node) -> void:
	if node is Control and not (node.get_parent() is Control or node.get_parent() is Window):
		node.theme = theme


# ── Label ────────────────────────────────────────────────────────────

func _theme_label() -> void:
	theme.set_color("font_color", "Label", ThemeColors.TEXT_PRIMARY)
	theme.set_color("font_shadow_color", "Label", Color.TRANSPARENT)
	theme.set_color("font_outline_color", "Label", Color.TRANSPARENT)
	theme.set_font("font", "Label", font_jetbrains)
	theme.set_font_size("font_size", "Label", ThemeColors.FONT_SIZE_MD)


# ── PanelTitle (Label variation for panel headers) ───────────────────

func _theme_panel_title() -> void:
	theme.add_type("PanelTitle")
	theme.set_type_variation("PanelTitle", "Label")
	theme.set_font("font", "PanelTitle", font_orbitron_medium)
	theme.set_font_size("font_size", "PanelTitle", ThemeColors.FONT_SIZE_MD)
	theme.set_color("font_color", "PanelTitle", ThemeColors.PLASMA_CYAN)


# ── Button ───────────────────────────────────────────────────────────

func _theme_button() -> void:
	# Fonts
	theme.set_font("font", "Button", font_jetbrains_medium)
	theme.set_font_size("font_size", "Button", ThemeColors.FONT_SIZE_SM)

	# Colors
	theme.set_color("font_color", "Button", ThemeColors.CHROME_SILVER)
	theme.set_color("font_hover_color", "Button", ThemeColors.PLASMA_CYAN)
	theme.set_color("font_pressed_color", "Button", ThemeColors.STAR_WHITE)
	theme.set_color("font_focus_color", "Button", ThemeColors.PLASMA_CYAN)
	theme.set_color("font_disabled_color", "Button", ThemeColors.DIM_GREY)

	# Normal state
	var normal := _make_stylebox(ThemeColors.DEEP_VOID, ThemeColors.DIM_GREY)
	theme.set_stylebox("normal", "Button", normal)

	# Hover state — border brightens to cyan
	var hover := _make_stylebox(
		Color(ThemeColors.PLASMA_CYAN, 0.08),
		ThemeColors.PLASMA_CYAN
	)
	theme.set_stylebox("hover", "Button", hover)

	# Pressed state
	var pressed := _make_stylebox(
		Color(ThemeColors.PLASMA_CYAN, 0.15),
		ThemeColors.PLASMA_CYAN
	)
	theme.set_stylebox("pressed", "Button", pressed)

	# Focus
	var focus := _make_stylebox(ThemeColors.DEEP_VOID, ThemeColors.PLASMA_CYAN)
	theme.set_stylebox("focus", "Button", focus)

	# Disabled
	var disabled := _make_stylebox(
		Color(ThemeColors.DEEP_VOID, 0.5),
		Color(ThemeColors.DIM_GREY, 0.3)
	)
	theme.set_stylebox("disabled", "Button", disabled)


# ── LineEdit ─────────────────────────────────────────────────────────

func _theme_line_edit() -> void:
	theme.set_font("font", "LineEdit", font_jetbrains)
	theme.set_font_size("font_size", "LineEdit", ThemeColors.FONT_SIZE_MD)

	theme.set_color("font_color", "LineEdit", ThemeColors.STAR_WHITE)
	theme.set_color("font_placeholder_color", "LineEdit", ThemeColors.HULL_GREY)
	theme.set_color("font_uneditable_color", "LineEdit", ThemeColors.DIM_GREY)
	theme.set_color("caret_color", "LineEdit", ThemeColors.PLASMA_CYAN)
	theme.set_color("selection_color", "LineEdit", Color(ThemeColors.PLASMA_CYAN, 0.25))

	var normal := _make_stylebox(Color(ThemeColors.SPACE_BLACK, 0.6), ThemeColors.DIM_GREY)
	theme.set_stylebox("normal", "LineEdit", normal)

	var focus := _make_stylebox(Color(ThemeColors.SPACE_BLACK, 0.6), ThemeColors.PLASMA_CYAN)
	theme.set_stylebox("focus", "LineEdit", focus)

	var read_only := _make_stylebox(
		Color(ThemeColors.SPACE_BLACK, 0.5),
		Color(ThemeColors.DIM_GREY, 0.3)
	)
	theme.set_stylebox("read_only", "LineEdit", read_only)


# ── TextEdit ─────────────────────────────────────────────────────────

func _theme_text_edit() -> void:
	theme.set_font("font", "TextEdit", font_jetbrains)
	theme.set_font_size("font_size", "TextEdit", ThemeColors.FONT_SIZE_MD)

	theme.set_color("font_color", "TextEdit", ThemeColors.STAR_WHITE)
	theme.set_color("font_placeholder_color", "TextEdit", ThemeColors.HULL_GREY)
	theme.set_color("font_readonly_color", "TextEdit", ThemeColors.DIM_GREY)
	theme.set_color("caret_color", "TextEdit", ThemeColors.PLASMA_CYAN)
	theme.set_color("selection_color", "TextEdit", Color(ThemeColors.PLASMA_CYAN, 0.25))

	var normal := _make_stylebox(Color(ThemeColors.SPACE_BLACK, 0.6), ThemeColors.DIM_GREY)
	theme.set_stylebox("normal", "TextEdit", normal)

	var focus := _make_stylebox(Color(ThemeColors.SPACE_BLACK, 0.6), ThemeColors.PLASMA_CYAN)
	theme.set_stylebox("focus", "TextEdit", focus)

	var read_only := _make_stylebox(
		Color(ThemeColors.SPACE_BLACK, 0.5),
		Color(ThemeColors.DIM_GREY, 0.3)
	)
	theme.set_stylebox("read_only", "TextEdit", read_only)


# ── Panel / PanelContainer ──────────────────────────────────────────

func _theme_panel() -> void:
	theme.set_stylebox("panel", "Panel", _make_stylebox(Color(ThemeColors.SPACE_BLACK, 0.86), Color(ThemeColors.PLASMA_CYAN, 0.22), 4, 0))


func _theme_panel_container() -> void:
	theme.set_stylebox("panel", "PanelContainer", _make_stylebox(Color(ThemeColors.SPACE_BLACK, 0.86), Color(ThemeColors.PLASMA_CYAN, 0.22), 4, 6))


# ── TabContainer ─────────────────────────────────────────────────────

func _theme_tab_container() -> void:
	theme.set_font("font", "TabContainer", font_jetbrains_medium)
	theme.set_font_size("font_size", "TabContainer", ThemeColors.FONT_SIZE_SM)

	theme.set_color("font_selected_color", "TabContainer", ThemeColors.PLASMA_CYAN)
	theme.set_color("font_hovered_color", "TabContainer", ThemeColors.PLASMA_CYAN)
	theme.set_color("font_unselected_color", "TabContainer", ThemeColors.HULL_GREY)

	# Selected tab
	var tab_selected := StyleBoxFlat.new()
	tab_selected.bg_color = Color(ThemeColors.PLASMA_CYAN, 0.08)
	tab_selected.border_color = Color.TRANSPARENT
	tab_selected.set_border_width_all(0)
	tab_selected.border_width_bottom = 2
	tab_selected.border_color = ThemeColors.PLASMA_CYAN
	tab_selected.set_corner_radius_all(0)
	tab_selected.set_content_margin_all(6)
	tab_selected.content_margin_bottom = 4
	tab_selected.content_margin_top = 4
	theme.set_stylebox("tab_selected", "TabContainer", tab_selected)

	# Hovered tab
	var tab_hovered := StyleBoxFlat.new()
	tab_hovered.bg_color = Color(ThemeColors.PLASMA_CYAN, 0.05)
	tab_hovered.set_border_width_all(0)
	tab_hovered.set_corner_radius_all(0)
	tab_hovered.set_content_margin_all(6)
	tab_hovered.content_margin_bottom = 4
	tab_hovered.content_margin_top = 4
	theme.set_stylebox("tab_hovered", "TabContainer", tab_hovered)

	# Unselected tab
	var tab_unselected := StyleBoxFlat.new()
	tab_unselected.bg_color = Color.TRANSPARENT
	tab_unselected.set_border_width_all(0)
	tab_unselected.set_corner_radius_all(0)
	tab_unselected.set_content_margin_all(6)
	tab_unselected.content_margin_bottom = 4
	tab_unselected.content_margin_top = 4
	theme.set_stylebox("tab_unselected", "TabContainer", tab_unselected)

	# Tab bar background
	var tabbar_bg := StyleBoxFlat.new()
	tabbar_bg.bg_color = Color(ThemeColors.SPACE_BLACK, 0.95)
	tabbar_bg.set_border_width_all(0)
	tabbar_bg.border_width_bottom = 1
	tabbar_bg.border_color = ThemeColors.DIM_GREY
	theme.set_stylebox("tabbar_background", "TabContainer", tabbar_bg)

	# Content panel
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color(ThemeColors.DEEP_VOID, 0.8)
	panel.border_color = Color(ThemeColors.DIM_GREY, 0.5)
	panel.set_border_width_all(1)
	panel.border_width_top = 0
	panel.set_corner_radius_all(0)
	panel.set_content_margin_all(4)
	theme.set_stylebox("panel", "TabContainer", panel)


# ── ScrollContainer / ScrollBars ────────────────────────────────────

func _theme_scroll_container() -> void:
	var panel := StyleBoxEmpty.new()
	theme.set_stylebox("panel", "ScrollContainer", panel)


func _theme_h_scroll_bar() -> void:
	_setup_scrollbar("HScrollBar")


func _theme_v_scroll_bar() -> void:
	_setup_scrollbar("VScrollBar")


func _setup_scrollbar(type_name: String) -> void:
	# Grabber (the draggable part)
	var grabber := StyleBoxFlat.new()
	grabber.bg_color = Color(ThemeColors.HULL_GREY, 0.5)
	grabber.set_corner_radius_all(3)
	grabber.set_content_margin_all(3)
	theme.set_stylebox("grabber", type_name, grabber)

	var grabber_hover := StyleBoxFlat.new()
	grabber_hover.bg_color = Color(ThemeColors.PLASMA_CYAN, 0.5)
	grabber_hover.set_corner_radius_all(3)
	grabber_hover.set_content_margin_all(3)
	theme.set_stylebox("grabber_highlight", type_name, grabber_hover)

	var grabber_pressed := StyleBoxFlat.new()
	grabber_pressed.bg_color = Color(ThemeColors.PLASMA_CYAN, 0.7)
	grabber_pressed.set_corner_radius_all(3)
	grabber_pressed.set_content_margin_all(3)
	theme.set_stylebox("grabber_pressed", type_name, grabber_pressed)

	# Scroll track
	var scroll := StyleBoxFlat.new()
	scroll.bg_color = Color(ThemeColors.SPACE_BLACK, 0.5)
	scroll.set_corner_radius_all(3)
	scroll.set_content_margin_all(3)
	theme.set_stylebox("scroll", type_name, scroll)


# ── OptionButton ─────────────────────────────────────────────────────

func _theme_option_button() -> void:
	theme.set_font("font", "OptionButton", font_jetbrains)
	theme.set_font_size("font_size", "OptionButton", ThemeColors.FONT_SIZE_SM)
	theme.set_color("font_color", "OptionButton", ThemeColors.CHROME_SILVER)
	theme.set_color("font_hover_color", "OptionButton", ThemeColors.PLASMA_CYAN)
	theme.set_color("font_focus_color", "OptionButton", ThemeColors.PLASMA_CYAN)

	var normal := _make_stylebox(ThemeColors.DEEP_VOID, ThemeColors.DIM_GREY)
	theme.set_stylebox("normal", "OptionButton", normal)

	var hover := _make_stylebox(
		Color(ThemeColors.PLASMA_CYAN, 0.08),
		ThemeColors.PLASMA_CYAN
	)
	theme.set_stylebox("hover", "OptionButton", hover)

	var pressed := _make_stylebox(
		Color(ThemeColors.PLASMA_CYAN, 0.15),
		ThemeColors.PLASMA_CYAN
	)
	theme.set_stylebox("pressed", "OptionButton", pressed)

	var focus := _make_stylebox(ThemeColors.DEEP_VOID, ThemeColors.PLASMA_CYAN)
	theme.set_stylebox("focus", "OptionButton", focus)


# ── CheckButton ──────────────────────────────────────────────────────

func _theme_check_button() -> void:
	theme.set_font("font", "CheckButton", font_jetbrains)
	theme.set_font_size("font_size", "CheckButton", ThemeColors.FONT_SIZE_SM)
	theme.set_color("font_color", "CheckButton", ThemeColors.CHROME_SILVER)
	theme.set_color("font_hover_color", "CheckButton", ThemeColors.PLASMA_CYAN)
	theme.set_color("font_pressed_color", "CheckButton", ThemeColors.PLASMA_CYAN)


# ── ItemList ─────────────────────────────────────────────────────────

func _theme_item_list() -> void:
	theme.set_font("font", "ItemList", font_jetbrains)
	theme.set_font_size("font_size", "ItemList", ThemeColors.FONT_SIZE_SM)

	theme.set_color("font_color", "ItemList", ThemeColors.CHROME_SILVER)
	theme.set_color("font_hovered_color", "ItemList", ThemeColors.PLASMA_CYAN)
	theme.set_color("font_selected_color", "ItemList", ThemeColors.STAR_WHITE)

	var selected := StyleBoxFlat.new()
	selected.bg_color = Color(ThemeColors.PLASMA_CYAN, 0.15)
	selected.set_border_width_all(0)
	selected.set_corner_radius_all(2)
	theme.set_stylebox("selected", "ItemList", selected)

	var hovered := StyleBoxFlat.new()
	hovered.bg_color = Color(ThemeColors.PLASMA_CYAN, 0.05)
	hovered.set_border_width_all(0)
	hovered.set_corner_radius_all(2)
	theme.set_stylebox("hovered", "ItemList", hovered)

	var panel := StyleBoxFlat.new()
	panel.bg_color = Color(ThemeColors.DEEP_VOID, 0.8)
	panel.border_color = Color(ThemeColors.DIM_GREY, 0.6)
	panel.set_border_width_all(1)
	panel.set_corner_radius_all(6)
	theme.set_stylebox("panel", "ItemList", panel)


# ── PopupMenu ────────────────────────────────────────────────────────

func _theme_popup_menu() -> void:
	theme.set_font("font", "PopupMenu", font_jetbrains)
	theme.set_font_size("font_size", "PopupMenu", ThemeColors.FONT_SIZE_SM)

	theme.set_color("font_color", "PopupMenu", ThemeColors.CHROME_SILVER)
	theme.set_color("font_hover_color", "PopupMenu", ThemeColors.PLASMA_CYAN)
	theme.set_color("font_separator_color", "PopupMenu", ThemeColors.HULL_GREY)

	var panel := StyleBoxFlat.new()
	panel.bg_color = Color(ThemeColors.DEEP_VOID, 0.96)
	panel.border_color = ThemeColors.DIM_GREY
	panel.set_border_width_all(1)
	panel.set_corner_radius_all(8)
	panel.set_content_margin_all(4)
	theme.set_stylebox("panel", "PopupMenu", panel)

	var hover := StyleBoxFlat.new()
	hover.bg_color = Color(ThemeColors.PLASMA_CYAN, 0.08)
	hover.set_border_width_all(0)
	hover.set_corner_radius_all(2)
	theme.set_stylebox("hover", "PopupMenu", hover)


# ── Tooltip ──────────────────────────────────────────────────────────

func _theme_tooltip() -> void:
	theme.set_font("font", "TooltipLabel", font_jetbrains)
	theme.set_font_size("font_size", "TooltipLabel", ThemeColors.FONT_SIZE_SM)
	theme.set_color("font_color", "TooltipLabel", ThemeColors.STAR_WHITE)

	var panel := StyleBoxFlat.new()
	panel.bg_color = Color(ThemeColors.DEEP_VOID, 0.95)
	panel.border_color = ThemeColors.DIM_GREY
	panel.set_border_width_all(1)
	panel.set_corner_radius_all(6)
	panel.set_content_margin_all(6)
	theme.set_stylebox("panel", "TooltipPanel", panel)


# ── Separators ───────────────────────────────────────────────────────

func _theme_separator() -> void:
	var h_sep := StyleBoxFlat.new()
	h_sep.bg_color = ThemeColors.SEPARATOR
	h_sep.set_content_margin_all(0)
	h_sep.content_margin_top = 4
	h_sep.content_margin_bottom = 4
	theme.set_stylebox("separator", "HSeparator", h_sep)
	theme.set_constant("separation", "HSeparator", 1)

	var v_sep := StyleBoxFlat.new()
	v_sep.bg_color = ThemeColors.SEPARATOR
	v_sep.set_content_margin_all(0)
	v_sep.content_margin_left = 4
	v_sep.content_margin_right = 4
	theme.set_stylebox("separator", "VSeparator", v_sep)
	theme.set_constant("separation", "VSeparator", 1)


# ── ProgressBar ──────────────────────────────────────────────────────

func _theme_progress_bar() -> void:
	theme.set_font("font", "ProgressBar", font_jetbrains)
	theme.set_font_size("font_size", "ProgressBar", ThemeColors.FONT_SIZE_SM)
	theme.set_color("font_color", "ProgressBar", ThemeColors.STAR_WHITE)

	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(ThemeColors.SPACE_BLACK, 0.8)
	bg.border_color = Color(ThemeColors.DIM_GREY, 0.6)
	bg.set_border_width_all(1)
	bg.set_corner_radius_all(2)
	theme.set_stylebox("background", "ProgressBar", bg)
	theme.set_stylebox("fill", "ProgressBar", bar_fill(ThemeColors.PLASMA_CYAN))


## Fill style for a ProgressBar in one colour; the HUD gives each ship bar its own.
static func bar_fill(color: Color) -> StyleBoxFlat:
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	fill.set_corner_radius_all(2)
	return fill


# ── Helpers ──────────────────────────────────────────────────────────

func _make_stylebox(bg: Color, border: Color, radius: int = 6, margin: int = 6) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(radius)
	sb.set_content_margin_all(margin)
	return sb
