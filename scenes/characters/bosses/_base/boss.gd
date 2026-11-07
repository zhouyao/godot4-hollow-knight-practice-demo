class_name Boss
extends Enemy


## 击败演出开始时发出（BOSS 专有）。
## 与 Enemy.enemy_death 的分工：enemy_death 负责"状态机转 defeat"，
## 本信号负责对外（存档标记 / 解锁 / 转场）。
signal boss_defeated
## BOSS 被激活（收到第一次开战请求）时发出，早于入场演出与 enter_combat。
## 需要"一激活就封锁退路"的关卡组件（雾门等）监听它；整场战斗只发一次。
signal boss_activated
## 阶段切换时发出，参数为新阶段的索引（0 起）。
signal phase_changed(phase_index: int)

## 当前阶段索引，0 起。
var phase_index: int = 0
## boss_activated 只发一次：入场演出收尾、领地反复拉仇恨、受击都会再走开战路径。
var _activated: bool = false


#region 过场锁定与生命周期（BOSS 通用）
## 处于这些状态名时免疫玩家伤害（沉睡 / 入场 / 苏醒演出等）。
## 子类在 _ready() 里、super._ready() 之前填（Enemy._ready() 会启动状态机并立刻进 dormant）。
## 状态机未启动 / 状态名未知时按"锁定"处理：宁可多无敌，不可误伤。
@export_group("过场锁定")
@export var cutscene_states: Array[StringName] = []


## 覆盖 Enemy 的空钩子：玩家侧 player.gd 的挥砍命中直接调用本方法，
## 过场期间把攻击整体穿透（不结算伤害 / 能量 / recoil），实现只需一份。
func is_cutscene_invulnerable() -> bool:
	if cutscene_states.is_empty():
		return false
	if state_machine == null or state_machine.current_state_name == &"":
		return true
	return state_machine.current_state_name in cutscene_states


## 与 is_cutscene_invulnerable() 保持同一判据：take_damage() 的首行守卫也走这里。
func is_invulnerable() -> bool:
	return super.is_invulnerable() or is_cutscene_invulnerable()


## 接触伤害的"设计值"：候场 / 入场 / 招式会临时关掉它，退出时按此还原。
## 直接还原"进入状态时的值"只会得到 dormant 关掉的 false，BOSS 就永远不蹭人了。
var base_contact_damage: bool = true


## 开发设置把敌方血量分成 BOSS / 小怪两项：BOSS 走自己那一项。
## Enemy._ready() 通过虚方法取覆盖值，基类不必反向依赖 Boss 子类。
func _health_override() -> int:
	return Globals.boss_health_override


func _ready() -> void:
	# 必须早于 super._ready()：Enemy._ready() 里的 state_machine.start() 会进 dormant 并关掉它。
	base_contact_damage = contact_damage_enabled
	super._ready()


func restore_contact_damage() -> void:
	contact_damage_enabled = base_contact_damage
#endregion


## 近战攻击（slash / 突进斩等）对玩家造成的伤害。通用，子类可覆盖。
@export var melee_damage: int = 1

## 距玩家的水平距离（绝对值），决策与权重统一取用。
func player_distance() -> float:
	var p := get_player()
	if p == null:
		return INF
	return absf(p.global_position.x - global_position.x)

## 玩家此刻是否在攻击（读全局标志，覆盖所有进攻型状态）。
func is_player_attacking() -> bool:
	return PlayerCombat.is_attacking

# ---- 朝向翻转扩展 ----
## 随朝向左右镜像的节点（探测器、挂点等）：位置 x 取绝对值后乘当前朝向。
## 子类在 Inspector 里填即可，不必为了翻一个节点去重写 _flip_extra。
## 注意：只影响节点的摆位（编辑器里的可视化），判定逻辑应自行按传入方向计算，不要依赖节点的实时朝向。
@export var flip_nodes: Array[NodePath] = []

# ---- 通用近战命中盒（节点名默认 MeleeHitBox，具体 Boss 场景自带该节点）----
@export var melee_hitbox_path: NodePath = ^"MeleeHitBox"
var _melee_hit_this_swing: bool = false

## 开启命中盒：激活碰撞形状 + 监听 body_entered + 重置本次挥砍命中标记。
func enable_melee_attack() -> void:
	_set_melee_hitbox_active(true)
	_melee_hit_this_swing = false
	_sync_melee_hitbox_facing()  # 开启即按当前朝向镜像命中盒
	var box := get_node_or_null(melee_hitbox_path) as Area2D
	if box != null and not box.body_entered.is_connected(_on_melee_hitbox_body_entered):
		box.body_entered.connect(_on_melee_hitbox_body_entered)
	# 开盒即补判：命中盒常由动画在指定帧才打开（如 slash）。若此时玩家已静止站在盒内，
	# body_entered 不一定会补发 entered 信号，故延迟到下一物理帧（monitoring 已生效）手动结算一次。
	# _melee_hit_this_swing 已去重，即便 body_entered 也触发了也只掉一次血。
	if box != null:
		call_deferred("_melee_check_overlap", box)

## 开盒补判：monitoring 经 set_deferred 在下一物理帧才生效，故延迟到此再查一次当前重叠体，
## 覆盖"命中盒开启瞬间玩家已静止站在盒内"导致 body_entered 不补发的边界情况。
func _melee_check_overlap(box: Area2D) -> void:
	if box == null or not is_instance_valid(box):
		return
	for b in box.get_overlapping_bodies():
		_on_melee_hitbox_body_entered(b)

## 关闭命中盒：停用形状 + 断开监听。
func disable_melee_attack() -> void:
	_set_melee_hitbox_active(false)
	var box := get_node_or_null(melee_hitbox_path) as Area2D
	if box != null and box.body_entered.is_connected(_on_melee_hitbox_body_entered):
		box.body_entered.disconnect(_on_melee_hitbox_body_entered)

## 命中盒镜像到当前朝向：MeleeHitBox 是 boss 根节点的子节点，而转向只翻 AnimatedSprite 的
## scale.x（见 enemy_facing._sync_facing），根节点子节点不会跟着翻，故命中盒永远停在固定一侧。
## 这里手动把命中盒 scale.x 设成与逻辑朝向一致（±1）：以 boss 中心为原点、多边形整体偏右，
## scale.x = -1 即把多边形镜像到左侧，朝左攻击时命中盒跟着转到左边。
func _sync_melee_hitbox_facing() -> void:
	var box := get_node_or_null(melee_hitbox_path) as Area2D
	if box != null:
		box.scale.x = float(move_direction)

## 激活/停用命中盒的碰撞形状与 monitoring（默认形状 disabled=true，只在出招时打开）。
func _set_melee_hitbox_active(active: bool) -> bool:
	var box := get_node_or_null(melee_hitbox_path) as Area2D
	if box == null:
		return false
	# 用 set_deferred：调用方常在物理查询 flush 期间（如 body_exited 信号里触发状态切换）
	# 改监测状态，直接赋值会报 "Can't change this state while flushing queries"。
	box.set_deferred("monitoring", active)
	for child in box.get_children():
		if child is CollisionShape2D or child is CollisionPolygon2D:
			child.set_deferred("disabled", not active)
	return true

func _on_melee_hitbox_body_entered(body: Node) -> void:
	if _melee_hit_this_swing:
		return
	var p := get_player()
	if body == p and p != null and p.has_method("take_damage"):
		_melee_hit_this_swing = true
		p.take_damage(melee_damage, self)


## 翻面扩展点（与 Enemy._flip_extra 构成多态链）：Enemy 翻 muzzle（吐弹口），
## Boss 再把 flip_nodes 里列出的节点跟着翻，并同步近战命中盒的镜像方向。
## 子类要加"只有本 BOSS 才需要翻"的节点，优先填 flip_nodes，而不是重写本方法。
func _flip_extra() -> void:
	super._flip_extra()
	# 命中盒是根节点子节点，不随精灵翻面，必须自己镜像（见 _sync_melee_hitbox_facing）。
	# 挂在这里而不是每帧轮询：move_direction 只在 EnemyFacing._flip_direction() 里变，
	# 而它每次都会回调本方法；出招开启命中盒时 enable_melee_attack() 还会再同步一次。
	_sync_melee_hitbox_facing()
	for path in flip_nodes:
		var node := get_node_or_null(path) as Node2D
		if node == null:
			continue
		node.position.x = absf(node.position.x) * float(move_direction)
		node.reset_physics_interpolation()


## 驻留状态：BOSS 不巡逻，沉睡 / 待机即 dormant。
## EnemyAggro.tick_zone_aggro() 会拿它比对当前状态；BOSS 没绑领地时那条路径本就不生效，
## 这里给出正确值是为了将来"用领地触发开战"时语义一致。
func resting_state() -> StringName:
	return BossStateNames.DORMANT


## 开战入口：由 BossArena 在玩家踏入时调用，或由入场动画的方法轨道在演出结束时调用。
## 走 Enemy 现成的仇恨广播（enter_combat_zone → _set_combat → enter_combat 信号），
## 关卡侧监听 enter_combat 即可切 BGM / 亮血条 —— 与领地开战是同一条路径。
## 需要"一激活就锁门"的组件改听 boss_activated：带入场演出的 BOSS 会先演出数秒。
func begin_fight() -> void:
	if dead or combat_active:
		return
	notify_boss_activated()
	enter_combat_zone()


## 领地仇恨 / 接触命中会绕过 begin_fight() 直接走这里，补发一次激活。
## 子类覆盖后若不调 super（如 SoulMaster 的入场分支），需自行调 notify_boss_activated()。
func enter_combat_zone() -> void:
	notify_boss_activated()
	super.enter_combat_zone()


## 广播"BOSS 已激活"，幂等。放在切状态 / 拉仇恨之前，保证是第一时间发出。
func notify_boss_activated() -> void:
	if _activated:
		return
	_activated = true
	boss_activated.emit()


func start_phase(index: int) -> void:
	if index == phase_index:
		return
	phase_index = index
	phase_changed.emit(index)


## 击败：先走基类的死亡结算（掉奖励、发 enemy_death → 状态机转 defeat），
## 再广播 BOSS 专有的 boss_defeated 供存档 / 解锁 / 转场监听。
func _dead() -> void:
	super._dead()
	boss_defeated.emit()
	# 关卡内信号只给"撤雾墙 / 灯光"这类局部组件用；胜利 UI 常驻在 GameRoot，
	# 跨关卡也拿不到 BOSS 节点，故再经 GameSession 广播一次（所有 BOSS 通用）。
	GameSession.notify_boss_defeated(persistent_id)


## BOSS 不做尸体淡出。
## _dead() 里的 _start_corpse_fade() 会在 corpse_lifetime 秒后把节点 queue_free 掉，
## 那会打断击败演出（动画没播完、信号没发完）。演出与清理全部交给 death 状态。
func _start_corpse_fade() -> void:
	pass


## BOSS 的奖励掉落延后到击败演出（death 状态）收尾再撒，
## 避免"一断气就爆金币"打断 boss 升天淡出的演出节奏。
## 基类 Enemy._dead() 里调用的 _drop_loot() 在此改为空操作，真正的掉落交给下面的 drop_loot()。
func _drop_loot() -> void:
	pass


## 击败演出收尾时由 death 状态调用：在 at 处（不传则跟随 DropMarker）撒落奖励。
## at 用 null 而不是 Vector2.ZERO 表示"没传"——否则掉落点正好在世界原点时会被误判成默认点。
func drop_loot(at: Variant = null) -> void:
	if drop_table == null:
		return
	var pos: Vector2 = drop_marker.global_position if drop_marker != null else global_position
	if at is Vector2:
		pos = at
	DropSpawner.spawn_table(drop_table, pos, drop_scatter)


#region 阶段推进
# 机制在基类，策略在子类：基类只管"什么时候问一次"和"阶段的通用状态"，
# 具体有几个阶段、跨哪条线、进什么演出，全部写在各 BOSS 自己的脚本里（_check_phase_policy）。
# 不做成阈值表 / Resource 的原因：阶段只有 2~4 个，而每个阶段往往不只是"切个状态"
# （换 BGM、刷小怪、改属性……），数据表表达不了，最后还是要回来改代码。


## 当前血量比例（0~1）。阶段判断用它，比 int(max_health * ratio) 直白，也没有截断歧义。
func health_ratio() -> float:
	return float(health) / float(max_health) if max_health > 0 else 0.0


## 检查是否该推进阶段。由 take_damage() 在"真掉血且没被打死"后自动调用；
## BossState._check_phase() 也留了一份，方便任何招式在收招时手动问一次。
func check_phase() -> void:
	if dead or max_health <= 0:
		return
	_check_phase_policy()


## 阶段策略：子类重写。想写几个阶段就写几个 if，想做什么都可以
## （切状态、换 BGM、刷小怪、改 contact_damage……），基类不预设表达形式。
## 约定：推进阶段时调 start_phase(i) —— 它会更新 phase_index 并广播 phase_changed。
func _check_phase_policy() -> void:
	pass


## 扣血入口：先走基类结算（受击特效 / 掉血 / 硬直 / 死亡），
## 再在"真的掉了血且没被打死"时推进阶段。
## 被无敌帧 / 过场锁血挡下的攻击 health 不变，因此不会误推进阶段演出。
func take_damage(amount: int, from: Node2D = null) -> void:
	var before := health
	super.take_damage(amount, from)
	if health < before and not dead:
		check_phase()


#endregion


#region 场地查询（竞技场 / 地面 / 落点 / 水平 AoE）
# 这一组只依赖"碰撞胶囊 + 物理射线 + 玩家位置"，与具体 BOSS 的美术、招式无关，
# 任何 BOSS（瞬移、跃击、地刺、范围预警）都要用，故沉淀在这里。

@export_group("场地查询")
## 竞技场节点名：先在本 BOSS 的子节点里找，找不到再到父节点（关卡场景）下找。
## 留默认值即兼容"竞技场挂在 BOSS 下"与"竞技场与 BOSS 平级"两种布局。
@export var arena_path: NodePath = ^"BossArena"
## 地面 / 悬崖探测的射线来源节点：找落点与"脚下有没有地"共用它的 collision_mask。
## 场景里没有该节点时退回固定 mask = 4（地形层）。
@export var ground_probe_path: NodePath = ^"LedgeDetector"

## 悬崖 / 地面探测器实例（场景里没有则为 null）。只在 _ready 解析一次，
## 几何（水平偏移 + 向下长度）直接取场景里摆好的值，代码里不抄常量。
@onready var ground_probe: RayCast2D = get_node_or_null(ground_probe_path) as RayCast2D

var _arena_zone: AuZone = null


## 竞技场实例（AuZone）。解析顺序：自身子节点 → 父节点下同名节点。
## 结果缓存；实例被销毁后下次调用自动重新解析。
func arena_zone() -> AuZone:
	if _arena_zone != null and is_instance_valid(_arena_zone):
		return _arena_zone
	_arena_zone = get_node_or_null(arena_path) as AuZone
	if _arena_zone == null and get_parent() != null:
		_arena_zone = get_parent().get_node_or_null(arena_path) as AuZone
	return _arena_zone


## 竞技场的世界矩形；未绑定 / 无 global_rect() 时返回空 Rect2。
## 调用方用 size.x > 0 判断"有没有竞技场"，不要把空矩形当成有效范围。
func arena_rect() -> Rect2:
	var zone := arena_zone()
	if zone != null and zone.has_method("global_rect"):
		return zone.global_rect()
	return Rect2()


## 身体原点允许的最高 y（头顶刚好贴住领地上沿）；没有领地时返回 NAN。
## 瞬移到空中 / 跃击时拿它做下限，BOSS 就不会跑到屏幕上方的天花板外侧。
func arena_ceiling_y() -> float:
	var arena := arena_rect()
	if arena.size.y <= 0.0:
		return NAN
	return minf(arena.position.y + body_bottom(), arena.end.y - body_bottom())


## 把「身体原点」坐标裁进竞技场（按碰撞体尺寸内缩）：瞬移 / 闪现落点共用，
## 保证 BOSS 整个身体留在领地内，不会瞬到墙外或领地上方的装饰平台上。
## 没有领地时原样返回，兼容旧关卡布局。
func clamp_position_to_arena(pos: Vector2) -> Vector2:
	var arena := arena_rect()
	if arena.size.x <= 0.0 or arena.size.y <= 0.0:
		return pos
	var lo_x := arena.position.x + body_half_width()
	var hi_x := arena.end.x - body_half_width()
	var lo_y := arena.position.y + body_bottom()
	var hi_y := arena.end.y - body_bottom()
	var x := clampf(pos.x, lo_x, hi_x) if lo_x <= hi_x else arena.get_center().x
	var y := clampf(pos.y, lo_y, hi_y) if lo_y <= hi_y else arena.get_center().y
	return Vector2(x, y)


## 地形检测用的碰撞 mask（取探测器的 mask，缺省 4 = 地形层）。
func ground_mask() -> int:
	return ground_probe.collision_mask if ground_probe != null else 4


## move_x（±1）方向的前方有没有落脚点。返回 true = 有地，可以走 / 可以冲 / 可以退。
## 重写 Enemy 的默认实现（基类恒 true，供飞行 / 水下怪沿用）：地面 BOSS 的冲刺、后撤、
## 跃击都靠它避免冲出平台。
##
## 与"当前朝向"解耦 —— 只用传入的方向，探测器几何取 absf(position.x) 后按该方向镜像，
## 因此不需要像以前那样先把 RayCast2D 掰到目标方向再查询（evade 的 _aim_ledge_detector 就此消失）。
## 每次即时打射线而不是读 RayCast2D 的缓存：缓存是上一物理帧的结果，会在"翻面 / 换向"那一帧给错答案。
func has_ground_ahead(move_x: float) -> bool:
	if is_zero_approx(move_x) or not is_on_floor():
		return true  # 空中不做悬崖限制
	var offset := _probe_offset()
	var from := global_position + Vector2(offset.x * signf(move_x), offset.y)
	var to := from + Vector2(0.0, _probe_length())
	var space := get_world_2d().direct_space_state
	if space == null:
		return true
	var query := PhysicsRayQueryParameters2D.create(from, to)
	query.collision_mask = ground_mask()
	query.exclude = [get_rid()]
	return not space.intersect_ray(query).is_empty()


## 探测器的水平偏移（取绝对值，方向由调用方给）与向下长度，沿用场景里 LedgeDetector 的摆位。
func _probe_offset() -> Vector2:
	if ground_probe == null:
		return Vector2(19.0, 3.0)
	return Vector2(absf(ground_probe.position.x), ground_probe.position.y)


func _probe_length() -> float:
	if ground_probe == null:
		return 15.0
	var length := ground_probe.target_position.length()
	return length if length > 0.0 else 15.0


## x 处地面顶部的 y（向下打一条长射线）。
## 没有地面时返回 fallback：默认 NAN，便于调用方用 is_nan() 区分"悬崖"与"合法落点"；
## 只想兜底不区分时传自己的 y 即可。
##
## 有领地时射线区间以领地为准：从领地上沿向下扫到领地底边之外。旧写法
## 「自身 y - 800 → 自身 y + 1200」有两个坑：头顶上方的天花板 / 装饰平台会被当成
## 脚下地面（grimm_gent 的 Platform_05 顶面 y=-10，会把瞬移落点算到 y≈-387，
## BOSS 飞出屏幕并卡在天花板上）；BOSS 一旦已经跑到高处，射线又够不到真正的地面，
## 错误位置会被后续招式一直放大。
func ground_y_at(x: float, fallback: float = NAN) -> float:
	var space := get_world_2d().direct_space_state
	if space == null:
		return fallback
	var from_y := global_position.y - 800.0
	var to_y := global_position.y + 1200.0
	var arena := arena_rect()
	if arena.size.y > 0.0:
		from_y = arena.position.y + 1.0
		to_y = arena.end.y + 200.0
	var from := Vector2(x, from_y)
	var to := Vector2(x, to_y)
	var query := PhysicsRayQueryParameters2D.create(from, to)
	query.collision_mask = ground_mask()
	query.exclude = [get_rid()]
	var res := space.intersect_ray(query)
	if res.is_empty():
		return fallback
	return float(res.position.y)


## 以 center_x 为圆心、radius 为水平半径，对玩家结算一次伤害（垂直方向不判，2D 平台惯例）。
## 命中返回 true。来源统一传 self，供玩家格挡 / 受击特效识别。
func damage_in_radius(center_x: float, radius: float, damage: int) -> bool:
	var p := get_player()
	if p == null or not p.has_method("take_damage"):
		return false
	if absf(p.global_position.x - center_x) > radius:
		return false
	p.take_damage(damage, self)
	return true


## 在 target_x 两侧挑一个"脚下有地、身体不卡墙"的落点（瞬移 / 闪现 / 召回共用）。
## 顺序：先在 near_dist 处试右左两侧，再退到 max_dist 处试左右；全部非法返回 Vector2.ZERO。
## 返回的是"身体原点"坐标（已按碰撞胶囊高度把脚贴到地面）。
func find_ground_position_near(target_x: float, near_dist: float, max_dist: float) -> Vector2:
	var space := get_world_2d().direct_space_state
	if space == null:
		return Vector2.ZERO
	var feet := feet_offset()
	var arena := arena_rect()
	var has_arena := arena.size.x > 0.0 and arena.size.y > 0.0
	# 候选（横距, 左右）：从近到远、左右交替。
	var candidates: Array[Vector2] = [
		Vector2(near_dist, 1.0),
		Vector2(near_dist, -1.0),
		Vector2(max_dist, 1.0),
		Vector2(max_dist, -1.0),
	]
	for cand_off in candidates:
		var cand_x := target_x + cand_off.x * cand_off.y
		if has_arena:
			# 别把候选点挑到领地外的墙里 / 悬崖外。
			cand_x = clampf(cand_x,
					arena.position.x + body_half_width(), arena.end.x - body_half_width())
		var ground_y := ground_y_at(cand_x)
		if is_nan(ground_y):
			continue  # 悬崖：脚下没地，跳过
		var cand := Vector2(cand_x, ground_y - feet)
		if has_arena:
			# 最后一道保险：落点整体裁进领地，绝不落到领地上方的平台上。
			cand = clamp_position_to_arena(cand)
		if blocked_by_wall(cand):
			continue  # 卡墙：跳过
		return cand
	return Vector2.ZERO


## 候选落点身体中段高度左右各打一条短水平射线，命中地形即视为卡墙。
## 取中段高度（避开脚下地面），避免"贴地"被误判成卡墙。
func blocked_by_wall(cand: Vector2) -> bool:
	var space := get_world_2d().direct_space_state
	if space == null:
		return false
	var mask := ground_mask()
	var probe_y := cand.y - feet_offset() * 0.5
	for dir in [-1.0, 1.0]:
		var from := Vector2(cand.x, probe_y)
		var to := Vector2(cand.x + dir * (body_half_width() + 8.0), probe_y)
		var query := PhysicsRayQueryParameters2D.create(from, to)
		query.collision_mask = mask
		query.exclude = [get_rid()]
		if not space.intersect_ray(query).is_empty():
			return true
	return false


## 碰撞胶囊底部相对身体原点的偏移（把脚贴到地面用）。非胶囊形状返回 0。
func feet_offset() -> float:
	var shape_node := collision_shape
	if shape_node != null and shape_node.shape is CapsuleShape2D:
		var cap := shape_node.shape as CapsuleShape2D
		return cap.height * 0.5 + cap.radius + shape_node.position.y
	return 0.0


## 碰撞形状底部相对身体原点的偏移（脚底距离）。落点 / 贴地 / 悬崖判定都按它算。
## 支持圆 / 胶囊 / 矩形三种，其它形状退回碰撞形状自身的 y 偏移。
## 与 feet_offset() 的分工：那个是"把胶囊贴到地面"的旧接口（非胶囊返回 0），
## 本函数对所有形状都给真实脚底距离，新代码一律用它。
func body_bottom() -> float:
	var shape_node := collision_shape
	if shape_node == null or shape_node.shape == null:
		return 0.0
	var shape := shape_node.shape
	if shape is CircleShape2D:
		return (shape as CircleShape2D).radius + shape_node.position.y
	if shape is CapsuleShape2D:
		var cap := shape as CapsuleShape2D
		return cap.height * 0.5 + cap.radius + shape_node.position.y
	if shape is RectangleShape2D:
		return (shape as RectangleShape2D).size.y * 0.5 + shape_node.position.y
	return shape_node.position.y


## 碰撞形状的水平半宽：圆 / 胶囊取半径，矩形取半宽；其它形状返回 100 兜底。
## 只有准确知道身体有多宽，墙 / 悬崖的预判射线才能从身体前缘外扩
## （SoulMaster 是半径 142 的圆，退回 100 会让悬崖判晚 42px）。
func body_half_width() -> float:
	var shape_node := collision_shape
	if shape_node == null or shape_node.shape == null:
		return 100.0
	var shape := shape_node.shape
	if shape is CircleShape2D:
		return (shape as CircleShape2D).radius
	if shape is CapsuleShape2D:
		return (shape as CapsuleShape2D).radius
	if shape is RectangleShape2D:
		return (shape as RectangleShape2D).size.x * 0.5
	return 100.0


#endregion


#region 通用工具（位置瞬变 / 落点 / 特效）
# 与上面的场地查询同属"只依赖碰撞体 + 物理射线 + 玩家位置"的无状态操作，
# 任何 BOSS 的瞬移、跃击、下砸、召唤特效都用得上，故沉淀在基类。


## 位置瞬变：归零速度 + 重置自身及所有 Node2D 子节点的物理插值。
## 项目 physics_interpolation=true，父节点 reset 不会递归到子节点，
## 精灵 / 碰撞形状 / 命中盒 / 音效播放器都要各自重置，否则首帧会从旧位置滑过来。
## face_player=true 时顺带看向玩家（瞬移后接施法 / 劈砍的常用收尾）。
func teleport_to(pos: Vector2, face_player: bool = false) -> void:
	global_position = pos
	velocity = Vector2.ZERO
	reset_physics_interpolation()
	for node in find_children("*", "", true, false):
		if node is Node2D:
			(node as Node2D).reset_physics_interpolation()
	if face_player:
		var p := get_player()
		if p != null:
			face_toward(p.global_position.x)


## 该 x 处"身体原点贴地"的 y：地面顶部往上让出整个身体高度。
## 无地面时退回竞技场底边，连领地都没有则返回 NAN，交给调用方的兜底时长。
func ground_position_at(x: float) -> float:
	var ground := ground_y_at(x, NAN)
	if not is_nan(ground):
		return ground - body_bottom()
	var arena := arena_rect()
	if arena.size.y > 0.0:
		return arena.end.y - body_bottom()
	return NAN


## dir(±1) 方向、身体前缘外扩 margin 处是否撞到地形墙。
## 只探地形层（与落点查询同一个 mask），玩家不在其中，不会把玩家算成墙。
## 不叫 wall_ahead()：Enemy 已有同名无参虚方法（按当前朝向查 WallDetector），
## GDScript 不允许同名不同签名覆盖，故本方法按"传入方向"另起一名。
func wall_in_direction(dir: float, margin: float = 0.0) -> bool:
	var space := get_world_2d().direct_space_state
	if space == null:
		return false
	var from := global_position
	var to := from + Vector2(dir * (body_half_width() + margin), 0.0)
	var query := PhysicsRayQueryParameters2D.create(from, to)
	query.collision_mask = ground_mask()
	query.exclude = [get_rid()]
	return not space.intersect_ray(query).is_empty()


## dir 方向、身体前缘外扩 margin 处是否踏空 / 落差超过 drop_tolerance。
## 脚下本来就没地面（无地形场景）时不做悬崖判定，交给墙 / 距离 / 兜底时长收招。
func ledge_ahead(dir: float, margin: float = 0.0, drop_tolerance: float = 80.0) -> bool:
	var here := ground_y_at(global_position.x, NAN)
	if is_nan(here):
		return false
	var probe_x := global_position.x + dir * (body_half_width() + margin)
	var ahead := ground_y_at(probe_x, NAN)
	if is_nan(ahead):
		return true
	return ahead - here > drop_tolerance


## 生成一个挂在 BOSS 父节点上的特效：同层 z 偏移、摆位、重置插值。
## 挂父节点而不是 BOSS 身上：BOSS 会瞬移 / 翻面 / 淡出，特效不该跟着被搬走或继承 modulate。
## 返回实例，调用方在 add_child 之后再做配置与启动（如 wave.launch() / orb.summon()）。
func spawn_attached_fx(scene: PackedScene, pos: Vector2, z_offset: int = 1) -> Node2D:
	var parent := get_parent()
	if parent == null or scene == null:
		return null
	var fx := scene.instantiate() as Node2D
	if fx == null:
		return null
	fx.z_as_relative = z_as_relative
	fx.z_index = z_index + z_offset
	parent.add_child(fx)
	fx.global_position = pos
	fx.reset_physics_interpolation()
	return fx
#endregion
