extends EnemyState

# 落地后才置 true：在此之前尸体保留本体碰撞，用来真正砸到地面上
var _landed := false

func enter(_from: StringName) -> void:
	_play_action(EnemyStateNames.DEATH)
	_play_audio(EnemyStateNames.DEATH)
	# 飞行怪（以及被打飞的地面怪）要落到地面才停：死后恢复重力继续跑物理。
	# 接触伤害无需担心——try_hit_player() 开头就被 dead 挡掉了。
	enemy.gravity_enabled = true
	# FLOATING 模式下 move_and_slide 不做地面检测（is_on_floor() 恒为 false），
	# 必须切回 GROUNDED，否则下面的落地判断永远不成立，尸体会一直往下掉。
	if enemy.motion_mode == CharacterBody2D.MOTION_MODE_FLOATING:
		enemy.motion_mode = CharacterBody2D.MOTION_MODE_GROUNDED

## 尸体坠落阶段：状态机保持运转，直到 is_on_floor() 为止。
## 落地后立刻关掉本体碰撞（不再挡玩家、不再被玩家攻击区命中）并停掉状态机。
func update(delta: float) -> void:
	super.update(delta)
	if _landed or not enemy.is_on_floor():
		return
	_landed = true
	enemy.collision_shape.set_deferred("disabled", true)
	machine.active = false

func get_transition(_delta: float) -> StringName:
	return &""
