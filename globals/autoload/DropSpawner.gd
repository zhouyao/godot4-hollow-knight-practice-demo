extends Node


## 同屏掉落实体上限：超出时直接丢弃新生成的，避免刷屏拖垮帧率。
const MAX_PICKUPS := 60

var _live: Array[Pickup] = []
## 命名序号：保证每次生成的名字唯一，否则 Godot 在名字冲突时会丢弃显式名，
## 退化成 @Area2D@2 这类自动名，调试时很难看。
var _seq := 0


func _physics_process(_delta: float) -> void:
	# 清理已被拾取 / 超时释放的引用，保持计数准确。
	for i in range(_live.size() - 1, -1, -1):
		if not is_instance_valid(_live[i]):
			_live.remove_at(i)


## 掷一张掉落表并在 at 附近生成实体。scatter 为水平/垂直散布（像素）。
func spawn_table(table: DropTable, at: Vector2, scatter: float = 28.0) -> void:
	if table == null:
		return
	var rng := RandomNumberGenerator.new()
	for r in table.roll(rng):
		if _live.size() >= MAX_PICKUPS:
			break
		var offset := Vector2(
				rng.randf_range(-scatter, scatter),
				rng.randf_range(-scatter * 0.5, 0.0))
		_spawn(r["scene"], at + offset, r["item_id"], int(r["amount"]), rng)


func _spawn(scene: PackedScene, at: Vector2, item_id: StringName,
		amount: int, rng: RandomNumberGenerator) -> void:
	if scene == null or not scene.can_instantiate():
		return
	var p := scene.instantiate()
	if not (p is Pickup):
		push_warning("DropSpawner: %s 根节点不是 Pickup，已丢弃" % scene.resource_path)
		p.free()
		return
	var parent := _parent()
	if parent == null:
		p.free()
		return
	_seq += 1
	p.name = "Pickup_%s_%d" % [item_id, _seq]
	p.item_id = item_id
	p.amount = amount
	_live.append(p)
	# _spawn 常从物理回调中触发（如敌人死亡掉落），此时物理引擎正在刷新查询，
	# 直接 add_child 带碰撞体的 Area2D 会触发 area_set_shape_disabled 报错。
	# 延迟到刷新结束后再挂载并激活，避免改动 monitoring 状态。
	parent.call_deferred("add_child", p)
	p.call_deferred("set_deferred", "global_position", at)
	# 位置改变后必须重置插值，否则第一帧会从世界原点飞过来。
	p.call_deferred("reset_physics_interpolation")
	p.call_deferred("launch",
			Vector2(rng.randf_range(-p.launch_speed_x, p.launch_speed_x),
					p.launch_speed_y))


## 优先放进世界里的 "Drops" 容器（保持场景树整洁），没有则退回当前场景根节点。
func _parent() -> Node:
	var scene := get_tree().current_scene
	if scene == null:
		return null
	var container := scene.find_child("Drops", true, false)
	return container if container != null else scene
