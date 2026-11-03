class_name BossHollowKnight
extends Boss

const BOSS_PLUME_SCENE := preload("res://scenes/characters/bosses/hollow_knight/effects/boss_plume.tscn")

@onready var ledge_detector: RayCast2D = $LedgeDetector

## 招架中：为 true 时，正面来袭伤害不结算、不进受击硬直，改发 blocked 让 counter 状态接手反击；
## 但若伤害来自背后（背刺），则正常结算并改发 guard_broken，让 counter 状态立刻解除。
## 由 HollowKnightCounterState 在 READY 相位开关；正/背判定见 _is_front_damage。
var blocking: bool = false
## 格挡成功（正面伤害被挡下）时发出，参数为伤害来源。
signal blocked(from: Node2D)
## 招架中被背刺破招（伤害来自背后）时发出，参数为伤害来源；counter 据此立刻退出招架。
signal guard_broken(from: Node2D)

## 二阶段触发阈值（剩余血量 / 最大血量）。血量跨过该线即进入二阶段演出。
const PHASE_TWO_THRESHOLD := 0.5

## ---- 过场锁定：沉睡 / 苏醒坠落 / 苏醒吼叫期间不可被玩家攻击 ----
## 这三态都属于"过场"：玩家从开局进领地、到砍断四根锁链、再到吼叫结束，全程打不掉血。
## 用"当前状态名"判定而不是再靠一个布尔：状态一离开锁定集（进入 idle）就自动解锁，
## 不需要任何状态记得去关 —— 也不会被受击无敌计时器超时误清。
const CUTSCENE_STATES: Array[StringName] = [
	BossStateNames.DORMANT,
	BossStateNames.DORMANT_END,
	BossStateNames.SCREAM,
]

## 是否处于过场锁定。状态机未启动 / 状态名未知时按"锁定"处理：宁可多无敌，不可误伤。
func is_cutscene_invulnerable() -> bool:
	if state_machine == null or state_machine.current_state_name == &"":
		return true
	return state_machine.current_state_name in CUTSCENE_STATES

## 覆盖基类：受击无敌帧 / 死亡之外，再叠一层过场锁定。
func is_invulnerable() -> bool:
	return super.is_invulnerable() or is_cutscene_invulnerable()

func take_damage(amount: int, from: Node2D = null) -> void:
	# 过场锁定 / 受击无敌帧 / 死亡：整体拒绝，连招架、背刺破招、阶段切换都不触发。
	# 阶段切换必须挂在"真的掉血"之后 —— 否则被无敌挡下的攻击也会推进二阶段演出。
	if is_invulnerable():
		return
	if blocking:
		if _is_front_damage(from):
			blocked.emit(from)
			return
		# 背刺破招：正常结算伤害（受击特效 / 掉血 / 无敌帧），并通知 counter 立刻解除招架。
		super.take_damage(amount, from)
		guard_broken.emit(from)
		_try_enter_phase_two()
		return
	super.take_damage(amount, from)
	_try_enter_phase_two()

## 血量跨过二阶段阈值：切到 phase_index=1，强制演出 scream（音效由 scream.gd 按阶段选）。
## 不做过场无敌——scream 会定身玩家，过场期间无法被攻击。
func _try_enter_phase_two() -> void:
	if dead or phase_index >= 1:
		return
	if health > int(max_health * PHASE_TWO_THRESHOLD):
		return
	start_phase(1)
	if state_machine != null:
		state_machine.set_state(BossStateNames.SCREAM)

## 伤害是否来自 boss 正面（朝向一侧）。来源在朝向侧即视为正面，与玩家 _is_blocking 同判据。
func _is_front_damage(from: Node2D) -> bool:
	if from == null:
		return false
	var side := signf(from.global_position.x - global_position.x)
	return side == float(move_direction)

func _flip_extra() -> void:
	super._flip_extra()  # 翻转 muzzle（吐弹口），保留 Enemy 基类行为
	if ledge_detector != null:
		ledge_detector.position.x = absf(ledge_detector.position.x) * float(move_direction)
		ledge_detector.reset_physics_interpolation()


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
