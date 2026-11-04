extends BossDecisionState
class_name SoulMasterIdleState

## 决策中枢：不做任何移动或攻击，只负责每隔状态机上的 decision_interval 秒决定下一步做什么。
## 站定 / 面向玩家 / 决策节奏 / 技能冷却（cooldowns 在场景的 idle 节点上配）全部由
## BossDecisionState 提供；本状态只给出招式池与权重表。
##
## 冷却一律用「到期时间戳」而不是「剩余秒数倒计时」：倒计时只在 idle.update 里递减，
## 而 idle 每次只活 decision_interval(0.1s)，冷却会被无限拉长。


## 当前阶段可用招式池：多阶段时按 boss.phase_index 返回不同集合。
func _available_actions() -> Array[StringName]:
	var pool: Array[StringName] = [
		BossStateNames.TELEPORT, BossStateNames.SUMMON, BossStateNames.QUAKE,
		BossStateNames.DASH]
	return pool


## 加权表：距离分层定基础偏好，情境与连招做有界修正。
## 关键约束：所有乘法都必须走 _mul（幅度夹在 0.1~4）。
func _weights(distance: float, _player_attacking: bool) -> Dictionary:
	var w := _base_weights(distance)

	# 冲刺是"贴地突进"：远距离才值钱，贴脸交给瞬移 / 召唤。
	if distance >= 640.0:
		_mul(w, BossStateNames.DASH, 1.8)
	elif distance <= 280.0:
		_mul(w, BossStateNames.DASH, 0.4)
	_apply_chain(w)
	return w


## 基础权重：这里只给"各有价值"的中性权重，距离修正放在 _weights 里。
## _filter_actions 的冷却硬门槛由 BossDecisionState 负责，本状态不再重复。
func _base_weights(_distance: float) -> Dictionary:
	return {
		BossStateNames.TELEPORT: 1.0,
		BossStateNames.SUMMON: 1.0,
		BossStateNames.QUAKE: 1.2,
		BossStateNames.DASH: 1.4,
	}
