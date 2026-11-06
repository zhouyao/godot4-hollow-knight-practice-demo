extends VBoxContainer

# 「开发」页：调试模式开关 + 首页路径。内容与状态都由 Settings.development 提供，
# 这里只负责控件的构建、同步与语言切换后的重建。

const OFF_TEXT := "关闭"
const ON_TEXT := "开启"

## 首页路径行的提示文案：同时也是 translations.csv 里的 key。
const HINT_IDLE := "新建存档时进入的场景；按回车或点击别处生效，已有存档不受影响"
const HINT_SAVED := "已保存：新建存档将从该场景开始"
const HINT_INVALID := "路径不存在，请输入已存在的 .tscn 场景路径"

@onready var debug_mode_option: OptionButton = $DebugModeRow/DebugModeOption
@onready var home_path_edit: LineEdit = $HomePathRow/HomePathEdit
@onready var home_path_reset: ResetButton = $HomePathRow/HomePathReset
@onready var home_path_hint: Label = $HomePathHint

var _hint_source := HINT_IDLE


func _ready() -> void:
	_build_options()
	Settings.development.debug_mode_changed.connect(_on_debug_mode_changed)
	Settings.development.home_path_changed.connect(_on_home_path_changed)
	Settings.localization.locale_changed.connect(_on_locale_changed)
	home_path_edit.text_submitted.connect(_on_home_path_text_submitted)
	home_path_edit.focus_exited.connect(_on_home_path_focus_exited)
	home_path_reset.pressed.connect(_on_home_path_reset_pressed)
	_sync_option()
	_sync_home_path()
	_set_hint(HINT_IDLE)


func _exit_tree() -> void:
	if Settings.development.debug_mode_changed.is_connected(_on_debug_mode_changed):
		Settings.development.debug_mode_changed.disconnect(_on_debug_mode_changed)
	if Settings.development.home_path_changed.is_connected(_on_home_path_changed):
		Settings.development.home_path_changed.disconnect(_on_home_path_changed)
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


# ---------------------------------------------------------------- 首页路径

func _sync_home_path() -> void:
	var path := Settings.development.get_home_path()
	if not home_path_edit.has_focus() and home_path_edit.text != path:
		home_path_edit.text = path
	home_path_reset.set_available(path != DevelopmentSection.DEFAULT_HOME_PATH)


func _on_home_path_text_submitted(_text: String) -> void:
	_commit_home_path()


func _on_home_path_focus_exited() -> void:
	_commit_home_path()


## 输入只在回车 / 失焦时提交，避免每敲一个字符就写一次配置。
## 校验放在 DevelopmentSection：坏路径不落盘，输入框恢复成上一次有效值。
func _commit_home_path() -> void:
	var typed := home_path_edit.text.strip_edges()
	var path := Settings.development.get_home_path()
	if typed == path:
		home_path_edit.text = path
		_set_hint(HINT_IDLE)
		return
	if Settings.development.set_home_path(typed):
		home_path_edit.text = typed
		_set_hint(HINT_SAVED)
		return
	_set_hint(HINT_INVALID)
	_sync_home_path()


func _on_home_path_changed(_path: String) -> void:
	_sync_home_path()


func _on_home_path_reset_pressed() -> void:
	Settings.development.reset_home_path()
	_sync_home_path()
	_set_hint(HINT_SAVED)


## HintLabel 的文案是动态的：Tr.apply 会把 meta 当作源文本，先同步再翻译，
## 否则切换语言后会被还原成场景里的初始文案。
func _set_hint(source: String) -> void:
	_hint_source = source
	home_path_hint.set_meta(Tr.SOURCE_META, source)
	home_path_hint.text = tr(source)


func _on_locale_changed(_locale: String) -> void:
	_build_options()
	_sync_option()
	_sync_home_path()
	_set_hint(_hint_source)
