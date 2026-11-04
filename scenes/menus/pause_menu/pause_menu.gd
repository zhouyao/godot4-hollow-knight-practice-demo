extends CanvasLayer

# 暂停菜单：由 WorldTemplate 在按 Esc 时实例化并 add_child 到世界节点下。
# 自身的 process_mode 在 WorldTemplate.open_pause 中被设为 ALWAYS，
# 所以即使 SceneTree 已暂停，仍正常处理输入与按钮回调。
# 两个面板：主面板（继续 / 音频 / 退回主菜单）与音频面板（内嵌 AudioContent）。
# “退回主菜单”不直接切场景，先弹一次确认（复用 quit_menu，复刻 HK 的 quit_pause_menu）。
# 样式/动效对齐 HK 原版：按钮用 menu_button（文字两侧指针花纹，聚焦浮出/失焦收起），
# 按钮组上下各一条 fleur 单次动画花纹；指针与按钮音效由 FocusButton/UiAudio 负责。

const PREVIEW_STREAM := preload("res://assets/sounds/menus/confirm.ogg")
const QUIT_MENU_SCENE := preload("res://scenes/menus/common/dialogs/quit_menu.tscn")

@onready var main_panel: VBoxContainer = $Margin/Center/MainPanel
@onready var audio_panel: VBoxContainer = $Margin/Center/AudioPanel
@onready var continue_button: FocusButton = $Margin/Center/MainPanel/ButtonContainer/ContinueButton
@onready var back_button: FocusButton = $Margin/Center/AudioPanel/BackButton
@onready var preview_player: AudioStreamPlayer = $PreviewPlayer
@onready var fleurs: Array[AnimatedSprite2D] = [
	$Margin/Center/MainPanel/TopFleur/Fleur,
	$Margin/Center/MainPanel/BottomFleur/Fleur,
]

var _quit_menu: QuitMenu

func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	Tr.apply(self)
	continue_button.quiet_focus()
	Settings.volume.volume_committed.connect(_on_volume_preview)

func _exit_tree() -> void:
	if Settings.volume.volume_committed.is_connected(_on_volume_preview):
		Settings.volume.volume_committed.disconnect(_on_volume_preview)

# 恢复游戏并销毁自身，供继续按钮与 Esc 复用
func resume() -> void:
	if get_tree().paused:
		get_tree().paused = false
	queue_free()

func _on_continue_pressed() -> void:
	resume()

func _on_audio_pressed() -> void:
	show_audio()

# 复刻 HK 的 quit_pause_menu：先隐藏主面板、弹出确认，确认后才真的离开本关。
# 弹窗挂在本 CanvasLayer 上（而不是 MainPanel 里），避免跟着主面板一起被隐藏。
func _on_main_menu_pressed() -> void:
	if is_instance_valid(_quit_menu):
		return
	main_panel.visible = false
	_quit_menu = QUIT_MENU_SCENE.instantiate()
	_quit_menu.title_text = "退回主菜单？"
	_quit_menu.subtitle_text = "当前进度不会保留"
	add_child(_quit_menu)
	_quit_menu.confirmed.connect(_on_quit_confirmed)
	_quit_menu.closed.connect(_on_quit_menu_closed)


func _on_quit_confirmed() -> void:
	# 不在这里解除暂停：交给 TransitionLayer 在黑场结束后统一恢复，
	# 否则淡出的 1 秒里世界继续跑，空中的角色会继续下落
	Globals.go_to_main_menu()
	queue_free()


func _on_quit_menu_closed() -> void:
	_quit_menu = null
	show_main()

func _on_back_pressed() -> void:
	show_main()

func show_audio() -> void:
	main_panel.visible = false
	audio_panel.visible = true
	back_button.quiet_focus()

func show_main() -> void:
	audio_panel.visible = false
	main_panel.visible = true
	play_fleurs()
	continue_button.quiet_focus()

# 花纹是单次动画：首次打开由 autoplay 播，从音频面板返回时重播（对齐 HK 每次显示都重放）
func play_fleurs() -> void:
	for fleur: AnimatedSprite2D in fleurs:
		fleur.stop()
		fleur.frame = 0
		fleur.play(&"default")

# 一次音量调节结束（松手 / 重置 / 静止超时）时播放预览音，反馈当前总线音量
func _on_volume_preview(bus_name: String) -> void:
	preview_player.bus = bus_name
	preview_player.stream = PREVIEW_STREAM
	preview_player.play()

# Esc：在音频面板时返回主面板，否则继续游戏
func _unhandled_input(event: InputEvent) -> void:
	if !event.is_action_pressed("ui_cancel"):
		return
	# 确认弹窗打开时 Esc 只关弹窗（由弹窗自己处理），不能顺手把游戏继续掉
	if is_instance_valid(_quit_menu):
		return
	get_viewport().set_input_as_handled()
	if audio_panel.visible:
		show_main()
	else:
		resume()
