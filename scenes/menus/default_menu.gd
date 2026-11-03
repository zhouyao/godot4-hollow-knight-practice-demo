extends Control

# 场景专属薄逻辑：处理主菜单按钮导航，无复用需求。
# 按钮统一接 pressed：确认音由 autoload 上的 UiAudio 播放，切场景不会把它掐断，
# 因此按下即可跳转，不需要等音效放完。

func _ready() -> void:
	Tr.apply(self)
	# 其它菜单（设置/暂停）进入时都会 quiet_focus 一个按钮，只有主菜单没有，
	# 导致从游戏（鼠标受限/隐藏）返回后，首个点击常被吞掉、需再点一次。
	# 主动聚焦首个按钮，让 GUI 输入系统就位，进入即可用鼠标/键盘正常交互。
	var start := $LogoContainer/ButtonContainer/StartButton
	if start is FocusButton:
		start.quiet_focus()

func _on_start_pressed() -> void:
	Globals.go_to_game()

func _on_system_button_pressed() -> void:
	Globals.go_to_system_settings()

func _on_quit_button_pressed() -> void:
	Globals.quit_game()
