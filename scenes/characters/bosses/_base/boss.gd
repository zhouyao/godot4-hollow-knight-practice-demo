class_name Boss
extends Enemy


## 击败演出开始时发出（BOSS 专有）。
## 与 Enemy.enemy_death 的分工：enemy_death 负责"状态机转 defeat"，
## 本信号负责对外（存档标记 / 解锁 / 转场）。
signal boss_defeated
## 阶段切换时发出，参数为新阶段的索引（0 起）。
signal phase_changed(phase_index: int)

## 当前阶段索引，0 起。
var phase_index: int = 0

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


func _ready() -> void:
	super._ready()

## 每帧把命中盒镜像到当前朝向，确保 boss 转向时 MeleeHitBox 跟着转（根节点子节点不随精灵翻面）。
func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	_sync_melee_hitbox_facing()


## 翻面扩展点（与 Enemy._flip_extra 构成多态链）：Boss 专有的、需要跟随朝向翻转的节点
## 挂在这里。默认仅 super 回 Enemy，保留 muzzle（吐弹口）翻转；子类（如 BossHollowKnight）
## 重写本方法时务必 super._flip_extra()，否则会断掉 muzzle 的翻转。
func _flip_extra() -> void:
	super._flip_extra()


## 驻留状态：BOSS 不巡逻，沉睡 / 待机即 dormant。
## EnemyAggro.tick_zone_aggro() 会拿它比对当前状态；BOSS 没绑领地时那条路径本就不生效，
## 这里给出正确值是为了将来"用领地触发开战"时语义一致。
func resting_state() -> StringName:
	return BossStateNames.DORMANT


## 开战入口：由 BossArena 在玩家踏入时调用，或由入场动画的方法轨道在演出结束时调用。
## 走 Enemy 现成的仇恨广播（enter_combat_zone → _set_combat → enter_combat 信号），
## 关卡侧监听 enter_combat 即可切 BGM / 锁门 / 亮血条 —— 与领地开战是同一条路径。
func begin_fight() -> void:
	if dead or combat_active:
		return
	enter_combat_zone()


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


## BOSS 不做尸体淡出。
## _dead() 里的 _start_corpse_fade() 会在 corpse_lifetime 秒后把节点 queue_free 掉，
## 那会打断击败演出（动画没播完、信号没发完）。演出与清理全部交给 defeat 状态。
func _start_corpse_fade() -> void:
	pass
