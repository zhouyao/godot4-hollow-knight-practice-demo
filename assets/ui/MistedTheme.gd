extends Theme
class_name MistedTheme

# 菜单的统一外观，字号与颜色集中在这里定义，场景里不再逐节点写 theme_override。
# Theme 资源本身无法序列化 type variation，所以挂到一个 .tres 上，在 _init() 里注册后才生效。

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

	# OptionButton 继承 Button 的 80 号字会撑爆行高，行内统一挂 RowButton 变体；
	# 展开后的菜单项走 PopupMenu，默认 16 号字在小屏上偏小，这里一并对齐到行高
	set_font_size("font_size", "PopupMenu", FONT_SIZE_ROW)

	set_font_size("font_size", "Button", FONT_SIZE_BUTTON)
	set_color("font_color", "Button", COLOR_TEXT)
