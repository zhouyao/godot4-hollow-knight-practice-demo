extends BossState
class_name HollowKnightWalkState

## 朝玩家方向移动（接近），或玩家贴脸攻击时后撤拉开。
## 接近：持续走到 APPROACH_STOP_RANGE 内才交还 idle（idle 多半会选 slash），
##       因此远距接近是平滑连续的，不会在 idle/walk 之间一顿一顿。
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

@export var walk_speed_multiplier: float = 2.0  ## 乘以 Boss 基础移动速度

var _retreating: bool = false


func enter(_from: StringName) -> void:
	if boss == null:
		return
	boss.disable_melee_attack()
	if boss.action_animation_player != null and boss.action_animation_player.has_animation("walk"):
		boss.action_animation_player.play("walk")
	_retreating = _should_retreat()


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

	boss._apply_vertical_motion(delta)
	boss._apply_movement()

	# 接近：走到攻击距离内才交还 idle（触发 slash）；
	# 后撤：拉到安全距离或玩家已停止攻击，才交还 idle 重新决策。
	if not _retreating and distance <= APPROACH_STOP_RANGE:
		machine.set_state(BossStateNames.IDLE)
	elif _retreating and (distance >= RETREAT_SAFE_RANGE or not PlayerCombat.is_attacking):
		machine.set_state(BossStateNames.IDLE)


## 玩家正在攻击且距离很近 → 后撤躲避；否则接近。
func _should_retreat() -> bool:
	var p := boss.get_player()
	if p == null:
		return false
	var distance := absf(p.global_position.x - boss.global_position.x)
	return PlayerCombat.is_attacking and distance <= RETREAT_RANGE


func _speed() -> float:
	return _move_speed() * walk_speed_multiplier
