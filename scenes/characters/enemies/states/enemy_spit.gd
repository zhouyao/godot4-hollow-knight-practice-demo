extends EnemyState
class_name EnemySpitState

## 吐弹怪 AI。地面怪（gravity_enabled）只站桩吐弹；飞行怪额外负责"追击 / 守边 / 回巢"：
##
##   玩家在活动区域内   → 追到 keep_distance 处悬停吐弹
##   玩家在活动区域外   → 目标被 clamp_to_leash() 压到边界，飞过去贴边吐弹
##   够不着且原地停留 / 玩家脱离侦测，持续 return_home_delay 秒 → 飞回出生点待命
##   守家期间玩家重新进入侦测范围、或直接走进活动区域 → 重新追出去
##
## 活动区域（Leash）由 Enemy 提供：NavigationRegion2D 只是寻路数据、不含碰撞，
## 挡不住飞行怪，所以"守住地盘"得靠这个矩形。

# ---- 吐弹 ----
@export var spit_interval: float = 1.5
@export var spit_range: float = 500.0

# ---- 飞行 ----
## 追击时与玩家保持的水平距离：靠到这个距离就停止贴近，专心吐弹
@export var keep_distance: float = 120.0
## 目标悬停高度相对玩家的偏移（负数 = 悬在玩家上方）
@export var hover_offset_y: float = -80.0
## 飞行速度相对 move_speed 的倍率（仅 gravity_enabled = false 时生效）
@export_range(0.05, 2.0) var fly_speed_multiplier: float = 0.75

# ---- 放弃追击 / 回巢 ----
## 回巢延时（秒）。两种"放弃"情况共用这一个值：
## a) 够不着玩家（他在活动区域外）且原地停留这么久；
## b) 玩家脱离 PlayerDetectionArea（脱战）后等这么久 —— 期间他回到侦测范围就计时清零、当没事发生。
## 回巢后停在出生点待命，直到：玩家重新进入侦测范围（会再飞过去守一次），
## 或玩家直接走进活动区域。这样不会"回巢—再守边"来回抖动。
## <= 0 = 永不回巢，一直停在原地吐弹
@export var return_home_delay: float = 3.0

## 贴到活动区域边界后留的余量（像素）：太小会在边界上每帧抖动
const LEASH_EDGE_MARGIN := 8.0
## 判定"原地停留"的水平位移阈值（像素）。只看水平：垂直一直在做悬停正弦浮动，
## 掺进来会让放弃计时永远清零
const IDLE_MOVE_EPSILON := 4.0

## 飞行 AI 当前阶段
enum Phase {
	PURSUE,  ## 追击：朝"夹进活动区域后的玩家位置"飞
	RETURN,  ## 回巢：飞回出生点并待命
}

var _timer := 0.0
## 放弃计时（秒）：原地停留 / 脱战两条路径共用
var _give_up_timer := 0.0
## 判定原地停留用的水平锚点：挪动超过 IDLE_MOVE_EPSILON 就重新锚定
var _stay_anchor_x := NAN
var _phase := Phase.PURSUE
## 玩家脱离侦测后置位：下次看到他就切回 PURSUE，而不是一直守在出生点
var _rearmed := false

func enter(_from: StringName) -> void:
	_play_action(EnemyStateNames.IDLE)
	_reset()

func update(delta: float) -> void:
	enemy.velocity.x = 0.0
	if enemy.target == null:
		_on_target_lost(delta)
	else:
		_on_target_visible(delta)
	super.update(delta)

func get_transition(_delta: float) -> StringName:
	return &""


# ---------------------------------------------------------------- 目标处理

## 玩家脱离 PlayerDetectionArea：飞行怪脱战计时，超时回巢；
## 已经在回巢的不再等，直接把家回完（否则会僵在半空）
func _on_target_lost(delta: float) -> void:
	_rearmed = true
	if not _is_flyer():
		return
	if _phase == Phase.RETURN:
		_fly_home(delta)
	elif _tick_give_up(delta, true):
		_fly_home(delta)

## 有目标：先处理"重新上膛"，再转向 / 飞行 / 吐弹
func _on_target_visible(delta: float) -> void:
	if _rearmed:
		# 玩家重新进入侦测范围：解除守家，再飞过去守一次
		_rearmed = false
		_phase = Phase.PURSUE
		_give_up_timer = 0.0
	var target_pos: Vector2 = enemy.target.global_position
	_face_target(target_pos.x)
	if _is_flyer():
		_fly_toward(target_pos, delta)
	_try_spit(target_pos, delta)

func _try_spit(target_pos: Vector2, delta: float) -> void:
	_timer += delta
	if _timer < spit_interval:
		return
	# 冷却好了却够不着时不重置计时：一进射程立刻打出第一发
	if enemy.global_position.distance_to(target_pos) > spit_range:
		return
	enemy.launch_projectile()
	_timer = 0.0


# ---------------------------------------------------------------- 飞行

## 目标点先被 clamp_to_leash() 夹进活动区域：玩家在框外时它就落在边界上，
## 敌人靠到边界后贴边悬停继续吐弹，而不是一路追出去。
func _fly_toward(target_pos: Vector2, delta: float) -> void:
	var goal: Vector2 = enemy.clamp_to_leash(target_pos)
	if goal == target_pos:
		# 玩家在活动区域内：够得着，取消回巢
		_phase = Phase.PURSUE
		_give_up_timer = 0.0
	elif _tick_give_up(delta, _is_staying_put()):
		_fly_home(delta)
		return
	if _phase == Phase.RETURN:
		_fly_home(delta)
		return
	_pursue(goal, target_pos, delta)

## 朝夹取后的目标点推进：水平听寻路（没路就直线），垂直交给悬停
func _pursue(goal: Vector2, target_pos: Vector2, delta: float) -> void:
	var speed := _fly_speed()
	# 水平被夹住说明玩家在框外：不再保持 keep_distance，直接贴到边界上，
	# 否则会停在离边界 keep_distance(120) 远的地方，离玩家更远、更难进射程
	var stop_distance := LEASH_EDGE_MARGIN if absf(goal.x - target_pos.x) > 0.01 else keep_distance
	var to_goal := goal.x - enemy.global_position.x
	if absf(to_goal) > stop_distance:
		var step: Vector2 = enemy.get_navigation_step(goal)
		var to_step := step.x - enemy.global_position.x
		enemy.velocity.x = signf(to_step) * speed if absf(to_step) > 1.0 else signf(to_goal) * speed
	# 再夹一次：hover_offset 可能把悬停基准顶出活动区域
	var hover_y := enemy.clamp_to_leash(Vector2(goal.x, goal.y + hover_offset_y)).y
	enemy.move_hover_base_to(hover_y, speed * delta)

## 飞回出生点并悬停待命
func _fly_home(delta: float) -> void:
	var home: Vector2 = enemy.spawn_position
	var to_home := home.x - enemy.global_position.x
	enemy.velocity.x = signf(to_home) * _fly_speed() if absf(to_home) > LEASH_EDGE_MARGIN else 0.0
	enemy.move_hover_base_to(home.y, _fly_speed() * delta)


# ---------------------------------------------------------------- 放弃计时

## 累计放弃计时，达到 return_home_delay 就切到 RETURN 并返回 true。
## 条件不成立就清零：所以"边飞边计时""玩家中途回来"都不会误触发。
## return_home_delay <= 0 时永远不触发（= 永不回巢）
func _tick_give_up(delta: float, condition: bool) -> bool:
	if not condition or return_home_delay <= 0.0:
		_give_up_timer = 0.0
		return false
	_give_up_timer += delta
	if _give_up_timer < return_home_delay:
		return false
	_give_up_timer = 0.0
	_phase = Phase.RETURN
	return true

## 是否原地停留（顺带维护水平锚点）：水平几乎没挪动就算停着
func _is_staying_put() -> bool:
	var x := enemy.global_position.x
	if is_nan(_stay_anchor_x):
		_stay_anchor_x = x
	if absf(x - _stay_anchor_x) > IDLE_MOVE_EPSILON:
		_stay_anchor_x = x
		return false
	return true


# ---------------------------------------------------------------- 杂项

func _reset() -> void:
	_timer = 0.0
	_give_up_timer = 0.0
	_stay_anchor_x = NAN
	_phase = Phase.PURSUE
	_rearmed = false

func _is_flyer() -> bool:
	return not enemy.gravity_enabled

func _fly_speed() -> float:
	return enemy.move_speed * fly_speed_multiplier

func _face_target(target_x: float) -> void:
	var desired := 0
	if target_x > enemy.global_position.x:
		desired = 1
	elif target_x < enemy.global_position.x:
		desired = -1
	if desired != 0 and desired != enemy.move_direction:
		enemy._flip_direction()
