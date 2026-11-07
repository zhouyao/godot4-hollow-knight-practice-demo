@tool
extends Node2D
class_name BossFogGate

## BOSS 空气墙：开战时在玩家身后落下一道墙，BOSS 被击败后自动消散。

@export_group("空气墙 Wall")
## 墙宽高（像素）：同步写入 `Wall/CollisionShape2D` 的 `RectangleShape2D.size`，
## 在编辑器里改也立即生效。最小值 1，避免 0 / 负值形状报错。
@export var wall_size: Vector2 = Vector2(24.0, 1000.0):
	set(value):
		wall_size = Vector2(maxf(value.x, 1.0), maxf(value.y, 1.0))
		_apply_wall_size()

@export_group("战斗 Combat")
## 目标 BOSS（相对本节点的路径）。
@export var boss_node: NodePath = NodePath()

var _boss: Node = null
var _closed := false

@onready var _wall: StaticBody2D = $Wall
@onready var _shape: CollisionShape2D = $Wall/CollisionShape2D


func _ready() -> void:
	# 场景属性恢复时子节点可能还没进树，setter 的同步会扑空，这里补一次
	_apply_wall_size()
	if Engine.is_editor_hint():
		return  # @tool：编辑器里只同步尺寸，不跑战斗 / 存档逻辑
	_boss = get_node_or_null(boss_node)
	_shape.set_deferred("disabled", true)

	if _boss == null:
		push_warning("[BossFogGate] %s 未绑定 boss_node，雾门不会工作" % name)
		return

	# 读档：BOSS 已被永久击败 → 门保持敞开
	if _is_boss_defeated():
		return

	# boss_activated 在 BOSS 被激活的第一帧就发，优先用它关门；
	# enter_combat 作为兜底，兼容旧 BOSS / 直接走 _set_combat 的开战路径。
	if _boss.has_signal(&"boss_activated"):
		_boss.connect(&"boss_activated", _on_boss_activated)
	if _boss.has_signal(&"enter_combat"):
		_boss.connect(&"enter_combat", _on_boss_enter_combat)
	if _boss.has_signal(&"boss_defeated"):
		_boss.connect(&"boss_defeated", _on_boss_defeated)


## 把 wall_size 同步到内部碰撞盒（可选同步雾墙视觉）。
## 用 get_node_or_null 兜住「属性恢复阶段子节点尚未进树」的情况，
## 值相同则不写，避免 @tool 反复把场景标脏。
func _apply_wall_size() -> void:
	var cs := get_node_or_null(^"Wall/CollisionShape2D") as CollisionShape2D
	if cs != null and cs.shape is RectangleShape2D:
		var shape := cs.shape as RectangleShape2D
		if not shape.size.is_equal_approx(wall_size):
			shape.size = wall_size

## BOSS 一被激活就落墙：不等入场演出结束，玩家没有时间跑出房间。
func _on_boss_activated() -> void:
	_set_closed(true)


func _on_boss_enter_combat(_target: Node2D) -> void:
	_set_closed(true)


func _on_boss_defeated() -> void:
	_set_closed(false)


func _is_boss_defeated() -> bool:
	if _boss == null:
		return false
	var raw: Variant = _boss.get(&"persistent_id")
	var id := String(raw) if raw != null else ""
	if id.is_empty():
		return false
	# @tool 脚本在编辑器里没有 autoload 上下文，按路径取单例而不是写标识符
	var save_mgr := get_node_or_null(^"/root/SaveManager")
	return save_mgr != null and bool(save_mgr.call(&"is_defeated", id))


func _set_closed(closed: bool) -> void:
	if _closed == closed:
		return
	_closed = closed

	# 关门立刻挡人，开门也立刻放行；重复收到信号时上面的 _closed 判重会挡掉
	_shape.set_deferred("disabled", not closed)
