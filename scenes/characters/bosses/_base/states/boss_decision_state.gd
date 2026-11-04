extends BossState
class_name BossDecisionState

## BOSS 战斗决策中枢（idle）的公共实现。
##
## 由 BossState 的加权决策引擎（tick_decision / decide_next / weighted_pick）驱动，
## 本层补齐所有 BOSS 的 idle 都一样的几件事：
##   · 收招回到 idle 时按 _last_action 登记技能冷却（到期时间戳，不用每帧递减）；
##   · 站定、看向玩家、到点跑一轮决策；
##   · 待机期间关闭近战命中盒、播 idle 动作；
##   · 提供 _now / _mul / is_cooling 三个共用工具与 _apply_chain 钩子。
## 具体 BOSS 只需在场景里填 cooldowns，并覆盖 _available_actions / _weights；
## 需要额外硬门槛时覆盖 _filter_actions，并先调 super 过滤冷却。

## 待机是否结算接触伤害。SoulMaster 的飞行身体会蹭人（true），
## HollowKnight 的 idle 不结算（在场景里改成 false）。
@export var contact_damage_in_idle: bool = true

## 动作名 → 冷却秒数。取代"每个技能一组 @export + 一个时间戳变量"。
## 用字典登记"到期时间戳"而不是倒计时：递减只在 idle.update 里跑，
## 而 idle 每次只活 decision_interval(0.1s)，冷却会被无限拉长。
@export var cooldowns: Dictionary = {}

## 动作名 → 冷却到期时刻（秒，Time.get_ticks_msec 时间轴）。
var _cooldown_until: Dictionary = {}


func enter(from: StringName) -> void:
	super.enter(from)
	_decision_timer = 0.0
	var cd := float(cooldowns.get(_last_action, 0.0))
	if _last_action != &"" and cd > 0.0:
		_cooldown_until[_last_action] = _now() + cd
	if boss != null:
		boss.disable_melee_attack()
	play_action(BossStateNames.IDLE)


func update(delta: float) -> void:
	# 本状态重写了 update()，接触伤害必须自己结算（走不到 EnemyState.update() 的 _tick_contact）。
	stand_still(delta, contact_damage_in_idle)
	if boss != null:
		var p := boss.get_player()
		if p != null:
			boss.face_toward(p.global_position.x)
	var action := tick_decision(delta)
	if action == &"" or action == BossStateNames.IDLE:
		return
	machine.set_state(action)


# ---- 冷却 ----
## 某动作是否仍在冷却中。
func is_cooling(action: StringName) -> bool:
	return _now() < float(_cooldown_until.get(action, 0.0))


## 默认硬门槛只过滤冷却。子类要加距离 / 阶段 / 玩家出招等门槛时，
## 先取 `var base := super._filter_actions(pool, distance)`，再对 base 做自己的剔除。
## 权重的职责是"偏好"、门槛的职责是"合法性"，两者不要混。
func _filter_actions(pool: Array[StringName], _distance: float) -> Array[StringName]:
	var out: Array[StringName] = []
	for action in pool:
		if is_cooling(action):
			continue
		out.append(action)
	return out


# ---- 共用工具 ----
## 当前时刻（秒），只用来算冷却到期。
func _now() -> float:
	return float(Time.get_ticks_msec()) / 1000.0


## 唯一的权重乘法入口：幅度强制夹在 0.1~4，杜绝 ×40 这种吃掉全部随机性的修饰。
func _mul(w: Dictionary, key: StringName, k: float) -> void:
	if w.has(key):
		w[key] = float(w[key]) * clampf(k, 0.1, 4.0)


## 连招节奏钩子：让 BOSS 看起来"有意图"，由具体 BOSS 的 idle 覆盖。
func _apply_chain(_w: Dictionary) -> void:
	pass
