extends Control

# 场景专属薄逻辑：左侧 tab 切换右侧内容 + 音量预览音，无复用需求。
# 五个内容面板已拆成独立场景（OperationsContent / AudioContent / LanguageContent /
# DisplayContent / DevelopmentContent），各页的下拉框逻辑随各自的面板脚本走。

const PREVIEW_STREAM := preload("res://assets/sounds/menus/confirm.ogg")

@onready var tab_operations: FocusButton = $Margin/Columns/TabList/TabOperations
@onready var tab_audio: FocusButton = $Margin/Columns/TabList/TabAudio
@onready var tab_language: FocusButton = $Margin/Columns/TabList/TabLanguage
@onready var tab_display: FocusButton = $Margin/Columns/TabList/TabDisplay
@onready var tab_development: FocusButton = $Margin/Columns/TabList/TabDevelopment

@onready var operations_content: Control = $Margin/Columns/ContentPanel/OperationsContent
@onready var audio_content: AudioContent = $Margin/Columns/ContentPanel/AudioContent
@onready var language_content: Control = $Margin/Columns/ContentPanel/LanguageContent
@onready var display_content: Control = $Margin/Columns/ContentPanel/DisplayContent
@onready var development_content: Control = $Margin/Columns/ContentPanel/DevelopmentContent

@onready var preview_player: AudioStreamPlayer = $PreviewPlayer

func _ready() -> void:
	tab_operations.pressed.connect(_on_tab_pressed.bind("operations"))
	tab_audio.pressed.connect(_on_tab_pressed.bind("audio"))
	tab_language.pressed.connect(_on_tab_pressed.bind("language"))
	tab_display.pressed.connect(_on_tab_pressed.bind("display"))
	tab_development.pressed.connect(_on_tab_pressed.bind("development"))

	Settings.volume.volume_committed.connect(_on_volume_preview)
	Settings.localization.locale_changed.connect(_on_locale_changed)

	_select_tab("operations")
	Tr.apply(self)
	tab_operations.quiet_focus()

	# 由暂停菜单 / 主菜单通过 change_scene 进来：解除暂停并揭开黑场
	get_tree().paused = false
	TransitionLayer.fade_in()

func _exit_tree() -> void:
	if Settings.volume.volume_committed.is_connected(_on_volume_preview):
		Settings.volume.volume_committed.disconnect(_on_volume_preview)
	if Settings.localization.locale_changed.is_connected(_on_locale_changed):
		Settings.localization.locale_changed.disconnect(_on_locale_changed)

# Esc / 手柄取消：正在监听按键时先退出监听，否则返回主菜单
func _unhandled_input(event: InputEvent) -> void:
	if !event.is_action_pressed(&"ui_cancel"):
		return
	get_viewport().set_input_as_handled()
	if get_tree().get_nodes_in_group(KeyBindingRow.LISTENING_GROUP).is_empty():
		Globals.go_to_main_menu()
		return
	KeyBindingRow.stop_all_listening(get_tree())

func _on_tab_pressed(tab: String) -> void:
	KeyBindingRow.stop_all_listening(get_tree())
	_select_tab(tab)

func _select_tab(tab: String) -> void:
	operations_content.visible = tab == "operations"
	audio_content.visible = tab == "audio"
	language_content.visible = tab == "language"
	display_content.visible = tab == "display"
	development_content.visible = tab == "development"

	# 切页时 AudioContent 自己会因可见性变化重放花纹；这里补一次，
	# 保证已经停在音频页时再点“音频”也能重放
	if tab == "audio":
		audio_content.play_intro()

# 切语言后不重载场景：菜单是短命的，把新语言重新套一遍即可。
# 语言下拉框的选中项同步由 LanguageContent 自行处理。
func _on_locale_changed(_locale: String) -> void:
	Tr.apply(self)

# 只在一次调节结束（滑条松手 / 重置）时播放，避免拖动过程中重复触发
func _on_volume_preview(bus_name: String) -> void:
	preview_player.bus = bus_name
	preview_player.stream = PREVIEW_STREAM
	preview_player.play()

func _on_back_button_pressed() -> void:
	Globals.go_to_main_menu()
