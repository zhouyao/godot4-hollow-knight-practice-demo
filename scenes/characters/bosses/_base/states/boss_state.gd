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


# ---- 状态切换收尾（所有招式状态共用）----
## 播放动作动画（ActionAnimationPlayer）：boss 为空、动画不存在都静默跳过，不刷错误。
## 实现只有 Enemy._play_action → EnemyFacing.play_action 一份；状态里不要再手写
## `if ap != null and ap.has_animation(x): ap.play(x)` 这三行。
func play_action(anim_name: StringName) -> void:
	if boss != null:
		boss._play_action(anim_name)

## 仅当状态机此刻仍停留在本状态（按节点名比对）时才切到 target。
## 用于"收招 / 演出结束"这类由计时器、动画信号触发的切换：期间若已被受击、
## 阶段切换或别的招式打断，就不该再把人拽回原定状态。
## 返回是否真的发起了切换（machine 为空 / 已被打断都返回 false）。
func goto_if_current(target: StringName) -> bool:
	if machine == null or machine.get_state_name() != name:
		return false
	machine.set_state(target)
	return true

## 收招出口：仍是本状态才切回 idle（各招式状态统一的"播完回去重新决策"）。
func go_idle() -> bool:
	return goto_if_current(BossStateNames.IDLE)

## 取动画时长；没有该动画 / 没有 AnimationPlayer 时返回 fallback。
## 相位推进普遍用"动画时长计时器"而不依赖 animation_finished 信号（信号链一旦断掉就卡死），
## 所以动画缺失时也必须有一个确定的时长让相位能继续走 —— 兜底值是这个函数的必要部分。
## 以前 dash / teleport / down_smash / teleport_smash 各抄了一份，现在只留这里一份。
func anim_length(anim_name: StringName, fallback: float) -> float:
	var ap := boss.action_animation_player if boss != null else null
	if ap != null and ap.has_animation(anim_name):
		return ap.get_animation(anim_name).length
	return fallback


# ---- 通用加权决策引擎 ----
## 出招节奏（秒）：统一取状态机上的全局配置 BossStateMachine.decision_interval。
## 以前状态与状态机各导出一份，Inspector 上改的往往不是真正生效的那份，这里只保留一个来源。
## 也是贴身追击时 idle 的喘息/前摇时长，越小越跟手（0.2 = 每次回 idle 只站 0.2s 就决策）。
var decision_interval: float:
	get:
		if machine is BossStateMachine:
			return (machine as BossStateMachine).decision_interval
		return 0.1

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
