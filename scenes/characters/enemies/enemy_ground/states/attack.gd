extends CombatState
class_name EnemyGroundAttackState


## 近战模式：单次攻击的最短硬直（秒），避免逐帧抖动。
@export var attack_hold: float = 0.3
## 远程模式：吐弹后的后摇（秒），到点即回 chase，节奏交给 chase 的 attack_interval。
@export var attack_recover: float = 0.25

## 进入时判定：配了 projectile_scene 走吐弹分支，否则走原来的近战分支。
var _ranged := false

func enter(_from: StringName) -> void:
	_ranged = enemy.has_projectile()
	if _ranged:
		enemy.launch_projectile()
		_play_audio(&"attack")
	_play_action(&"attack")

func update(delta: float) -> void:
	enemy.velocity.x = 0.0  # 攻击时站定（远程：吐弹后摇；近战：贴身僵持）
	if not _ranged:
		enemy.try_hit_player(true)
	enemy.tick_combat(delta)
	super.update(delta)

func get_transition(_delta: float) -> StringName:
	if not enemy.combat_active:
		return EnemyStateNames.RETURN
	# 远程：后摇结束即回 chase，由 chase 的冷却控制下一发。
	if _ranged:
		return EnemyStateNames.CHASE if elapsed >= attack_recover else &""
	# 近战：硬直结束后，玩家仍在贴身范围内就继续留在 attack（靠 contact_cooldown 间隔掉血）。
	if elapsed < attack_hold:
		return &""
	var player := enemy.get_player()
	if player == null \
			or enemy.global_position.distance_to(player.global_position) > enemy.attack_range:
		return EnemyStateNames.CHASE
	return &""

func _attack_range() -> float:
	return enemy.attack_range
