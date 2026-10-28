class_name EnemyLocomotion
extends Resource


## 运动介质（Locomotion）：把"这种怪怎么动"从敌人身上剥离出来，是本作怪物体系的
## **唯一变化轴** —— 新增一种怪 = 新增一个本类的子类，Enemy 与各状态不用改一行。
##
## 之前这件事由 Enemy.gravity_enabled 一个 bool 承担，只能表达"地面 / 非地面"两态，
## 加第三种怪（水下）就会崩。现在换成可替换的资源：
##   地面  GroundLocomotion   —— 吃重力、贴地走、尸体落地
##   飞行  FlyingLocomotion   —— 不吃重力、全向飞、死后坠落
##   水下  SwimmingLocomotion —— 浮力 + 水阻、全向游、只在水体内活动
##
## 本类负责的差异一共四类，子类按需重写：
##   1. 每帧介质力      apply_vertical()     —— 重力 / 悬停阻尼 / 浮力与水阻
##   2. 站定            apply_stop()         —— 贴地只清 x，全向整体归零
##   3. 归位距离        home_distance()      —— 贴地只算 x，全向算 2D
##   4. 尸体与介质占用  on_death() / is_corpse_settled() / can_occupy()
## 其中 2、3 已由 nav_planar_only 一处推导出默认实现，绝大多数介质无需重写。
##
## 注意：本资源在多个敌人实例之间共享（ground.tres 等），**禁止在本类里保存
## 逐敌人的可变状态**（追击被卡时长、退避方向之类只能放在状态节点上）。

## 导航是否只保留水平分量：贴地走 = true（垂直交给重力），全向 = false。
## 同时决定 return / patrol 的"抵达"按水平距离还是按 2D 距离判定。
@export var nav_planar_only: bool = false

## 视线（光线检测）用的物理碰撞层，0 = 沿用宿主敌人的 collision_mask。
## 想让视线与行走错开时单独指定，例如水下怪让视线穿过水体本身。
## 由 Enemy._sight_mask() 消费。
@export_flags_2d_physics var sight_mask: int = 0

## 本介质实际生效的视线层：未指定（0）时回落到敌方自身的 collision_mask。
## 由 Enemy._sight_mask() 统一调用，状态 / 子类不要再各自读 sight_mask。
func get_sight_mask(fallback_mask: int) -> int:
	return fallback_mask if sight_mask == 0 else sight_mask

## 站定：patrol / chase 的 _stop() 与 attack 的 _hold_still() 一律走这里。
## 贴地走只清水平分量（垂直留给重力往下落）；全向移动必须整体归零，
## 否则只清 x 会让它往下掉或往上飘 —— 飞行 / 水下同理。
## 由 nav_planar_only 一处推导，状态层不再为每种介质各写一份 _stop()。
func apply_stop(enemy: Enemy) -> void:
	if nav_planar_only:
		enemy.velocity.x = 0.0
	else:
		enemy.velocity = Vector2.ZERO

## 距出生点的"归位距离"：贴地走只按水平算（出生点的 y 受重力 / 地形影响，
## 与实际高度不一致，用全量 2D 距离会永远到不了、卡死在 return 状态），
## 全向怪（飞行 / 水下）按 2D 距离。同样由 nav_planar_only 一处推导。
## 由 EnemyReturnState._has_arrived() 消费。
func home_distance(enemy: Enemy) -> float:
	var d := enemy.global_position.distance_to(enemy.spawn_position)
	if nav_planar_only:
		d = absf(enemy.global_position.x - enemy.spawn_position.x)
	return d

## 每物理帧的垂直运动，由 EnemyState.update() 统一调用（经 Enemy._apply_vertical_motion 转发）。
## enemy：宿主敌人（Enemy）；delta：物理帧时长（秒）。
func apply_vertical(_enemy: Enemy, _delta: float) -> void:
	pass

## 死亡瞬间对躯体的处理：切换 motion_mode 等。
## 由 _base/states/death.gd 的 enter() 调用一次。
func on_death(_enemy: Enemy) -> void:
	pass

## 尸体是否已处理完毕（落地 / 沉底 / 上浮到位）：death 状态每帧轮询，
## 首次为 true 时才禁用碰撞、应用 corpse_y_offset 并停机，之后不再反复结算。
## 基类按"落地"判定：地面怪本来就在地上，飞行怪由 on_death() 切回 GROUNDED 后也能落地。
## 水下怪没有"地"可落（若死后上浮则永远等不到 is_on_floor()），必须重写本函数，
## 否则尸体的碰撞不会禁用、corpse_y_offset 不生效、状态机会一直空转。
## since_death：death 状态已持续的秒数，供"沉底 / 上浮到位"这类按时间判定的介质使用。
func is_corpse_settled(enemy: Enemy, _since_death: float = 0.0) -> bool:
	return enemy.is_on_floor()

## 本敌人此刻能否在 pos 处活动：地面怪恒 true；水下怪只在水体内。
## 由 Enemy.is_in_medium() 消费，chase / patrol 据此转 return（出水搁浅 → 强制回巢）。
## 基类恒 true；水下怪重写本函数即可，消费端无需改动。
func can_occupy(_enemy: Enemy, _pos: Vector2) -> bool:
	return true
