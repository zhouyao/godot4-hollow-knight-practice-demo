extends EnemyState
class_name EnemyAttackState


## 攻击骨架：远程吐弹 / 近战扑击的分流、一次性攻击音、站定、硬直结束回 chase，
## 各类怪完全一致，故收在基类。"怎么站定"与 patrol / chase 共用同一个介质策略
## （EnemyState._stop() → EnemyLocomotion.apply_stop），不再按介质建 attack 子类。
##
## 注：本状态不再继承 chase。旧版飞行 attack 为了复用 _attack_range() 而 extends 飞行 chase，
## 结果 super.update() 走的是 chase 的 update —— 飞行怪在 attack 里仍在追击移动、
## 攻击冷却仍在累加，与地面"攻击时站定"不一致。统一后攻击期间一律站定，
## 节奏交给 chase 的 attack_interval，"怎么站定"则交给运动介质。

## 近战模式：一次扑击的最短硬直（秒），到点即回 chase，避免逐帧抖动。
@export var attack_hold: float = 0.3
## 远程模式：吐弹后的后摇（秒），到点即回 chase，节奏交给 chase 的 attack_interval。
@export var attack_recover: float = 0.25

## 进入时判定：配了 projectile_scene 走吐弹分支，否则走近战分支。
var _ranged := false

func enter(_from: StringName) -> void:
	_ranged = enemy.has_projectile()
	if _ranged:
		# 没配 projectile_scene 就是纯近战（接触伤害由 EnemyState.update() 统一结算），
		# 无条件 launch_projectile() 会刷警告。
		enemy.launch_projectile()
	# 一次攻击 = 一声：远程在弹丸出膛的同一帧，近战在扑击起手那帧。
	# 前提是两种模式都必须在硬直 / 后摇结束后回 chase，把节奏交给 chase 的冷却，
	# 否则会长期赖在 attack 里 —— 一声攻击音配 N 次掉血，音画对不上。
	_play_audio(EnemyStateNames.ATTACK)
	_play_action(EnemyStateNames.ATTACK)

func update(delta: float) -> void:
	_hold_still()
	enemy.tick_combat(delta)
	# 接触伤害由 EnemyState.update() 统一结算，此处不重复调用。
	super.update(delta)

func get_transition(_delta: float) -> StringName:
	if not enemy.combat_active:
		return EnemyStateNames.RETURN
	var hold := _tuning(&"attack_recover", attack_recover) if _ranged \
		else _tuning(&"attack_hold", attack_hold)
	return EnemyStateNames.CHASE if elapsed >= hold else &""


# ---------- 子类重写点 ----------

## 攻击时站定：与 patrol / chase 的 _stop() 同源，统一由运动介质决定
## （贴地只清水平分量以保留重力，全向整体归零以悬停吐弹）。
## 需要"边攻击边位移"（冲刺 / 跃击）的介质直接重写本函数即可。
func _hold_still() -> void:
	_stop()
