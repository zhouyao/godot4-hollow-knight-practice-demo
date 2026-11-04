class_name BossHollowKnight
extends Boss

const BOSS_PLUME_SCENE := preload("res://scenes/characters/bosses/hollow_knight/effects/boss_plume.tscn")

## 二阶段触发线：剩余血量比例低于该值即进二阶段（怒吼演出）。
const PHASE_TWO_RATIO: float = 0.5

## 招架中：为 true 时，正面来袭伤害不结算、不进受击硬直，改发 blocked 让 counter 状态接手反击；
## 但若伤害来自背后（背刺），则正常结算并改发 guard_broken，让 counter 状态立刻解除。
## 由 HollowKnightCounterState 在 READY 相位开关；正/背判定见 _is_front_damage。
var blocking: bool = false
## 格挡成功（正面伤害被挡下）时发出，参数为伤害来源。
signal blocked(from: Node2D)
## 招架中被背刺破招（伤害来自背后）时发出，参数为伤害来源；counter 据此立刻退出招架。
signal guard_broken(from: Node2D)


## 继承链上的 _ready：Enemy 里会解析 tuning / 音频 / 朝向 / 领地并启动状态机，所以必须先 super。
func _ready() -> void:
	# 过场锁定集由 Boss 基类统一判定；必须在 super._ready() 之前填 ——
	# Enemy._ready() 会启动状态机并立刻进 dormant，晚一帧就有可乘之机。
	cutscene_states = [
		BossStateNames.DORMANT,
		BossStateNames.DORMANT_END,
		BossStateNames.SCREAM,
	]
	super._ready()
	# 悬崖探测器跟着朝向换边：只影响编辑器 / 调试里的可视化。
	# 判定由 Boss.has_ground_ahead() 按"传入方向 + absf(position.x)"即时计算，与节点当前朝向无关。
	flip_nodes = [ground_probe_path]

## ---- 过场锁定：沉睡 / 苏醒坠落 / 苏醒吼叫期间不可被玩家攻击 ----
## 状态名列表在 _ready() 里填给 Boss.cutscene_states；判定（is_cutscene_invulnerable /
## is_invulnerable）由 Boss 基类统一实现，玩家侧 player.gd 与本类 take_damage 共用一份判据。
## 用"当前状态名"判定而不是再靠一个布尔：状态一离开锁定集（进入 idle）就自动解锁，
## 不需要任何状态记得去关 —— 也不会被受击无敌计时器超时误清。

func take_damage(amount: int, from: Node2D = null) -> void:
	# 过场锁定 / 受击无敌帧 / 死亡：整体拒绝，连招架、背刺破招、阶段切换都不触发。
	if is_invulnerable():
		return
	if blocking:
		if _is_front_damage(from):
			blocked.emit(from)
			return
		# 背刺破招：正常结算伤害（受击特效 / 掉血 / 无敌帧），并通知 counter 立刻解除招架。
		# 阶段推进由 Boss.take_damage() 在"真掉血且没死"后统一处理，本类不必再调。
		super.take_damage(amount, from)
		guard_broken.emit(from)
		return
	super.take_damage(amount, from)


## 阶段策略：二阶段 = 血量跌破 PHASE_TWO_RATIO → 怒吼演出（一阶段不做任何事）。
## 以后加三阶段就在下面继续写 elif；每个分支里可以顺手做任何事
## （换 BGM、刷小怪、改 contact_damage、给自身挂无敌帧……），不受任何"阶段表"限制。
func _check_phase_policy() -> void:
	if phase_index == 0 and health_ratio() <= PHASE_TWO_RATIO:
		start_phase(1)
		if state_machine != null:
			state_machine.set_state(BossStateNames.SCREAM)

## 伤害是否来自 boss 正面（朝向一侧）。来源在朝向侧即视为正面，与玩家 _is_blocking 同判据。
func _is_front_damage(from: Node2D) -> bool:
	if from == null:
		return false
	var side := signf(from.global_position.x - global_position.x)
	return side == float(move_direction)

## 在 BOSS 领地内施放一排 boss_plume。
## 领地模式（传了宽度 >0 的 territory）：根数 = 领地可用宽度 / spacing（动态，至少 1 根），
## 整组按 spacing 等距、居中于领地，两端各内缩半个 plume 宽度，确保羽柱不越出领地。
## 退回模式（未传 territory 或其宽度 <=0）：以 center 为中点、固定 count 根、相邻间距 spacing，
## 兼容尚未绑定 BossArena 的旧布局 / 非领地技能（如 teleport_smash）。
## 返回 plume 数组，供后续 burst_plumes() 引爆 / free_plumes() 清理。
func spawn_plume_field(center: Vector2, count: int, spacing: float, damage: int, territory: Rect2 = Rect2()) -> Array:
	var out: Array = []
	if territory.size.x > 0.0 and spacing > 0.0:
		# 领地模式：根数随领地宽度动态算，整组居中于领地、不越界。
		var extent := 30.0  # plume 半宽（碰撞框宽 61 的一半），两端内缩用。
		var usable := maxf(territory.size.x - extent * 2.0, spacing)
		var n := maxi(1, int(floorf(usable / spacing)) + 1)
		var field_width := (n - 1) * spacing
		var start_x := territory.get_center().x - field_width * 0.5
		for i in n:
			_add_plume(out, start_x + i * spacing, center.y, damage)
	else:
		# 退回模式：以 center 为中点等距铺开 count 根。
		var n := maxi(count, 1)
		var total_width := (n - 1) * spacing
		for i in n:
			_add_plume(out, center.x - total_width * 0.5 + i * spacing, center.y, damage)
	return out


## 实例化一根 plume 并加进当前场景（抽出公共逻辑，避免上述两条分支重复）。
func _add_plume(out: Array, x: float, y: float, damage: int) -> void:
	var plume := BOSS_PLUME_SCENE.instantiate() as BossPlume
	if plume == null:
		return
	plume.setup(damage, self)
	get_tree().current_scene.add_child(plume)
	plume.global_position = Vector2(x, y)
	out.append(plume)


## 批量引爆一组 plume（播放 plume_burst 并对范围内玩家结算一次）。
func burst_plumes(plumes: Array) -> void:
	for p in plumes:
		if is_instance_valid(p):
			(p as BossPlume).burst()


## 清理一组 plume（状态退出 / BOSS 被打断、死亡时释放残留）。
func free_plumes(plumes: Array) -> void:
	for p in plumes:
		if is_instance_valid(p):
			(p as BossPlume).queue_free()
