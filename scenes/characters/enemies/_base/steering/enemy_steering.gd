class_name EnemySteering


## 敌人横向行为裁决：朝向与位移的唯一来源。
##
## 这里只放**纯函数**（不碰节点、不做物理查询、不读全局状态），所以能被单元测试直接覆盖；
## Enemy 上的实例方法只负责"采集输入 + 施加结果"（见 Enemy.decide_step_x / apply_step）。
##
## 背景：以前"朝向"由 EnemyState._face_target_x() 按死区算、"位移"由 nav_velocity() 按导航
## 方向算，两套判据在目标几乎位于正上 / 正下方（玩家从头顶跳过）时给出相反答案 ——
## 怪物会一边朝右一边往左走；而且位移会不断把 |dx| 缩小，它永远出不了死区，朝向也就永远不更新。
## 修法不是"每个状态记得对齐一次"，而是让朝向与位移都从同一个 step 派生：
## 两者同源，物理上就不可能打架，新增状态也不会再复制一份判据。

## 横向步向：本帧该往哪个方向走（同时也决定"该朝哪看"）。
## 返回 0 = 本帧不横向移动；此时朝向与位移同时为 0，不可能出现倒着走。
##   self_x      ：自身世界 x
##   target_x    ：目标世界 x（玩家 / 出生点 / 巡逻端点）
##   deadzone    ：朝向死区（像素），>= 0；目标横向距离在此范围内一律站定
##   planar      ：贴地怪才做地形裁决；飞行 / 水下怪忽略地形
##   ground_ahead：按候选方向探测的结果，true = 前方有落脚点
static func step_x(self_x: float, target_x: float, deadzone: float,
		planar: bool, ground_ahead: bool) -> int:
	var dx := target_x - self_x
	# 死区必须最先判：目标在正上 / 正下方时横向根本没有"该走的方向"，
	# 而且位移会不断把 |dx| 缩小 —— 若不在死区停手，就会永远出不去、朝向永远不更新。
	if absf(dx) <= deadzone:
		return 0
	var step := 1 if dx > 0.0 else -1
	if planar and not ground_ahead:
		return 0
	return step


## 画面朝向：素材基准朝向 × 逻辑朝向。
## 幂等 —— 调 0 次、1 次、3 次结果完全一致，所以任何时机补一次都是安全的。
## 这是"不再用 scale.x *= -1 累乘"的关键：累乘是有状态开关，调用次数一旦被异步回调
## （动画结束 / 状态抢占 / 受击打断）打乱，朝向就会与 move_direction 永久错位且极难复现。
##   base_sign      ：素材基准朝向，+1 = 原画朝右，-1 = 原画朝左（如 crawlid）
##   current_scale_x：精灵当前 scale.x，只取绝对值，保留美术上可能存在的缩放
##   move_direction ：逻辑朝向，±1
static func facing_scale_x(base_sign: float, current_scale_x: float,
		move_direction: int) -> float:
	return absf(current_scale_x) * signf(base_sign) * float(move_direction)
