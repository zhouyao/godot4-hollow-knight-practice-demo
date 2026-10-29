extends EnemyState
class_name EnemyPatrolState


## 巡逻骨架：开关、端点往返、抵达停留、掉头转身、开战转 chase 都是各类怪共有的，
## 只有"这一步往哪走"各不相同。
##
## 走法不再按怪物类型建子类（那会让"介质 × 状态"变成 N×M 矩阵），而是按
## **贴地 / 全向**两条分支收在本文件里，由 locomotion.nav_planar_only 一处分派：
##   _planar_patrol_move() —— 地面怪：沿地往返，撞墙 / 悬崖提前掉头
##   _omni_patrol_move()   —— 飞行怪 / 水下怪：2D 飘移，可叠加纵向浮动
## 新增一种介质时，只要它属于这两类之一就**无需新建任何文件**；
## 确实需要第三种走法时直接重写 _patrol_move()，骨架其余部分不受影响。

## 巡逻半径（像素）：无领地时，出生点左右各伸出这么远作为往返的两个端点。
## patrol_enabled = false 时本项无效。
@export var patrol_radius: float = 80.0
## 巡逻速度倍率（相对 enemy.move_speed）。patrol_enabled = false 时本项无效。
@export var patrol_speed_multiplier: float = 0.5
## 抵达端点后的停留时长（秒）：掉头前先停一下，比贴着端点原地翻面自然。
@export var wait_time: float = 1.0
## 纵向浮动幅度（像素）：仅全向移动（飞行 / 水下），0 = 只做水平往返。
@export var bob_amplitude: float = 40.0
## 纵向浮动频率（弧度 / 秒）：仅全向移动。
@export var bob_frequency: float = 3.0

var _dir: int = 1
var _wait: float = 0.0

func enter(_from: StringName) -> void:
	# 巡逻开启时本状态才会被进入（关巡逻的怪走 idle 状态），所以恒播移动动作。
	# 用 set_locomotion_clip 声明：转身动画播完要恢复到它。
	enemy.set_locomotion_clip(EnemyStateNames.MOVE)
	_dir = enemy.move_direction
	_wait = 0.0  # 地面版原先漏了这行：端点等待途中被打断会带着残留值回到巡逻

func update(delta: float) -> void:
	if not enemy.patrol_enabled:
		_stop()
	elif _wait > 0.0:
		_wait -= delta
		_stop()
	else:
		_patrol_move(delta)
	super.update(delta)

func get_transition(_delta: float) -> StringName:
	if enemy.combat_active:
		return EnemyStateNames.CHASE
	# 被击退等原因离开了可活动介质（水下怪出水）：回巢。
	# 守卫 return 状态是否存在 —— 否则没有该状态的怪会每帧空转。
	if not enemy.is_in_medium() \
			and enemy.state_machine != null \
			and enemy.state_machine.states.has(EnemyStateNames.RETURN):
		return EnemyStateNames.RETURN
	return &""


## 掉头 + 停留，并立刻转身（地面怪的探测器 / 吐弹口要跟着指向新方向）。
## wait_scale：撞墙 / 悬崖这类被动掉头只停一半时长，看起来像"撞了一下赶紧回头"。
func _flip_end(wait_scale: float = 1.0) -> void:
	_dir *= -1
	# 名字对不上（状态叫 wait_time、tuning 叫 patrol_wait_time）是故意的：
	# EnemyTuning 里所有巡逻项统一 patrol_ 前缀，避免和 Timer.wait_time 之类撞名。
	_wait = _tuning(&"patrol_wait_time", wait_time) * wait_scale
	enemy.face_step(_dir)
	_stop()

## 当前要走向的端点的世界 x。绑了领地时按领地的左右端（与运动介质无关）。
func _end_x() -> float:
	var zone := enemy.get_node_or_null(enemy.enemy_zone)
	if zone is AuZone:
		var half := (zone as AuZone).size.x * 0.5
		return zone.global_position.x + float(_dir) * half
	return enemy.spawn_position.x + float(_dir) * _tuning(&"patrol_radius", patrol_radius)

## 本帧的巡逻速度（像素 / 秒）：各走法直接用，不要再各自乘倍率。
func _patrol_speed() -> float:
	return _move_speed() * _tuning(&"patrol_speed_multiplier", patrol_speed_multiplier)

## 抵达判定只看水平距离：既不依赖 navigation_agent 是否存在，
## 也不受"纵向浮动把 2D 距离撑开"的影响（飞行怪的 bob 就是这么把怪钉死在端点的）。
## 用 enemy.nav_arrive_distance 是为了和 nav_velocity() 内部的判定保持同一个数。
func _has_arrived(target_x: float) -> bool:
	return absf(enemy.global_position.x - target_x) <= enemy.nav_arrive_distance


# ---------- 走法：由 locomotion.nav_planar_only 分派 ----------

func _patrol_move(_delta: float) -> void:
	if enemy.is_planar_mover():
		_planar_patrol_move()
	else:
		_omni_patrol_move()

## 贴地往返：前方撞墙或前方无地面（悬崖）都立即掉头，继续巡逻。
## wall_ahead() 内部已 force_raycast_update()，不会读到翻面前那一侧的旧结果。
func _planar_patrol_move() -> void:
	if enemy.wall_ahead() or not enemy.has_ground_ahead(float(_dir)):
		_flip_end(0.5)  # 被动掉头只停一半时长，像"撞了一下赶紧回头"
		return

	var target_x := _end_x()
	if _has_arrived(target_x):
		_flip_end()
		return

	var dir := enemy.nav_velocity(
		Vector2(target_x, enemy.global_position.y), _patrol_speed())
	# dir.x == 0：导航给不出路（含抵达端点），掉头换个方向再试。
	if dir.x != 0.0:
		# 贴地怪 nav_velocity 的水平分量就是 ±speed，这里用 apply_step 统一施加：
		# 翻面与位移同源，不会出现"面朝一侧却往另一侧走"。
		enemy.apply_step(int(signf(dir.x)), _patrol_speed())
		return
	_flip_end()

## 全向飘移（飞行 / 水下）：水平端点往返 + 可选纵向浮动。
func _omni_patrol_move() -> void:
	var target_x := _end_x()
	if _has_arrived(target_x):
		_flip_end()
		return

	# 导航目标只含水平分量：纵向浮动是表演，不参与抵达判定。
	# 早先把 bob 塞进 target 会酿成 bug —— 怪去追一个上下移动的点，而目标垂直速度峰值
	# 是 amplitude * frequency（40 × 3 = 120 px/s），大于飞行速度（move_speed ≈ 96 px/s）。
	# 于是水平早就到位、2D 距离却永远差一点，怪卡在端点上下抖、永不掉头。
	var dir := enemy.nav_velocity(
		Vector2(target_x, enemy.spawn_position.y), _patrol_speed())
	# 浮动改以速度叠加（sin 的导数），水平导航因此保持纯净。
	var amp := _tuning(&"bob_amplitude", bob_amplitude)
	var freq := _tuning(&"bob_frequency", bob_frequency)
	enemy.velocity = dir + Vector2(0.0, cos(elapsed * freq) * amp * freq)
	# 朝向必须用带死区的 _face_toward，不能用 signf(dir.x)：
	# 端点附近 x 分量在 0 附近抖动，取符号会原地疯狂翻面（chase / return 同理）。
	_face_toward(target_x)
