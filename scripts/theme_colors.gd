class_name ThemeColors

# SpaceMolt UI color palette — matches www.spacemolt.com design system.
# Use these constants everywhere instead of hardcoded Color() values.

# ── Backgrounds ──────────────────────────────────────────────────────
const SPACE_BLACK := Color(0.039, 0.055, 0.090, 1.0)     # #0a0e17
const DEEP_VOID := Color(0.051, 0.075, 0.129, 1.0)       # #0d1321
const NEBULA_BLUE := Color(0.102, 0.153, 0.267, 1.0)     # #1a2744
const DIM_GREY := Color(0.165, 0.227, 0.290, 1.0)        # #2a3a4a

# ── Accent colors ────────────────────────────────────────────────────
const PLASMA_CYAN := Color(0.0, 0.831, 1.0, 1.0)         # #00d4ff
const LASER_BLUE := Color(0.302, 0.671, 0.969, 1.0)      # #4dabf7
const SHELL_ORANGE := Color(1.0, 0.420, 0.208, 1.0)      # #ff6b35
const CLAW_RED := Color(0.902, 0.224, 0.275, 1.0)        # #e63946
const BIO_GREEN := Color(0.176, 0.831, 0.749, 1.0)       # #2dd4bf
const WARNING_YELLOW := Color(1.0, 0.851, 0.239, 1.0)    # #ffd93d
const VOID_PURPLE := Color(0.608, 0.349, 0.714, 1.0)     # #9b59b6

# ── Neutrals / text ─────────────────────────────────────────────────
const STAR_WHITE := Color(0.910, 0.957, 0.973, 1.0)      # #e8f4f8
const CHROME_SILVER := Color(0.659, 0.773, 0.839, 1.0)   # #a8c5d6
const HULL_GREY := Color(0.420, 0.561, 0.639, 1.0)       # #6b8fa3

# ── Semantic aliases ─────────────────────────────────────────────────
const TEXT_PRIMARY := STAR_WHITE
const TEXT_SECONDARY := CHROME_SILVER
const TEXT_MUTED := HULL_GREY
const TEXT_DISABLED := DIM_GREY
const TEXT_ACCENT := PLASMA_CYAN
const TEXT_ERROR := CLAW_RED
const TEXT_SUCCESS := BIO_GREEN
const TEXT_WARNING := WARNING_YELLOW

const BG_PRIMARY := SPACE_BLACK
const BG_SECONDARY := DEEP_VOID
const BG_PANEL := NEBULA_BLUE
const BG_HOVER := Color(0.0, 0.831, 1.0, 0.08)          # plasma_cyan @ 8%
const BG_SELECTED := Color(0.0, 0.831, 1.0, 0.12)        # plasma_cyan @ 12%

const BORDER_DEFAULT := HULL_GREY
const BORDER_ACCENT := PLASMA_CYAN
const BORDER_SUBTLE := Color(0.0, 0.831, 1.0, 0.2)       # plasma_cyan @ 20%

const SEPARATOR := Color(0.165, 0.227, 0.290, 0.6)        # dim_grey @ 60%

# ── Category colors (action log, etc.) ───────────────────────────────
const CAT_NAVIGATION := PLASMA_CYAN
const CAT_SOCIAL := BIO_GREEN
const CAT_COMBAT := CLAW_RED
const CAT_TRADE := SHELL_ORANGE
const CAT_SYSTEM := CHROME_SILVER
const CAT_DEFAULT := HULL_GREY

# ── Empire colors ────────────────────────────────────────────────────
const EMPIRE_SOLARIAN := Color(1.0, 0.843, 0.0, 1.0)     # #ffd700
const EMPIRE_VOIDBORN := VOID_PURPLE
const EMPIRE_CRIMSON := CLAW_RED
const EMPIRE_NEBULA := PLASMA_CYAN
const EMPIRE_OUTERRIM := BIO_GREEN

# ── Status indicators ───────────────────────────────────────────────
const ACTIVE := BIO_GREEN
const INACTIVE := HULL_GREY
const DANGER := CLAW_RED
const BUY_ORDER := BIO_GREEN
const SELL_ORDER := SHELL_ORANGE

# ── UI element styling ──────────────────────────────────────────────
const PANEL_BG_ALPHA := 0.6
const BAR_BG := Color(0.06, 0.06, 0.1, 0.9)
const MINIMAP_BG := Color(0.0, 0.0, 0.0, 0.5)
const MINIMAP_BORDER := Color(0.2, 0.3, 0.5, 0.4)

# ── Font sizes ───────────────────────────────────────────────────────
const FONT_SIZE_XS := 10
const FONT_SIZE_SM := 12
const FONT_SIZE_MD := 14
const FONT_SIZE_LG := 16
const FONT_SIZE_XL := 20
const FONT_SIZE_H1 := 32
const FONT_SIZE_H2 := 24

# ── Spacing ──────────────────────────────────────────────────────────
const SPACING_XS := 2
const SPACING_SM := 4
const SPACING_MD := 8
const SPACING_LG := 12
const SPACING_XL := 16
