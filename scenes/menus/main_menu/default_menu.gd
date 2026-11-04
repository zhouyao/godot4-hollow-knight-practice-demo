extends Control

# 场景专属薄逻辑：处理主菜单按钮导航，无复用需求。
# 按钮统一接 pressed：确认音由 autoload 上的 UiAudio 播放，切场景不会把它掐断，
# 因此按下即可跳转，不需要等音效放完。

const QUIT_MENU_SCENE := preload("res://scenes/menus/common/dialogs/quit_menu.tscn")

@onready var _buttons: VBoxContainer = $VBoxContainer/VBoxContainer
@onready var _quit_button: FocusMenuButton = $VBoxContainer/VBoxContainer/QuitButton

var _quit_menu: QuitMenu


func _ready() -> void:
	Tr.apply(self)
	Settings.localization.locale_changed.connect(_on_locale_changed)
	# 其它菜单（设置/暂停）进入时都会 quiet_focus 一个按钮，只有主菜单没有，
	# 导致从游戏（鼠标受限/隐藏）返回后，首个点击常被吞掉、需再点一次。
	# 主动聚焦首个按钮，让 GUI 输入系统就位，进入即可用鼠标/键盘正常交互。
	var start := _buttons.get_node("StartButton")
	if start is FocusButton:
		start.quiet_focus()


func _exit_tree() -> void:
	if Settings.localization.locale_changed.is_connected(_on_locale_changed):
		Settings.localization.locale_changed.disconnect(_on_locale_changed)


# 语言切换后重刷文案并重贴指针：字体由主题保证——TrajanPro 只有拉丁字形，
# 中文/繁体自动回退到 assets/font 下的思源宋体。
func _on_locale_changed(_locale: String) -> void:
	Tr.apply(self)
	for button in _buttons.get_children():
		if button is FocusMenuButton:
			button.refresh_pointer_layout()


func _on_start_pressed() -> void:
	Globals.go_to_game()


func _on_system_button_pressed() -> void:
	Globals.go_to_system_settings()


# 复刻 HK：先弹确认（警告花纹 + 退出游戏？+ 是/否），确认后才真正退出。
# 弹窗挂到主菜单根层（CanvasLayer）而不是自己名下：本菜单要先 hide，
# 否则标题和按钮会透在弹窗背后（HK 原版同样先隐藏主菜单）。
func _on_quit_button_pressed() -> void:
	if is_instance_valid(_quit_menu):
		return
	hide()
	_quit_menu = QUIT_MENU_SCENE.instantiate()
	get_parent().add_child(_quit_menu)
	_quit_menu.confirmed.connect(_on_quit_confirmed)
	_quit_menu.closed.connect(_on_quit_menu_closed)


func _on_quit_confirmed() -> void:
	Globals.quit_game()


func _on_quit_menu_closed() -> void:
	_quit_menu = null
	show()
	_quit_button.quiet_focus()
