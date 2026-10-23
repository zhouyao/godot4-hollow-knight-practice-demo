extends Theme
class_name MistedTheme


const VARIATION_DISPLAY := "DisplayLabel"
const VARIATION_TITLE := "TitleLabel"
const VARIATION_MUTED := "MutedLabel"
const VARIATION_HINT := "HintLabel"
const VARIATION_ROW_BUTTON := "RowButton"

const FONT_SIZE_DISPLAY := 100
const FONT_SIZE_TITLE := 56
const FONT_SIZE_ROW := 38
const FONT_SIZE_MUTED := 30
const FONT_SIZE_HINT := 24
const FONT_SIZE_ROW_BUTTON := 30
const FONT_SIZE_BUTTON := 80

const COLOR_TEXT := Color(0.95, 0.95, 0.95)
const COLOR_MUTED := Color(0.7, 0.72, 0.78)
const COLOR_HINT := Color(0.86, 0.72, 0.44)

func _init() -> void:
	set_type_variation(VARIATION_DISPLAY, "Label")
	set_type_variation(VARIATION_TITLE, "Label")
	set_type_variation(VARIATION_MUTED, "Label")
	set_type_variation(VARIATION_HINT, "Label")
	set_type_variation(VARIATION_ROW_BUTTON, "Button")

	set_font_size("font_size", "Label", FONT_SIZE_ROW)
	set_color("font_color", "Label", COLOR_TEXT)

	set_font_size("font_size", VARIATION_DISPLAY, FONT_SIZE_DISPLAY)
	set_font_size("font_size", VARIATION_TITLE, FONT_SIZE_TITLE)
	set_font_size("font_size", VARIATION_MUTED, FONT_SIZE_MUTED)
	set_color("font_color", VARIATION_MUTED, COLOR_MUTED)
	set_font_size("font_size", VARIATION_HINT, FONT_SIZE_HINT)
	set_color("font_color", VARIATION_HINT, COLOR_HINT)

	set_font_size("font_size", VARIATION_ROW_BUTTON, FONT_SIZE_ROW_BUTTON)

	set_font_size("font_size", "PopupMenu", FONT_SIZE_ROW)

	set_font_size("font_size", "Button", FONT_SIZE_BUTTON)
	set_color("font_color", "Button", COLOR_TEXT)

	var pb_bg := StyleBoxFlat.new()
	pb_bg.bg_color = Color(0.12, 0.12, 0.12)
	var pb_fill := StyleBoxFlat.new()
	pb_fill.bg_color = Color(0.85, 0.85, 0.85)
	set_stylebox("background", "ProgressBar", pb_bg)
	set_stylebox("fill", "ProgressBar", pb_fill)
