class_name SaveRow
extends Control

## 单个存档槽（复刻 HK 的 load_game_row）：
##   · 有存档：区域插画 + 关卡名 / 游玩时长 + 生命 / 灵魂 / 钱币摘要 + “清除存档”；
##   · 无存档：同一张插画压暗成“空槽底板”，叠“新游戏”，点整行即新建并进入；
##   · 清档：行内二次确认（是 / 否，默认聚焦“否”）。

signal load_requested(slot: int)

## 插画明暗：有档全亮，空槽压暗，聚焦再提一点。
const TINT_FILLED := Color(1, 1, 1, 1)
const TINT_EMPTY := Color(0.76, 0.82, 0.94, 0.24)
const TINT_FOCUS_FILLED := Color(1.16, 1.16, 1.16, 1)
const TINT_FOCUS_EMPTY := Color(0.92, 0.96, 1, 0.4)

## 焦点指针：与主菜单按钮同一套花纹帧，浮出/沉下两段单次动画。
const ANIM_POINTER_SHOW := &"pointer up"
const ANIM_POINTER_HIDE := &"pointer down"

@export var slot_index: int = 1

@onready var _load_button: FocusButton = $LoadGameButton
@onready var _pointer_left: AnimatedSprite2D = $FocusIconLeft
@onready var _pointer_right: AnimatedSprite2D = $FocusIconRight
@onready var _fleur: AnimatedSprite2D = $Fleur
@onready var _main_display: TextureRect = $LoadGameButton/Margin/MainDisplay
@onready var _new_game_display: Control = $LoadGameButton/Margin/NewGameDisplay
@onready var _game_label: Label = $LoadGameButton/GameMargin/GameLabel
@onready var _details: SavePlayerDetails = $LoadGameButton/Margin/MainDisplay/ContentMargin/Content/Details
@onready var _info: VBoxContainer = $LoadGameButton/Margin/MainDisplay/ContentMargin/Content/Info
@onready var _zone_label: Label = $LoadGameButton/Margin/MainDisplay/ContentMargin/Content/Info/ZoneLabel
@onready var _time_label: Label = $LoadGameButton/Margin/MainDisplay/ContentMargin/Content/Info/TimeLabel
@onready var _clear_button: FocusMenuButton = $ClearSaveButton
@onready var _confirm: Control = $Confirmation
@onready var _deny_button: FocusMenuButton = $Confirmation/Content/DenyButton

var _has_save := false
var _pointers_wanted := false


func _ready() -> void:
	_game_label.text = "%d." % slot_index
	_confirm.visible = false
	_pointer_left.visible = false
	_pointer_right.visible = false
	_pointer_left.animation_finished.connect(_on_pointer_animation_finished)
	_pointer_right.animation_finished.connect(_on_pointer_animation_finished)
	_refresh()
	play_fleur()


func _refresh() -> void:
	var summary := SaveManager.get_summary(slot_index)
	var exists: bool = summary.get("exists", false)
	_has_save = exists

	# 空槽也保留插画做底板（压暗），避免运行时整行只剩一行字，
	# 与编辑器里看到的结构保持一致。
	_main_display.visible = true
	_main_display.modulate = TINT_FILLED if exists else TINT_EMPTY
	_details.visible = exists
	_info.visible = exists
	_new_game_display.visible = not exists
	_clear_button.visible = exists

	if not exists:
		return

	_details.display(summary)
	var zone := String(summary.get("zone", ""))
	_zone_label.text = zone if not zone.is_empty() else "未知区域"
	_time_label.text = SaveManager.format_play_time(float(summary.get("play_time", 0.0)))


## 花纹是单次动画：每次页面出现都重放（同 HK）。
func play_fleur() -> void:
	_fleur.stop()
	_fleur.frame = 0
	_fleur.play(&"default")


func _on_load_game_button_pressed() -> void:
	load_requested.emit(slot_index)


## 聚焦（含鼠标滑入）：两端花纹指针浮出，插画顺带提亮一档。
func _on_load_game_button_focus_entered() -> void:
	_main_display.modulate = TINT_FOCUS_FILLED if _has_save else TINT_FOCUS_EMPTY
	_show_pointers(true)


func _on_load_game_button_focus_exited() -> void:
	_main_display.modulate = TINT_FILLED if _has_save else TINT_EMPTY
	_show_pointers(false)


## 两端指针同主菜单按钮：获得焦点时浮出，失焦时沉下后再隐藏。
func _show_pointers(on: bool) -> void:
	_pointers_wanted = on
	for pointer: AnimatedSprite2D in [_pointer_left, _pointer_right]:
		if on:
			pointer.visible = true
			pointer.play(ANIM_POINTER_SHOW)
		elif pointer.visible:
			pointer.play(ANIM_POINTER_HIDE)


func _on_pointer_animation_finished() -> void:
	# 收起动画播完才隐藏；若期间又重新获得焦点则不隐藏
	if _pointers_wanted:
		return
	_pointer_left.visible = false
	_pointer_right.visible = false


func _on_clear_save_button_pressed() -> void:
	_show_pointers(false)
	_set_row_enabled(false)
	_main_display.visible = false
	_game_label.visible = false
	_clear_button.visible = false
	_confirm.visible = true
	_deny_button.quiet_focus()


func _on_confirm_button_pressed() -> void:
	SaveManager.delete_slot(slot_index)
	_close_confirm()


func _on_deny_button_pressed() -> void:
	_close_confirm()


func _on_confirm_cancel() -> void:
	_close_confirm()


func _close_confirm() -> void:
	_confirm.visible = false
	_set_row_enabled(true)
	_game_label.visible = true
	_refresh()
	_load_button.quiet_focus()


func _set_row_enabled(enabled: bool) -> void:
	_load_button.disabled = not enabled
	_clear_button.disabled = not enabled


## 确认框打开时 Esc 只关闭确认框，不返回上一页。
func _unhandled_input(event: InputEvent) -> void:
	if not _confirm.visible:
		return
	if !event.is_action_pressed(&"ui_cancel"):
		return
	get_viewport().set_input_as_handled()
	_on_confirm_cancel()
