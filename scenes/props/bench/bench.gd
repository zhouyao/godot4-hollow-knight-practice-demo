extends EntryPoint
class_name Bench

## 长椅（存档点）：玩家碰到就存档，并把重生点改成这张长椅。
##
## 为什么继承 EntryPoint：存档里存的出生点就是 entry_id，
## 长椅自己带一个 entry_id 就能被 WorldArea.get_entry() 直接找到，
## 读档 / 死亡后不用额外配置"这张椅子对应哪个入口"。
##
## 位置约定与 EntryPoint 一致：节点原点 = 玩家胶囊中心（离地 75px），
## 所以长椅摆在"地面 y - 75"的位置，视觉方块由 Visual 子节点往下偏。

signal rested

## 休息时是否写盘（关掉可用于纯视觉的装饰椅）。
@export var save_on_rest := true
## 两次存档之间的最小间隔（秒），防止玩家贴着椅子反复触发。
@export var rest_cooldown := 1.5
## 休息闪光时长（秒）。
@export var flash_time := 0.25

var _cooldown_until := 0
var _flash_tween: Tween = null

@onready var _detect: Area2D = $DetectArea
@onready var _visual: Sprite2D = $Visual


func _ready() -> void:
	super._ready()
	_detect.body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node2D) -> void:
	if not body.is_in_group(&"player"):
		return
	if Time.get_ticks_msec() < _cooldown_until:
		return
	_cooldown_until = Time.get_ticks_msec() + int(rest_cooldown * 1000.0)
	rest()


## 主动休息：把重生点切到本长椅并落盘。
func rest() -> void:
	GameSession.current_entry_id = entry_id
	if save_on_rest:
		# 坐标钉在长椅本身：玩家可能是从旁边蹭到检测区的
		SaveManager.save_game(false, global_position)
	_flash()
	GameSession.notify_rested(entry_id)
	rested.emit()


func _flash() -> void:
	if _visual == null:
		return
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	_visual.modulate = Color(2.4, 2.8, 3.2, 1.0)
	_flash_tween = create_tween()
	_flash_tween.tween_property(_visual, "modulate", Color.WHITE, flash_time)
