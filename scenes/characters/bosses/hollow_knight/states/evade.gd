extends BossState
class_name HollowKnightEvadeState

## 后撤技能（Hollow Knight 的向后闪避）。
## 进入时锁定"背对玩家"的撤退方向（= 朝向玩家的反方向），高速向后撤，
## 直到累计位移达到"本次目标距离"（按当前间距自适应，默认落在 160~320px）或撞墙或悬崖边缘才停下，
## 随后回 idle 重新决策。目标距离刻意不拉太远：后撤应该只是"撤半步再压上"，不是退出战斗圈。
##
## 与 dash 对称：dash 朝玩家冲、evade 背玩家撤；二者共用"累计位移 + 撞墙 + 悬崖"三套停止条件，只是方向相反。
##
## 演出与朝向：后撤时应"正面朝向玩家、向后撤"（像真正的防御性闪避），所以这里让 boss 用
## face_toward 面朝玩家（精灵正脸朝威胁）。但悬崖判定用的 ledge_detector 默认跟着 move_direction
## （此刻朝向玩家）走，会指错方向；因此 _aim_ledge_detector() 手动把探测器掰到撤退前方，
## 这样悬崖探测才正确，不会后撤下坑。代价只是探测器的朝向被单独修正，精灵画面仍正对玩家。
##
## 位移直接写 velocity.x 交给 Enemy._apply_movement，不启用近战命中盒（disable_melee_attack），
## 符合 BossState 基类"招式不用 _step_toward/apply_step"的约定。

# ---- 可调参数 ----
@export var evade_speed: float = 900.0           ## 后撤速度（像素 / 秒）
@export var max_evade_distance: float = 320.0    ## 单次后撤最大距离（像素）：别一撤就退出战斗圈
@export var min_evade_distance: float = 160.0    ## 单次后撤最短距离（像素）
@export var evade_gap: float = 100.0             ## 后撤后想在玩家外侧拉开多少像素

var _retreat_dir: int = 1
var _target_distance: float = 0.0
var _distance_travelled: float = 0.0


func enter(_from: StringName) -> void:
	if boss == null:
		return
	boss.disable_melee_attack()

	_distance_travelled = 0.0

	# 锁定撤退方向：背对玩家 = 朝向玩家的反方向。
	var p := boss.get_player()
	var to_player := 0.0
	if p != null:
		to_player = signf(p.global_position.x - boss.global_position.x)
	if is_zero_approx(to_player):
		to_player = float(boss.move_direction)
	_retreat_dir = -1 if to_player >= 0.0 else 1

	# 目标距离：按当前间距自适应，后撤后仍停在"刀外沿"附近，下一步能立刻反扑。
	# 原来固定 500，贴脸后撤会直接退出战斗圈，然后必须走两秒才能回来。
	var gap := 300.0
	if p != null:
		gap = absf(p.global_position.x - boss.global_position.x)
	_target_distance = clampf(gap + evade_gap, min_evade_distance, max_evade_distance)

	# 演出：面朝玩家（正脸朝向威胁，像真正的后撤闪避）。
	if p != null:
		boss.face_toward(p.global_position.x)
	# 但探测器要指向撤退前方，悬崖判定才正确。
	_aim_ledge_detector()

	var ap := boss.action_animation_player
	if ap != null and ap.has_animation(&"evade"):
		ap.play(&"evade")


func update(delta: float) -> void:
	if boss == null:
		return
	_evade_update(delta)


func exit(_to: StringName) -> void:
	if boss != null:
		boss.velocity.x = 0.0
		# 复位悬崖探测器：撤离时曾把它掰向撤退方向，离开本状态要恢复成跟随 move_direction 的默认朝向，
		# 否则move_direction没变（仍朝向玩家）时 idle 的 face_toward 不会触发 _flip_extra，探测器会一直指错。
		if boss.ledge_detector != null:
			boss.ledge_detector.position.x = absf(boss.ledge_detector.position.x) * boss.move_direction


## 悬崖探测器默认跟着 move_direction（= 面朝玩家方向）走；
## 后撤是朝相反方向走，所以这里手动把探测器掰到撤退前方，悬崖判定才正确。
## 每帧重设一次以保证稳定（幂等：absf 后乘方向，重复调用结果不变）。
func _aim_ledge_detector() -> void:
	if boss == null or boss.ledge_detector == null:
		return
	boss.ledge_detector.position.x = absf(boss.ledge_detector.position.x) * _retreat_dir


## 后撤一帧：先预判悬崖（撤退前方无地就停，别退下坑），再给速度、位移、累计距离，
## 撞墙或退满本次目标距离则停。
func _evade_update(delta: float) -> void:
	# 撤退前方是悬崖：本帧就收，不迈出那一步。
	_aim_ledge_detector()
	boss.ledge_detector.force_raycast_update()
	if !boss.ledge_detector.is_colliding():
		_finish()
		return

	boss.velocity.x = float(_retreat_dir) * evade_speed
	boss._apply_vertical_motion(delta)
	var prev_x := boss.global_position.x
	boss._apply_movement()
	_distance_travelled += absf(boss.global_position.x - prev_x)

	# 停止条件：1) 撤退前方有墙（撞墙）即停；2) 退满本次目标距离即停。
	if boss.is_on_wall():
		_finish()
	elif _distance_travelled >= _target_distance:
		_finish()


func _finish() -> void:
	if boss != null:
		boss.velocity.x = 0.0
	if machine != null:
		machine.set_state(BossStateNames.IDLE)
