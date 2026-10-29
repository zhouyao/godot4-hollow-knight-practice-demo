extends EnemyState
class_name EnemyReturnState


## 返回骨架：归位判定、丢战转 patrol、重开战转 chase 都是各类怪共有的，
## 只有"这一步往哪走"不同。
##
## 走法同样按 **贴地 / 全向** 两条分支收在本文件里，由 locomotion.nav_planar_only 分派：
##   _planar_return_move() —— 地面怪：沿地走回家，朝家那一步会踏空时先退避再重新规划
##   _omni_return_move()   —— 飞行怪 / 水下怪：直飞 / 直游回巢，并保持头朝前进方向
## 逐敌人可变状态（_escape_* 等）留在本状态节点上，不进共享的 Locomotion 资源。

## 抵达出生点的判定距离（像素）。
@export var arrive_distance: float = 8.0
## 返回速度倍率（相对 enemy.move_speed）。
@export var return_speed_multiplier: float = 2.0
## 朝家那一步会踏空时的退避：锁定一个方向至少走满这么多像素才允许重新规划。仅贴地怪。
## 没有这个"承诺"就会每帧改主意，敌人会在边缘原地翻面（chase 里同一个坑已修掉）。
@export var escape_distance: float = 64.0
## 连续退避超过这么久，说明"家在对岸、根本过不去"：放弃防踏空判定，直接朝家走。仅贴地怪。
## 保留这条兜底是为了让 return 一定能结束 —— 否则敌人会永远卡在平台边缘回不了巢。
@export var escape_patience: float = 3.0

var _escape_dir: float = 0.0
var _escape_origin: float = 0.0
var _escape_time: float = 0.0
## 退避超时后置 true：本状态下不再检查悬崖，一路朝家走。
var _ignore_ledge: bool = false

func enter(_from: StringName) -> void:
	# 声明循环动作：转身动画播完要恢复到它（见 Enemy.set_locomotion_clip）。
	enemy.set_locomotion_clip(EnemyStateNames.MOVE)
	_escape_dir = 0.0
	_escape_origin = 0.0
	_escape_time = 0.0
	_ignore_ledge = false

func update(delta: float) -> void:
	_return_move(delta)
	super.update(delta)

func get_transition(_delta: float) -> StringName:
	if _has_arrived():
		enemy._set_combat(false)
		return enemy.resting_state()
	# 返回途中仅受击可重开战（take_damage 会置 combat_active）；否则继续返回。
	if enemy.combat_active:
		return EnemyStateNames.CHASE
	return &""


## 抵达判定与距离算法一并委托给运动介质：贴地只按水平算，全向按 2D 算
## （见 EnemyLocomotion.home_distance），此处不再出现介质分支。
func _has_arrived() -> bool:
	var d := enemy.locomotion.home_distance(enemy) if enemy.locomotion != null \
		else enemy.global_position.distance_to(enemy.spawn_position)
	return d <= _tuning(&"arrive_distance", arrive_distance)

## 本帧的返回速度（像素 / 秒）。
func _return_speed() -> float:
	return _move_speed() * _tuning(&"return_speed_multiplier", return_speed_multiplier)


# ---------- 走法：由 locomotion.nav_planar_only 分派 ----------

func _return_move(delta: float) -> void:
	if enemy.is_planar_mover():
		_planar_return_move(delta)
	else:
		_omni_return_move()

## 贴地回家：原则上跟着导航走；前方踏空就先锁定安全方向退开一段再重新规划，
## 退到无解（escape_patience）后放弃踏空保护，保证状态能收敛。
func _planar_return_move(delta: float) -> void:
	var speed := _return_speed()
	var dir := enemy.nav_velocity(enemy.spawn_position, speed)
	if dir.x == 0.0:
		enemy.velocity.x = 0.0
		return
	var step_x := signf(dir.x)

	# 处于退避中：至少走满承诺距离再复盘，中途不改主意，避免逐帧掉头。
	# _escape_time 是本状态的累计退避时长（enter() 才清零），不会走出一段就归零，
	# 否则"来回退避"永远凑不满 escape_patience，兜底就失效了。
	if _escape_dir != 0.0:
		_escape_time += delta
		if _escape_time >= _tuning(&"escape_patience", escape_patience):
			# 退了这么久还没能重新上路：认为家在对岸，不再防踏空。
			_ignore_ledge = true
			_escape_dir = 0.0
			_escape_time = 0.0
		elif absf(enemy.global_position.x - _escape_origin) \
				>= _tuning(&"escape_distance", escape_distance):
			_escape_dir = 0.0  # 走满承诺距离，回到正常逻辑重新找路
		else:
			enemy.apply_step(int(_escape_dir), speed)
			return

	if not _ignore_ledge:
		var safe := enemy.safe_step_x(step_x)
		if safe == 0.0:
			_ignore_ledge = true  # 两侧都没地，只能朝家硬走
		elif safe != step_x:
			# 朝家的下一步会踏空：往身后的实地退开一段，退出去再找路。
			_escape_dir = safe
			_escape_origin = enemy.global_position.x
			enemy.apply_step(int(_escape_dir), speed)
			return

	enemy.apply_step(int(step_x), speed)

## 全向回巢（飞行 / 水下）：直奔出生点，并保持头朝前进方向。
func _omni_return_move() -> void:
	enemy.velocity = enemy.nav_velocity(enemy.spawn_position, _return_speed())
	# 回家途中头要朝前进方向：不补这句会一直保持 chase 留下的朝向（面朝玩家），
	# 看起来就是"头朝后倒着飞回巢"。用带死区的 _face_toward 而不是 signf(dir.x)：
	# 导航方向在接近出生点时可能逐帧抖动变号，直接取符号会原地疯狂翻面。
	_face_toward(enemy.spawn_position.x)
