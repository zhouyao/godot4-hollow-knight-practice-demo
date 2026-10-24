extends EnemyFlyingChaseState
class_name EnemyFlyingAttackState


## 攻击（吐息）后的后摇（秒）：期间停在 attack 状态，结束后切回 chase。
@export var attack_recover: float = 0.2

var _recover := 0.0

func enter(_from: StringName) -> void:
	enemy.launch_projectile()
	_play_audio(&"attack")
	_recover = 0.0

func update(delta: float) -> void:
	_recover += delta
	enemy.tick_combat(delta)
	super.update(delta)

func get_transition(_delta: float) -> StringName:
	if not enemy.combat_active:
		return EnemyStateNames.RETURN
	# 玩家离开攻击射程则回到追击。
	var player := enemy.get_player()
	if player != null and enemy.global_position.distance_to(player.global_position) > _attack_range():
		return EnemyStateNames.CHASE
	if _recover >= attack_recover:
		return EnemyStateNames.CHASE
	return &""
