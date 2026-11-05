extends Control

## 存档选择页（复刻 HK 的 start_game_menu）：
## 标题 + 花纹 + 4 个存档槽 + 返回。由主菜单“开始游戏”实例化挂到 MainMenu 根层下。
## 点空槽 = 新建存档并进入关卡；点已有槽 = 读档进入；清档在行内二次确认。

signal back

@onready var _profiles: VBoxContainer = $VBox/Content/Profiles
@onready var _back_button: FocusMenuButton = $VBox/Content/BackButton
@onready var _fleur: AnimatedSprite2D = $VBox/Header/Fleur/Sprite

var _busy := false


func _ready() -> void:
	Tr.apply(self)
	Settings.localization.locale_changed.connect(_on_locale_changed)
	for row in _profiles.get_children():
		if row is SaveRow:
			row.load_requested.connect(_on_load_requested)
	_back_button.quiet_focus()
	play_fleur()


func _exit_tree() -> void:
	if Settings.localization.locale_changed.is_connected(_on_locale_changed):
		Settings.localization.locale_changed.disconnect(_on_locale_changed)


func play_fleur() -> void:
	_fleur.stop()
	_fleur.frame = 0
	_fleur.play(&"default")


func _on_locale_changed(_locale: String) -> void:
	Tr.apply(self)


func _on_back_pressed() -> void:
	if _busy:
		return
	hide()
	back.emit()
	queue_free()


func _on_load_requested(slot: int) -> void:
	if _busy:
		return
	_busy = true

	var ok := SaveManager.load_game(slot) if SaveManager.has_slot(slot) else false
	if not ok:
		# 空槽（或文件损坏读不出来）按新建处理。
		ok = SaveManager.new_game(slot)
	if not ok:
		_busy = false
		return

	# 进的是常驻根场景，具体加载哪块区域由 GameSession 读存档决定
	TransitionLayer.change_scene(Globals.GAME_SCENE_PATH)


func _unhandled_input(event: InputEvent) -> void:
	if !event.is_action_pressed(&"ui_cancel"):
		return
	get_viewport().set_input_as_handled()
	_on_back_pressed()
