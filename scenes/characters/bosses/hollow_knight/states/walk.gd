extends BossState
class_name HollowKnightWalkState

## 朝玩家方向移动（接近），或玩家贴脸攻击时后撤拉开。
## 接近：持续走到 APPROACH_STOP_RANGE 内才交还 idle（idle 多半会选 slash），
##       因此远距接近是平滑连续的，不会在 idle/walk 之间一顿一顿。
##       唯一的例外是"追不上"：玩家背向逃跑时走速追不上跑速，本状态会周期性向 idle 中枢
##       借一次决策，挑中 dash / teleport 就让位（详见 _tick_chase_redecision）。
## 后撤：拉开到安全距离、或玩家已停止攻击，才交还 idle 重新决策。
## 方向在 enter 时根据上下文决定：玩家正在攻击且距离很近 → 后撤；否则接近。
##
## 后撤的实现：面朝玩家（face_toward），但水平速度取"远离玩家"的方向。
## 不直接走 _step_toward(远离点)，因为那样会把朝向也翻成背对玩家（apply_step 在
## step != move_direction 时会翻面）；这里手动写 velocity.x 反向，得到"面朝玩家、往后退"的手感。

# 与 idle.attack_range 同义：接近到此距离内即视为"已贴身"，交还 idle 做攻击决策。
const APPROACH_STOP_RANGE := 160.0
# 与 idle.retreat_range 同义：玩家贴脸且正在攻击时转为后撤的触发距离。
const RETREAT_RANGE := 90.0
# 后撤要拉开到的安全距离（超过即停后撤、回 idle）。
const RETREAT_SAFE_RANGE := 220.0

## 乘以 Boss 基础移动速度（96 × 2.4 ≈ 230 px/s）。
## 玩家跑速 384，BOSS 走速原本 192 追不上，会被纯走路风筝到死；提高到 230 后
## 玩家仍需冲刺才能拉开，同时又不至于完全甩不掉。
@export var walk_speed_multiplier: float = 2.4

## 追击途中重新决策的间隔（秒）：只在"追不上"时计时。
## 走路 230px/s 追不上跑速 384 的玩家，一旦被拉距离，本状态会一路走到贴脸才交还 idle，
## 途中不做任何决策 —— dash / teleport 于是永远等不到出手机会，手感就是"只会慢慢走"。
## 到点后把决策权交回 idle 中枢，只有它挑中 dash / teleport 才让位；挑中 walk 就继续平滑接近。
@export var chase_redecide_interval: float = 0.6
## 视为"有在接近"的最小距离改善（像素）：没缩到这个量就算这一帧没追上。
@export var chase_progress_epsilon: float = 8.0

var _retreating: bool = false
var _stuck_timer: float = 0.0
var _best_distance: float = INF
var _idle_state: BossState = null


func enter(_from: StringName) -> void:
	if boss == null:
		return
	boss.disable_melee_attack()
	play_action(&"walk")
	_retreating = _should_retreat()
	_stuck_timer = 0.0
	_best_distance = INF


func update(delta: float) -> void:
	var p := boss.get_player()

	# 没有目标就站定（兜底，正常不会长时间停留）。
	if p == null:
		boss.velocity.x = 0.0
		boss._apply_vertical_motion(delta)
		boss._apply_movement()
		return

	var distance := absf(p.global_position.x - boss.global_position.x)

	if _retreating:
		# 面朝玩家，反向位移（后撤）。
		var to_player := signf(p.global_position.x - boss.global_position.x)
		if to_player == 0.0:
			to_player = float(boss.move_direction)
		boss.face_toward(p.global_position.x)
		boss.velocity.x = -to_player * _speed()
	else:
		# 接近：朝玩家走（朝哪里走就面朝哪里，由引擎统一裁决）。
		_step_toward(p.global_position.x, _speed())
		_tick_chase_redecision(delta, distance)

	boss._apply_vertical_motion(delta)
	boss._apply_movement()

	# 决策已把状态切走（dash / teleport），本帧不再做收尾判断。
	if machine.current_state_name != BossStateNames.WALK:
		return

	# 接近：走到攻击距离内才交还 idle（触发 slash）；
	# 后撤：拉到安全距离或玩家已停止攻击，才交还 idle 重新决策。
	if not _retreating and distance <= APPROACH_STOP_RANGE:
		go_idle()
	elif _retreating and (distance >= RETREAT_SAFE_RANGE or not PlayerCombat.is_attacking):
		go_idle()


## 玩家正在攻击且距离很近 → 后撤躲避；否则接近。
func _should_retreat() -> bool:
	var p := boss.get_player()
	if p == null:
		return false
	var distance := absf(p.global_position.x - boss.global_position.x)
	return PlayerCombat.is_attacking and distance <= RETREAT_RANGE


func _speed() -> float:
	return _move_speed() * walk_speed_multiplier


## 追击体检：只要还在实质接近，就继续平滑地走（保持原有的接近手感）。
## 一旦"追不上"（玩家背向逃跑，走速 230 追不上跑速 384），累计时间到点，
## 就把主意交给 idle 决策中枢：它挑中 dash / teleport 才打断走路，挑中 walk 就继续走。
func _tick_chase_redecision(delta: float, distance: float) -> void:
	if distance < _best_distance - chase_progress_epsilon:
		_best_distance = distance
		_stuck_timer = 0.0
		return
	_best_distance = minf(_best_distance, distance)
	_stuck_timer += delta
	if _stuck_timer < chase_redecide_interval:
		return
	_stuck_timer = 0.0
	var idle := _get_idle_state()
	if idle == null:
		return
	var next := idle.decide_next()
	# 只有位移类招式值得打断走路；slash / counter / evade 在远距离本来就被门槛滤掉，
	# 这里再显式白名单一次，避免将来放开门槛时走路被奇怪的招式打断。
	if next == BossStateNames.DASH or next == BossStateNames.TELEPORT:
		machine.set_state(next)


## 决策中枢 idle 的实例：权重钩子与技能冷却都在它身上，walk 直接复用同一套决策与门槛，
## 不复制第二份权重表（两处权重必然漂移）。
func _get_idle_state() -> BossState:
	if _idle_state != null and is_instance_valid(_idle_state):
		return _idle_state
	if machine == null:
		return null
	_idle_state = machine.states.get(BossStateNames.IDLE) as BossState
	return _idle_state
