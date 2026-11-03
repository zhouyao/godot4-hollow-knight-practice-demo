extends BossState
class_name SoulMasterIdleState

## 决策中枢：不做任何移动或攻击，只负责每隔状态机上的 decision_interval 秒决定下一步做什么。
## 决策引擎（tick_decision / decide_next / weighted_pick）已沉淀在 BossState 基类，
## 本状态只需提供三件套钩子：_available_actions / _filter_actions / _weights，以及距离阈值调参。


func enter(_from: StringName) -> void:
	if boss == null:
		return
	
	# 待机期间关闭挥砍命中盒，避免站定时误伤。
	boss.disable_melee_attack()
	play_action(BossStateNames.IDLE)

func update(delta: float) -> void:
	# 待机：站定（清水平速度），不做接触伤害结算。
	boss.velocity.x = 0.0
	boss._apply_vertical_motion(delta)
	boss._apply_movement()

	# 站定时也看向玩家，演出更自然。
	var p := boss.get_player()
	if p != null:
		boss.face_toward(p.global_position.x)

	# 到时间就跑一轮加权决策。
	var action := tick_decision(delta)
	if action == &"" or action == BossStateNames.IDLE:
		return
	machine.set_state(action)


# ---- 决策三件套（基类 decide_next 会调用这三个钩子）----

## 当前阶段可用招式池：多阶段时按 boss.phase_index 返回不同集合。
func _available_actions() -> Array[StringName]:
	var pool: Array[StringName] = []

	return pool


## 硬门槛：只负责"这招现在能不能放"，不关心权重。
## 权重的职责是"偏好"，门槛的职责是"合法性"——两者不要混，
## 否则会出现"权重压得再低也照样放"或"权重很高但永远放不出"的调参地狱。
func _filter_actions(pool: Array[StringName], _distance: float) -> Array[StringName]:
	# 占位：招式池填好后按 attacking 做合法性过滤（如仅玩家挥砍时允许 counter）。
	var _attacking := boss.is_player_attacking() if boss != null else false
	var out: Array[StringName] = []
	for action in pool:
		out.append(action)
	return out


## 加权表：距离分层定基础偏好，情境与连招做有界修正。
## 关键约束：所有乘法都必须走 _mul（幅度夹在 0.1~4）。
## 旧的 evade ×40 一次性吃掉全部随机性，连 ×0.2 的反重复惩罚都压不住，
## 才会出现"贴脸 91% 后撤"的逃跑型 BOSS。
func _weights(distance: float, player_attacking: bool) -> Dictionary:
	var w := _base_weights(distance)

	_apply_chain(w)
	return w


## 距离分层基础权重：层间互斥，只命中一层；层内一次定好，不再跨层累乘。
func _base_weights(distance: float) -> Dictionary:
	var w := {
	}
	return w


## 连招节奏：让 BOSS 看起来"有意图"，而不是每招独立随机。
## "砍完拉开半步观察、撤完立刻反扑"是把"逃跑"翻译成"试探"的关键。
func _apply_chain(w: Dictionary) -> void:
	pass


## 唯一的乘法入口：幅度强制夹在 0.1~4，杜绝再出现 ×40 这种吃掉全部随机性的修饰。
func _mul(w: Dictionary, key: StringName, k: float) -> void:
	if w.has(key):
		w[key] = float(w[key]) * clampf(k, 0.1, 4.0)


## 当前时刻（秒），只用来算冷却到期。
## 注意：不能用"每秒减 delta"的倒计时 —— 递减只在 idle.update 里跑，
## 而 idle 在整场战斗里只占很小一部分时间，冷却会被无限拉长。
func _now() -> float:
	return float(Time.get_ticks_msec()) / 1000.0

## 该技能是否还在冷却中（到期时间戳未到）。
func _cooling(until: float) -> bool:
	return _now() < until
