extends Button
class_name ResetButton

# 设置菜单里的“恢复默认”按钮：图标、尺寸与显隐方式只有这一处定义。
# 音量行的重置、按键行的键盘/手柄重置都实例化它，表头的占位宽度也读同一个 SIZE。

# reset.svg 本身就是 24x24，这里给足两轴：
# 开了 expand_icon 后按钮的 minimum size 不再计入图标尺寸，只给 x 会把按钮压成一条缝
const SIZE := 40.0

const RESET_ICON := preload("res://assets/icons/reset.svg")


func _ready() -> void:
	icon = RESET_ICON
	custom_minimum_size = Vector2(SIZE, SIZE)
	expand_icon = true
	# 始终占位，避免出现/消失时整行布局抖动；具体状态由所属行在 _ready 里刷新
	set_available(false)


func set_available(enabled: bool) -> void:
	disabled = !enabled
	modulate.a = 1.0 if enabled else 0.0
