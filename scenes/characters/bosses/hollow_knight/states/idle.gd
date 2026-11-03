extends BossState
class_name HollowKnightIdleState

## 决策中枢：不做任何移动或攻击，只负责每隔状态机上的 decision_interval 秒决定下一步做什么。
## 决策引擎（tick_decision / decide_next / weighted_pick）已沉淀在 BossState 基类，
## 本状态只需提供三件套钩子：_available_actions / _filter_actions / _weights，以及距离阈值调参。


# ---- 距离分层（互斥，只命中一层；出招手感全在这里调）----
@export var point_range: float = 90.0          ## 贴身：玩家几乎站在脸上
@export var attack_range: float = 160.0        ## slash 合法距离（硬门槛）
@export var edge_range: float = 260.0          ## 刀外沿：最该用短突进的区间
@export var mid_range: float = 520.0           ## 中距离：dash 主场
const DASH_RANGE := 1300.0                     ## dash 可达上限（配合 dash 的自适应位移）
## teleport 的近距硬门槛：低于此距离瞬移毫无收益（落点固定贴在玩家身边 appear_distance≈130，
## 从 160~300 瞬移过去只是原地挪一小步，还要白送 2.4s 的消失/出现演出）。
## 必须明显大于 teleport 的 max_appear_distance(200)，否则净位移接近 0。
@export var teleport_min_range: float = 450.0

# ---- 技能冷却（硬门槛：收招后多久内不再被选）----
# 一律用「到期时间戳」而不是「剩余秒数倒计时」：
# 倒计时只能在 idle.update 里递减，而 idle 每次只活 decision_interval(0.1s)、
# 其余时间全在 walk / dash / slash 等状态里 —— 名字上 2s 的冷却，实际会被拉长成十几秒真实时间，
# 追风筝时几乎发不出 dash。时间戳在任何状态下都按真实时间自然过期，不需要谁去递减。
@export var counter_cooldown: float = 2.0      ## counter 收招后多久内不再被选（避免反复招架）
var _counter_cd_until: float = 0.0
@export var dash_cooldown: float = 5.0        ## dash 收招后多久内不再被选（避免冲刺过于频繁）
var _dash_cd_until: float = 0.0
@export var evade_cooldown: float = 2.0        ## evade 收招后多久内不再被选（避免后撤过于频繁）
var _evade_cd_until: float = 0.0
@export var teleport_cooldown: float = 5.0      ## teleport 收招后多久内不再被选（与 dash 同规格）
var _teleport_cd_until: float = 0.0
@export var down_smash_cooldown: float = 6.0    ## down_smash 收招后多久内不再被选（二阶段专属）
var _down_smash_cd_until: float = 0.0
@export var teleport_smash_cooldown: float = 6.0 ## teleport_smash 收招后多久内不再被选（二阶段专属）
var _teleport_smash_cd_until: float = 0.0

## 头顶实时显示决策权重（调试用）。需同时打开全局调试开关 Globals.debug_enabled。
@export var show_decision_debug: bool = false
var _decision_label: Label = null

func enter(_from: StringName) -> void:
	if boss == null:
		return
	# 过场（沉睡 → 苏醒坠落 → 吼叫）全部结束，正式解锁：玩家自此可以攻击 boss。
	# 与 HollowKnight.is_cutscene_invulnerable() 配套：锁定期间靠状态名挡住伤害，
	# 进入 idle 后状态名不再属于锁定集，这里再把残留的 invincible 清干净。
	boss.invincible = false
	_decision_timer = 0.0
	# 若上一招是 counter（刚收招回到 idle），开启冷却，避免立刻再选 counter 形成反复招架死循环。
	if _last_action == BossStateNames.COUNTER:
		_counter_cd_until = _now() + counter_cooldown
	# 若上一招是 dash，开启冷却，避免冲刺过于频繁。
	if _last_action == BossStateNames.DASH:
		_dash_cd_until = _now() + dash_cooldown
	# 若上一招是 evade，开启冷却，避免后撤过于频繁。
	if _last_action == BossStateNames.EVADE:
		_evade_cd_until = _now() + evade_cooldown
	# 若上一招是 teleport，开启冷却，避免瞬移过于频繁（与 dash 同规格）。
	if _last_action == BossStateNames.TELEPORT:
		_teleport_cd_until = _now() + teleport_cooldown
	# 若上一招是 down_smash，开启冷却，避免二阶段频繁跃击。
	if _last_action == BossStateNames.DOWN_SMASH:
		_down_smash_cd_until = _now() + down_smash_cooldown
	# 若上一招是 teleport_smash，开启冷却，避免二阶段频繁瞬移下杀。
	if _last_action == BossStateNames.TELEPORT_SMASH:
		_teleport_smash_cd_until = _now() + teleport_smash_cooldown
	# 待机期间关闭挥砍命中盒，避免站定时误伤。
	boss.disable_melee_attack()
	boss.action_animation_player.play(BossStateNames.IDLE)

func update(delta: float) -> void:
	# 待机：站定（清水平速度），不做接触伤害结算。
	boss.velocity.x = 0.0
	boss._apply_vertical_motion(delta)
	boss._apply_movement()

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
	var pool: Array[StringName] = [BossStateNames.WALK, BossStateNames.SLASH, BossStateNames.DASH, BossStateNames.TELEPORT, BossStateNames.COUNTER, BossStateNames.EVADE]
	# 二阶段才解锁下砸跃击（朝玩家头顶的自预警 AoE）。
	if boss != null and boss.phase_index >= 1:
		pool.append(BossStateNames.DOWN_SMASH)
		pool.append(BossStateNames.TELEPORT_SMASH)
	return pool


## 硬门槛：只负责"这招现在能不能放"，不关心权重。
## 权重的职责是"偏好"，门槛的职责是"合法性"——两者不要混，
## 否则会出现"权重压得再低也照样放"或"权重很高但永远放不出"的调参地狱。
func _filter_actions(pool: Array[StringName], distance: float) -> Array[StringName]:
	var attacking := boss.is_player_attacking() if boss != null else false
	var out: Array[StringName] = []
	for action in pool:
		if action == BossStateNames.SLASH:
			# slash 仅当玩家进入 attack_range 才合法。
			if distance > attack_range:
				continue
		elif action == BossStateNames.COUNTER:
			# 招架仅当玩家"真的在出招"、且在近战范围内、且不在冷却中才合法。
			# 玩家没出招时选 counter = 白站近 3 秒（0.9s 起手 + 招架窗口），
			# 这不是"防守"，是"发呆"，必须由硬门槛排除而不是靠权重压低。
			if not attacking or distance > attack_range or _cooling(_counter_cd_until):
				continue
		elif action == BossStateNames.DASH:
			# 冲刺仅当：距离不超过可达上限、玩家不在 slash 攻击范围内、且不在冷却中。
			# （进入 attack_range 即视为贴脸，优先 slash 而非继续冲）。
			if distance > DASH_RANGE or distance <= attack_range or _cooling(_dash_cd_until):
				continue
		elif action == BossStateNames.TELEPORT:
			# 瞬移仅当：距离足够远（近距瞬移 = 原地换个姿势，白送 2.4s 演出，收益为负）、
			# 不超过可达上限、且不在冷却中。
			# 门槛比 attack_range 更严：teleport 落点固定贴在玩家身边（appear_distance≈130），
			# 从 160~260 这种"刀外沿"瞬移过去只是原地挪一小步，必须由 teleport_min_range 排除。
			if distance < teleport_min_range or distance > DASH_RANGE or _cooling(_teleport_cd_until):
				continue
		elif action == BossStateNames.EVADE:
			# 后撤只在近战圈附近合法：中远距离还后撤，战斗就变成追逃循环了。
			if distance > edge_range or _cooling(_evade_cd_until):
				continue
		elif action == BossStateNames.DOWN_SMASH:
			# 二阶段专属 AoE：自预警、无距离硬门槛，仅在冷却中排除。
			if _cooling(_down_smash_cd_until):
				continue
		elif action == BossStateNames.TELEPORT_SMASH:
			# 二阶段专属 AoE：瞬移到玩家头顶自预警，无距离硬门槛，仅在冷却中排除。
			if _cooling(_teleport_smash_cd_until):
				continue
		out.append(action)
	return out


## 加权表：距离分层定基础偏好，情境与连招做有界修正。
## 关键约束：所有乘法都必须走 _mul（幅度夹在 0.1~4）。
## 旧的 evade ×40 一次性吃掉全部随机性，连 ×0.2 的反重复惩罚都压不住，
## 才会出现"贴脸 91% 后撤"的逃跑型 BOSS。
func _weights(distance: float, player_attacking: bool) -> Dictionary:
	var w := _base_weights(distance)

	if player_attacking:
		if distance <= attack_range:
			# 玩家正在出招且贴身：优先招架 / 后撤，不硬拼。
			_mul(w, BossStateNames.SLASH, 0.45)
			_mul(w, BossStateNames.WALK, 0.5)
			_mul(w, BossStateNames.COUNTER, 2.6)
			_mul(w, BossStateNames.EVADE, 2.2)
		else:
			# 玩家在刀外沿挥空：别一头撞进判定，先等他的收招空档。
			_mul(w, BossStateNames.DASH, 0.45)
			_mul(w, BossStateNames.EVADE, 1.4)
			_mul(w, BossStateNames.WALK, 1.6)

	if _player_retreating():
		# 玩家背向逃跑：走路 230px/s 追不上跑速 384 的玩家，追赶只能靠 dash / 瞬移。
		# 这里刻意压低 WALK 而不是抬高 —— 抬高 WALK 会让 BOSS 更容易进入"一路走到底"的 walk 状态，
		# 恰好是"拉开距离后只会慢慢靠近"的成因。
		_mul(w, BossStateNames.DASH, 1.8)
		_mul(w, BossStateNames.TELEPORT, 1.8)
		_mul(w, BossStateNames.WALK, 0.5)

	if boss != null and boss.phase_index >= 1:
		# 二阶段：down_smash 朝玩家头顶跃击的自预警 AoE，中近距离偏重、超远距压低（砸不到）。
		var w2 := 1.8
		if distance > mid_range:
			w2 = 0.5
		w[BossStateNames.DOWN_SMASH] = w2
		# teleport_smash 也是二阶段 AoE，但靠瞬移贴脸，超远距离也能用（down_smash 砸不到远处）。
		var w3 := 1.6
		if distance > mid_range:
			w3 = 1.2
		w[BossStateNames.TELEPORT_SMASH] = w3

	_apply_chain(w)
	return w


## 距离分层基础权重：层间互斥，只命中一层；层内一次定好，不再跨层累乘。
func _base_weights(distance: float) -> Dictionary:
	var w := {
		BossStateNames.WALK: 0.0,
		BossStateNames.SLASH: 0.0,
		BossStateNames.DASH: 0.0,
		BossStateNames.TELEPORT: 0.0,
		BossStateNames.COUNTER: 0.0,
		BossStateNames.EVADE: 0.0,
		BossStateNames.DOWN_SMASH: 0.0,
		BossStateNames.TELEPORT_SMASH: 0.0,
	}
	if distance <= point_range:
		# 贴身：以砍为主，留一点停顿做呼吸节拍（walk 在此距离等价于站 0.1s）。
		w[BossStateNames.WALK] = 1.0
		w[BossStateNames.SLASH] = 3.2
		w[BossStateNames.COUNTER] = 1.0
		w[BossStateNames.EVADE] = 0.8
	elif distance <= attack_range:
		# 刀范围内：继续压上，后撤欲很低。
		w[BossStateNames.WALK] = 1.2
		w[BossStateNames.SLASH] = 3.0
		w[BossStateNames.COUNTER] = 1.2
		w[BossStateNames.EVADE] = 0.9
	elif distance <= edge_range:
		# 刀刚好够不到：唯一正确的选择是短突进，而不是后撤 / 瞬移。
		# teleport 在这一层恒为 0：本层上限 edge_range(260) 本来就在 teleport_min_range 之内，
		# 给了权重也放不出来，留着只会让权重表看起来"有瞬移"而实际没有。
		w[BossStateNames.WALK] = 1.0
		w[BossStateNames.DASH] = 2.2
		w[BossStateNames.EVADE] = 0.3
	elif distance <= mid_range:
		w[BossStateNames.WALK] = 1.2
		w[BossStateNames.DASH] = 2.8
		w[BossStateNames.TELEPORT] = 2.2
	else:
		# 远距离：BOSS 走路（192px/s）追不上玩家（384px/s），接近只能靠 dash / 瞬移。
		w[BossStateNames.WALK] = 0.5
		w[BossStateNames.DASH] = 4.0
		w[BossStateNames.TELEPORT] = 3.0
	return w


## 连招节奏：让 BOSS 看起来"有意图"，而不是每招独立随机。
## "砍完拉开半步观察、撤完立刻反扑"是把"逃跑"翻译成"试探"的关键。
func _apply_chain(w: Dictionary) -> void:
	if _last_action == BossStateNames.SLASH:
		# 砍完拉开半步，看玩家怎么反应。
		_mul(w, BossStateNames.EVADE, 1.6)
		_mul(w, BossStateNames.WALK, 1.3)
	elif _last_action == BossStateNames.EVADE:
		# 后撤是"引招"不是逃跑：撤完立刻反扑，避免进入追逃循环。
		_mul(w, BossStateNames.DASH, 2.2)
		_mul(w, BossStateNames.SLASH, 1.4)
		_mul(w, BossStateNames.EVADE, 0.2)
	elif _last_action == BossStateNames.DASH:
		# 冲到面前就压上去接砍。
		_mul(w, BossStateNames.SLASH, 1.6)
	elif _last_action == BossStateNames.COUNTER:
		# 反击 / 收招后继续施压。
		_mul(w, BossStateNames.SLASH, 1.5)
		_mul(w, BossStateNames.WALK, 1.3)


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


## 玩家是否在拉开距离（速度背离 BOSS）：追风筝玩家的信号。
func _player_retreating() -> bool:
	if boss == null:
		return false
	var p := boss.get_player()
	if p == null:
		return false
	var vx := 0.0
	if p is CharacterBody2D:
		vx = (p as CharacterBody2D).velocity.x
	if absf(vx) < 40.0:
		return false
	var away := signf(p.global_position.x - boss.global_position.x)
	return signf(vx) == away


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
