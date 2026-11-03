extends BossState
class_name HollowKnightIdleState

## 决策中枢：不做任何移动或攻击，只负责每隔状态机上的 decision_interval 秒决定下一步做什么。
## 决策引擎（tick_decision / decide_next / weighted_pick）已沉淀在 BossState 基类，
## 本状态只需提供三件套钩子：_available_actions / _filter_actions / _weights，以及距离阈值调参。


# ---- 距离阈值（出招手感全在这里调）----
@export var far_range: float = 500.0          ## 超过此距离视为"远"，强烈偏好接近
@export var attack_range: float = 160.0       ## 进入此距离内 slash 才合法（硬门槛）
@export var retreat_range: float = 90.0       ## 玩家贴脸且正在攻击时，walk 转为后撤的触发距离
@export var counter_cooldown: float = 2.0      ## counter 收招后多久内不再被选（避免近战区反复招架死循环）
var _counter_cd: float = 0.0
@export var dash_cooldown: float = 3.0          ## dash 收招后多久内不再被选（避免冲刺过于频繁）
var _dash_cd: float = 0.0

## 头顶实时显示决策权重（调试用）。需同时打开全局调试开关 Globals.debug_enabled。
@export var show_decision_debug: bool = false
var _decision_label: Label = null

# 基础权重（被下方信号动态放大 / 压低）
const BASE_WALK := 1.0
const BASE_SLASH := 1.0
const BASE_DASH := 1.0
const DASH_RANGE := 900.0          ## 冲刺有效的最远距离，超出则冲不到，不入选
const BASE_COUNTER := 0.6

func enter(_from: StringName) -> void:
	if boss == null:
		return
	_decision_timer = 0.0
	# 若上一招是 counter（刚收招回到 idle），开启冷却，避免立刻再选 counter 形成反复招架死循环。
	if _last_action == BossStateNames.COUNTER:
		_counter_cd = counter_cooldown
	# 若上一招是 dash，开启冷却，避免冲刺过于频繁。
	if _last_action == BossStateNames.DASH:
		_dash_cd = dash_cooldown
	# 待机期间关闭挥砍命中盒，避免站定时误伤。
	boss.disable_melee_attack()
	boss.action_animation_player.play(BossStateNames.IDLE)

func update(delta: float) -> void:
	# 待机：站定（清水平速度），不做接触伤害结算。
	boss.velocity.x = 0.0
	boss._apply_vertical_motion(delta)
	boss._apply_movement()

	# 技能冷却递减：收招后一段时间内不再选对应技能。
	if _counter_cd > 0.0:
		_counter_cd = maxf(0.0, _counter_cd - delta)
	if _dash_cd > 0.0:
		_dash_cd = maxf(0.0, _dash_cd - delta)

	# 站定时也看向玩家，演出更自然。
	var p := boss.get_player()
	if p != null:
		boss.face_toward(p.global_position.x)

	# 调试：头顶实时显示当前决策权重（便于调参）。
	if show_decision_debug:
		_draw_decision_debug()

	# 到时间就跑一轮加权决策。
	var action := tick_decision(delta)
	if action == &"" or action == BossStateNames.IDLE:
		return
	machine.set_state(action)


# ---- 决策三件套（基类 decide_next 会调用这三个钩子）----

## 当前阶段可用招式池：多阶段时按 boss.phase_index 返回不同集合。
func _available_actions() -> Array[StringName]:
	return [BossStateNames.WALK, BossStateNames.SLASH, BossStateNames.DASH, BossStateNames.COUNTER]


## 硬门槛：只负责"这招现在能不能放"，不关心权重。
## slash 仅当玩家进入 attack_range 才合法。
func _filter_actions(pool: Array[StringName], distance: float) -> Array[StringName]:
	var out: Array[StringName] = []
	for action in pool:
		if action == BossStateNames.SLASH and distance > attack_range:
			continue
		# 招架反击仅当玩家进入近战范围、且不在冷却中才合法（需求硬门槛 + 防反复招架死循环）。
		if action == BossStateNames.COUNTER and (distance > attack_range or _counter_cd > 0.0):
			continue
		# 冲刺仅当：距离不超过上限（太远冲不到）、玩家不在 slash 攻击范围内、且不在冷却中。
		# （进入 attack_range 即视为贴脸，优先 slash 而非继续冲）。
		if action == BossStateNames.DASH and (distance > DASH_RANGE or distance <= attack_range or _dash_cd > 0.0):
			continue
		out.append(action)
	return out



func _weights(distance: float, player_attacking: bool) -> Dictionary:
	var w := {BossStateNames.WALK: BASE_WALK, BossStateNames.SLASH: BASE_SLASH, BossStateNames.DASH: BASE_DASH, BossStateNames.COUNTER: BASE_COUNTER}
	if distance > far_range:
		# 远距离（500~dash 上限 900）：dash 是更快的接近手段，明显占优；压低 walk，避免反复走路不突进。
		w[BossStateNames.DASH] *= 3.0
		w[BossStateNames.WALK] *= 0.3
		w[BossStateNames.SLASH] *= 0.01
	elif distance <= attack_range:
		# 距离近：偏好进攻
		w[BossStateNames.SLASH] *= 3.0
		w[BossStateNames.COUNTER] *= 2.5
		w[BossStateNames.WALK] *= 0.5
	if distance > attack_range and distance < far_range:
		# 中距离（够不到 slash、又没远到需要纯走路）：偏好突进拉近距离
		w[BossStateNames.DASH] *= 3.0
	if player_attacking and distance <= retreat_range:
		# 玩家贴脸且正在攻击：偏好后撤躲避，不硬拼
		w[BossStateNames.WALK] *= 3.0
		w[BossStateNames.SLASH] *= 0.2
	return w


## 在 Boss 头顶用 Label 实时画出本帧的决策权重，方便调 dash / walk 的出现频率。
## 仅当 show_decision_debug 且全局调试开关打开时生效；权重复刻 decide_next 的“不重复上次”惩罚。
func _draw_decision_debug() -> void:
	if boss == null:
		return
	if _decision_label == null:
		_decision_label = Label.new()
		_decision_label.z_index = 100
		_decision_label.position = Vector2(-43.0, -470.0)
		boss.add_child(_decision_label)
	_decision_label.visible = show_decision_debug and Globals.debug_enabled
	if not _decision_label.visible:
		return
	var distance := boss.player_distance()
	var pool := _filter_actions(_available_actions(), distance)
	var w := _weights(distance, boss.is_player_attacking())
	# 复刻 decide_next 的“不重复上次”惩罚，展示真实可用权重。
	if _last_action != &"" and w.has(_last_action):
		w[_last_action] *= 0.2
	var lines := PackedStringArray()
	lines.append("dist=%.0f" % distance)
	# 标记的是 boss“上一帧实际选中的招式”（_last_action），而非权重最高的招式：
	# 真正的选中是 weighted_pick 的随机结果，权重最高≠一定被选中，若标理论最高权重，
	# 会与随机落到的实际动作对不上，看起来“不准确”。如实标出上一招，配合上面的×0.2惩罚更直观。
	for a in pool:
		var mark := " " if a != _last_action else ">"
		lines.append("%s %s %.2f" % [mark, a, float(w.get(a, 0.0))])
	_decision_label.text = "\n".join(lines)
