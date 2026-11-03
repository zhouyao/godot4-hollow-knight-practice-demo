class_name BossState
extends EnemyState


## BOSS 状态基类。
##
## 只在 EnemyState 之上加一份 Boss 类型的快捷访问 —— 其余全部沿用：
##   · update() 不重写：EnemyState.update() 已经做了
##     「垂直运动 → 位移 → 接触伤害结算」三步，BOSS 一样适用；
##     而且 _contact_opens_combat() 默认 false，接触只会扣玩家血、
##     不会误触发开战（BOSS 的开战由 BossArena / 入场演出决定）。
##   · _tuning()（三级取值）、_play_audio()（镜头可见性）、_flash_white()（受击闪白）、
##     _stop()（站定，委托给运动介质）、_face_toward()（带死区朝向）—— 统统共用一份。
##
## 唯一的使用约定：招式位移**不要**走 _step_toward() / apply_step()。
## 那套会把位移交给 EnemySteering 裁决（朝向死区 + 踏空探测），是为小怪追击设计的；
## BOSS 的位移由招式自己给定（冲刺按累计位移收尾、后撤是面朝反方向），
## 招式状态应直接写 velocity.x，再靠 Enemy._apply_movement() 统一 move_and_slide()。
## 这也是 Boss._ready() 把 facing.check_displacement 置 false 的原因。

var _boss: Boss

var boss: Boss:
	get:
		if _boss == null or not is_instance_valid(_boss):
			_boss = machine.host as Boss if machine != null else null
		return _boss


## 进入下一阶段前先问一次：血量是否跨过了阈值。
## 由 combat 在每次决策前调用；这里也放一份，方便任何招式状态在收招时顺手检查。
func _check_phase() -> void:
	if boss == null:
		return
	boss.check_phase()


# ---- 通用加权决策引擎 ----
## 出招节奏：每隔 decision_interval 秒重新决策一次（也是贴身追击时 idle 的喘息/前摇时长，
## 越小越跟手；设 0.2 即每次回到 idle 仅站 0.2s 就决策，避免跟放风筝玩家时一顿一顿）。
## 在子类 idle.update 里调用，到点返回要切换的状态名，否则返回 &""。
@export var decision_interval: float = 0.1
var _decision_timer: float = 0.0
var _last_action: StringName = &""

## 计时到点后跑一轮决策；未到点返回 &""。
func tick_decision(delta: float) -> StringName:
	_decision_timer += delta
	if _decision_timer < decision_interval:
		return &""
	_decision_timer = 0.0
	return decide_next()

## 一整轮决策：可用池 → 硬门槛过滤 → 加权 → 随机 + lastAction 惩罚。
## 三个钩子由具体 boss 的 idle 实现：_available_actions / _filter_actions / _weights。
func decide_next() -> StringName:
	var distance := boss.player_distance()
	var pool := _filter_actions(_available_actions(), distance)
	if pool.is_empty():
		return &""
	var w := _weights(distance, boss.is_player_attacking())
	if _last_action != &"" and w.has(_last_action):
		w[_last_action] *= 0.2   # 上次动作惩罚，避免连续两次同招
	var pick := weighted_pick(pool, w)
	_last_action = pick
	return pick

## 按权重随机挑一个动作（纯函数，通用）。
func weighted_pick(pool: Array[StringName], w: Dictionary) -> StringName:
	var total := 0.0
	for action in pool:
		total += float(w.get(action, 0.0))
	if total <= 0.0:
		return pool[0]
	var r := randf() * total
	for action in pool:
		r -= float(w.get(action, 0.0))
		if r <= 0.0:
			return action
	return pool[pool.size() - 1]

# —— 三个钩子，默认空实现，由具体 boss 的 idle 覆盖 ——
## 当前阶段可用招式池：多阶段时按 boss.phase_index 返回不同集合。
func _available_actions() -> Array[StringName]:
	return []

##硬门槛：只负责"这招现在能不能放"，不关心权重。
func _filter_actions(pool: Array[StringName], _distance: float) -> Array[StringName]:
	return pool

## 加权表：根据上下文调整各动作权重。
func _weights(_distance: float, _attacking: bool) -> Dictionary:
	return {}
