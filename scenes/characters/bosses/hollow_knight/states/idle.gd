extends BossDecisionState
class_name HollowKnightIdleState

## 决策中枢：不做任何移动或攻击，只负责每隔状态机上的 decision_interval 秒决定下一步做什么。
## 站定 / 面向玩家 / 决策节奏 / 技能冷却（cooldowns 在场景的 idle 节点上配）全部由
## BossDecisionState 提供；本状态只给距离门槛、招式池与权重表。
##
## 冷却一律用「到期时间戳」而不是「剩余秒数倒计时」：
## 倒计时只能在 idle.update 里递减，而 idle 每次只活 decision_interval(0.1s)、
## 其余时间全在 walk / dash / slash 等状态里 —— 名字上 2s 的冷却，实际会被拉长成十几秒真实时间。
## 时间戳在任何状态下都按真实时间自然过期，不需要谁去递减。


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


func enter(from: StringName) -> void:
	super.enter(from)
	# 过场（沉睡 → 苏醒坠落 → 吼叫）全部结束，正式解锁：玩家自此可以攻击 boss。
	# 与 Boss.is_cutscene_invulnerable() 配套：锁定期间靠状态名挡住伤害，
	# 进入 idle 后状态名不再属于锁定集，这里再把残留的 invincible 清干净。
	if boss != null:
		boss.invincible = false
		# 过场全部结束 = 正式开战：补上 begin_fight()（→ enter_combat），与
		# SoulMaster 入场演出收尾一致。boss_activated 已在四链全断时发过（幂等），
		# 这里负责仇恨 / BGM 等开战广播；每次复位后重进 idle 也会重新拉起仇恨。
		boss.begin_fight()


# ---- 决策三件套（基类 decide_next 会调用这三个钩子）----

## 当前阶段可用招式池：多阶段时按 boss.phase_index 返回不同集合。
func _available_actions() -> Array[StringName]:
	var pool: Array[StringName] = [
		BossStateNames.WALK, BossStateNames.SLASH, BossStateNames.DASH,
		BossStateNames.TELEPORT, BossStateNames.COUNTER, BossStateNames.EVADE]
	# 二阶段才解锁下砸跃击（朝玩家头顶的自预警 AoE）。
	if boss != null and boss.phase_index >= 1:
		pool.append(BossStateNames.DOWN_SMASH)
		pool.append(BossStateNames.TELEPORT_SMASH)
	return pool


## 硬门槛：只负责"这招现在能不能放"，不关心权重。冷却由 super 统一过滤。
## 权重的职责是"偏好"，门槛的职责是"合法性"——两者不要混，
## 否则会出现"权重压得再低也照样放"或"权重很高但永远放不出"的调参地狱。
func _filter_actions(pool: Array[StringName], distance: float) -> Array[StringName]:
	var attacking := boss.is_player_attacking() if boss != null else false
	var out: Array[StringName] = []
	for action in super._filter_actions(pool, distance):
		if action == BossStateNames.SLASH:
			# slash 仅当玩家进入 attack_range 才合法。
			if distance > attack_range:
				continue
		elif action == BossStateNames.COUNTER:
			# 招架仅当玩家"真的在出招"、且在近战范围内才合法。
			# 玩家没出招时选 counter = 白站近 3 秒，这不是"防守"是"发呆"。
			if not attacking or distance > attack_range:
				continue
		elif action == BossStateNames.DASH:
			# 冲刺仅当：距离不超过可达上限、玩家不在 slash 攻击范围内。
			if distance > DASH_RANGE or distance <= attack_range:
				continue
		elif action == BossStateNames.TELEPORT:
			# 瞬移仅当：距离足够远（近距瞬移 = 原地换个姿势，白送 2.4s 演出）。
			if distance < teleport_min_range or distance > DASH_RANGE:
				continue
		elif action == BossStateNames.EVADE:
			# 后撤只在近战圈附近合法：中远距离还后撤，战斗就变成追逃循环了。
			if distance > edge_range:
				continue
		# down_smash / teleport_smash 是二阶段专属 AoE，只有冷却这一个门槛，
		# 已由 super 过滤，不需要再写分支。
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
		# 这里刻意压低 WALK 而不是抬高 —— 抬高 WALK 会让 BOSS 更容易进入"一路走到底"的 walk 状态。
		_mul(w, BossStateNames.DASH, 1.8)
		_mul(w, BossStateNames.TELEPORT, 1.8)
		_mul(w, BossStateNames.WALK, 0.5)

	if boss != null and boss.phase_index >= 1:
		# 二阶段：down_smash 朝玩家头顶跃击的自预警 AoE，中近距离偏重、超远距压低（砸不到）。
		var w2 := 1.8
		if distance > mid_range:
			w2 = 0.5
		w[BossStateNames.DOWN_SMASH] = w2
		# teleport_smash 也是二阶段 AoE，但靠瞬移贴脸，超远距离也能用。
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
		# teleport 在这一层恒为 0：本层上限 edge_range(260) 本来就在 teleport_min_range 之内。
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
		_mul(w, BossStateNames.EVADE, 1.6)
		_mul(w, BossStateNames.WALK, 1.3)
	elif _last_action == BossStateNames.EVADE:
		_mul(w, BossStateNames.DASH, 2.2)
		_mul(w, BossStateNames.SLASH, 1.4)
		_mul(w, BossStateNames.EVADE, 0.2)
	elif _last_action == BossStateNames.DASH:
		_mul(w, BossStateNames.SLASH, 1.6)
	elif _last_action == BossStateNames.COUNTER:
		_mul(w, BossStateNames.SLASH, 1.5)
		_mul(w, BossStateNames.WALK, 1.3)


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
