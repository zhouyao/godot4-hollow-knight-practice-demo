extends Node2D
class_name BossFogGate

## BOSS 雾门：开战时在玩家身后落下一道雾墙，BOSS 被击败后自动消散。
##
## 挂的是 BOSS 自己的信号，不依赖竞技场怎么触发战斗：
##   · enter_combat  → 关门（玩家被锁在战斗区域内）
##   · boss_defeated → 开门（永久；读档时若 BOSS 已击败则直接保持敞开）
##
## 为什么不在 leave_combat 时开门：玩家跑远脱战会把门重新打开，
## 等于"雾门"形同虚设。这里只在击败 / 读档两个时机开门。
##
## 布置约定：节点原点 = 雾墙中心；把 boss_node 指向 BOSS 根节点即可。

## 目标 BOSS（相对本节点的路径）。
@export var boss_node: NodePath = NodePath()
## 雾墙淡入淡出时长（秒）。
@export var fade_time: float = 0.35

var _boss: Node = null
var _closed := false

@onready var _wall: StaticBody2D = $Wall
@onready var _shape: CollisionShape2D = $Wall/CollisionShape2D
@onready var _fog: Sprite2D = $Fog


func _ready() -> void:
	_boss = get_node_or_null(boss_node)
	_fog.visible = false
	_fog.modulate.a = 0.0
	_shape.set_deferred("disabled", true)

	if _boss == null:
		push_warning("[BossFogGate] %s 未绑定 boss_node，雾门不会工作" % name)
		return

	# 读档：BOSS 已被永久击败 → 门保持敞开
	if _is_boss_defeated():
		return

	if _boss.has_signal(&"enter_combat"):
		_boss.connect(&"enter_combat", _on_boss_enter_combat)
	if _boss.has_signal(&"boss_defeated"):
		_boss.connect(&"boss_defeated", _on_boss_defeated)


func _on_boss_enter_combat(_target: Node2D) -> void:
	_set_closed(true)


func _on_boss_defeated() -> void:
	_set_closed(false)


func _is_boss_defeated() -> bool:
	if _boss == null:
		return false
	var raw: Variant = _boss.get(&"persistent_id")
	var id := String(raw) if raw != null else ""
	return not id.is_empty() and SaveManager.is_defeated(id)


func _set_closed(closed: bool) -> void:
	if _closed == closed:
		return
	_closed = closed

	# 关门立刻挡人，开门也立刻放行；视觉再慢慢淡
	_shape.set_deferred("disabled", not closed)

	if closed:
		_fog.visible = true
	var tween := create_tween()
	tween.tween_property(_fog, "modulate:a", 1.0 if closed else 0.0, fade_time)
	if not closed:
		tween.finished.connect(func() -> void:
			if is_instance_valid(_fog):
				_fog.visible = false
		)
