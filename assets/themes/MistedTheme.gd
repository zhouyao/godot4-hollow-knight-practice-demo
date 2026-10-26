extends Theme
class_name MistedTheme


const VARIATION_DISPLAY := "DisplayLabel"
const VARIATION_TITLE := "TitleLabel"
const VARIATION_MUTED := "MutedLabel"
const VARIATION_HINT := "HintLabel"
const VARIATION_ROW_BUTTON := "RowButton"

const FONT_LATIN_PATH := "res://assets/font/TrajanPro.ttf"
const FONT_CJK_REGULAR_PATH := "res://assets/font/SourceHanSerifCN-Regular.otf"
const FONT_CJK_BOLD_PATH := "res://assets/font/SourceHanSerifCN-Bold.otf"

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
	# 加载字体
	var latin := load(FONT_LATIN_PATH) as FontFile
	var cjk_regular := load(FONT_CJK_REGULAR_PATH) as FontFile
	var cjk_bold := load(FONT_CJK_BOLD_PATH) as FontFile

	# 拉丁文（TrajanPro）为主，中文（思源宋体）兜底，缺字自动回退
	var font_regular := FontVariation.new()
	font_regular.base_font = latin
	font_regular.set_fallbacks([cjk_regular])

	var font_bold := FontVariation.new()
	font_bold.base_font = latin
	font_bold.set_fallbacks([cjk_bold])

	set_type_variation(VARIATION_DISPLAY, "Label")
	set_type_variation(VARIATION_TITLE, "Label")
	set_type_variation(VARIATION_MUTED, "Label")
	set_type_variation(VARIATION_HINT, "Label")
	set_type_variation(VARIATION_ROW_BUTTON, "Button")

	# 常规字体：套到所有基础控件类型（中文走思源宋体 Regular）
	set_font("font", "Label", font_regular)
	set_font("font", "LineEdit", font_regular)
	set_font("font", "TextEdit", font_regular)
	set_font("font", "PopupMenu", font_regular)
	set_font("font", "MenuButton", font_regular)
	set_font("font", "OptionButton", font_regular)
	set_font("font", "Tree", font_regular)
	set_font("font", "ItemList", font_regular)
	set_font("font", "TabBar", font_regular)
	set_font("font", "TabContainer", font_regular)
	set_font("font", "SpinBox", font_regular)
	set_font("font", "CheckButton", font_regular)
	set_font("font", "ColorPicker", font_regular)
	set_font("font", "Window", font_regular)
	set_font("font", "AcceptDialog", font_regular)
	set_font("normal_font", "RichTextLabel", font_regular)

	# 粗体变体：标题 / 按钮 / 大显示字 用真粗体中文（思源宋体 Bold）
	set_font("font", VARIATION_DISPLAY, font_bold)
	set_font("font", VARIATION_TITLE, font_bold)
	set_font("font", "Button", font_bold)
	set_font("font", VARIATION_ROW_BUTTON, font_bold)
	set_font("bold_font", "RichTextLabel", font_bold)

	# 字号 / 颜色（沿用原有配置）
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
