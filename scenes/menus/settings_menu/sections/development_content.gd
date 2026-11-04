extends VBoxContainer

# 「开发」页：调试模式开关。内容与状态都由 Settings.development 提供，
# 这里只负责 OptionButton 的构建、同步与语言切换后的重建。

const OFF_TEXT := "关闭"
const ON_TEXT := "开启"

@onready var debug_mode_option: OptionButton = $DebugModeRow/DebugModeOption

func _ready() -> void:
	_build_options()
	Settings.development.debug_mode_changed.connect(_on_debug_mode_changed)
	Settings.localization.locale_changed.connect(_on_locale_changed)
	_sync_option()

func _exit_tree() -> void:
	if Settings.development.debug_mode_changed.is_connected(_on_debug_mode_changed):
		Settings.development.debug_mode_changed.disconnect(_on_debug_mode_changed)
	if Settings.localization.locale_changed.is_connected(_on_locale_changed):
		Settings.localization.locale_changed.disconnect(_on_locale_changed)

# OptionButton 的 item 文本不会被 Tr.apply 覆盖，切语言后要整表重建
func _build_options() -> void:
	debug_mode_option.clear()
	debug_mode_option.add_item(tr(OFF_TEXT))
	debug_mode_option.add_item(tr(ON_TEXT))

func _sync_option() -> void:
	var index := int(Settings.development.get_debug_mode())
	if debug_mode_option.selected != index:
		debug_mode_option.selected = index

func _on_debug_mode_option_item_selected(index: int) -> void:
	Settings.development.set_debug_mode(index == 1)

func _on_debug_mode_changed(_enabled: bool) -> void:
	_sync_option()

func _on_locale_changed(_locale: String) -> void:
	_build_options()
	_sync_option()
