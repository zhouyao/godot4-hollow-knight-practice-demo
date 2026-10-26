extends EnemyState
class_name CombatState


## 子类实现：把本帧期望速度写入 enemy.velocity（chase / return / patrol 各自不同）。
func _step_move(_delta: float) -> void:
	pass

## 子类实现：近战/远程各自的攻击触发距离（像素）。
func _attack_range() -> float:
	return enemy.attack_range if enemy != null else 0.0

## 子类实现：进入攻击的附加条件（如远程冷却）。默认无条件。
func _can_attack(_delta: float) -> bool:
	return true

## 统一转换骨架：战斗丢失→RETURN；进入攻击距离且满足附加条件→ATTACK；否则空。
## 子类 get_transition 应优先调用本函数，再叠加自身额外条件。
func _check_combat_transition(delta: float) -> StringName:
	if not enemy.combat_active:
		return EnemyStateNames.RETURN
	if not enemy.state_machine.states.has(EnemyStateNames.ATTACK):
		return &""
	var player := enemy.get_player()
	if player != null \
			and enemy.global_position.distance_to(player.global_position) <= _attack_range() \
			and _can_attack(delta):
		return EnemyStateNames.ATTACK
	return &""

## 推进战斗丢失计时；子类在 update 里调用（tick_combat 内部会在超时后翻 combat_active）。
func _tick_combat(delta: float) -> void:
	enemy.tick_combat(delta)
