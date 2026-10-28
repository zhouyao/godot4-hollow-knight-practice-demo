class_name SwimmingLocomotion
extends EnemyLocomotion


## 水中怪的运动介质：浮力 + 水阻、全向游、只在水体内活动。
##
## 本文件是"新增一种怪物类型要动多少地方"的验收样例 —— 做完阶段 1 的重构后，
## 接入水中怪**只需要新增本文件 + swimming.tres**，Enemy 基类、6 个状态骨架、
## 死亡状态、调参资源全部不用改：
##   · 站定 / 归位判定      由 nav_planar_only = false 自动推导（apply_stop / home_distance）
##   · 追击 / 巡逻 / 返回   走基类 _omni_*_move() 全向分支，无需建 enemy_water/states/
##   · 出水搁浅             重写 can_occupy()，消费端 Enemy.is_in_medium() 早已就位
##   · 尸体处理             重写 is_corpse_settled()（水中没有"落地"这回事）
##
## 尚未接入真实水体：water_mask 默认 0，此时 can_occupy() 恒 true，行为退化成
## "全向自由游动"（与飞行怪一致），不会因为没配水体就把怪卡死在原地。
## 接入时只需在项目的水体 Area2D 上勾选一个物理层，并把该层填进 water_mask。

## 水体所在的物理层（Area2D）。0 = 未配置水体，can_occupy() 恒 true。
@export_flags_2d_physics var water_mask: int = 0

## 浮力（像素 / 秒²，负值向上）：把怪往水面顶，与重力方向相反。
@export var buoyancy: float = -520.0
## 水阻（像素 / 秒²）：把纵向速度往 0 收敛，营造"水里飘"的手感。
@export var drag: float = 900.0
## 上浮速度上限（像素 / 秒）：浮力不至于把怪顶出水面后一路飞走。
@export var max_rise_speed: float = 120.0

## 死亡后的沉降加速度（像素 / 秒²）：正值 = 往下沉。
@export var death_sink: float = 240.0
## 死亡后尸体的处理时长（秒）：到点即视为 settled，再交给 corpse_lifetime 淡出。
@export var corpse_settle_time: float = 0.8


func _init() -> void:
	nav_planar_only = false


## 存活时：浮力顶 + 水阻收敛；死亡后：转为下沉。
## 水平方向的水阻由各状态每帧重写 velocity（= 方向 × 速度）自然体现，无需额外处理。
func apply_vertical(enemy: Enemy, delta: float) -> void:
	if enemy.dead:
		enemy.velocity.y = move_toward(enemy.velocity.y, death_sink, drag * delta)
		return
	enemy.velocity.y += buoyancy * delta
	enemy.velocity.y = move_toward(enemy.velocity.y, 0.0, drag * delta)
	if enemy.velocity.y < -max_rise_speed:
		enemy.velocity.y = -max_rise_speed


## 水中没有"落地"：尸体按时间判定，保证 death 状态一定会收敛
## （否则碰撞不禁用、corpse_y_offset 不生效、状态机永久空转）。
func is_corpse_settled(_enemy: Enemy, since_death: float = 0.0) -> bool:
	return since_death >= corpse_settle_time


## 只在水体内活动：出水即搁浅，chase / patrol 会据此放弃当前行为转 return 回巢。
## 水层未配置（water_mask = 0）时恒 true，退化成全向自由游动。
func can_occupy(enemy: Enemy, pos: Vector2) -> bool:
	if water_mask == 0:
		return true
	var space := enemy.get_world_2d().direct_space_state
	if space == null:
		return true
	var query := PhysicsPointQueryParameters2D.new()
	query.position = pos
	query.collision_mask = water_mask
	query.collide_with_areas = true
	query.collide_with_bodies = false
	query.exclude = [enemy.get_rid()]
	# 每物理帧一次点查询：敌人数量在百级以内时开销可忽略；
	# 若以后做大量鱼群，再考虑把结果缓存到宿主敌人上（本资源是共享的，不能缓存）。
	return not space.intersect_point(query).is_empty()
