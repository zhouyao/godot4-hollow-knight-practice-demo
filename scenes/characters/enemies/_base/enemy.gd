extends CharacterBody2D
class_name Enemy


## 死亡瞬间发出一次（血量归零或被 kill() 调用），状态机据此切到 death 状态。
signal enemy_death
## 每次成功结算伤害后发出（无敌帧内的伤害不会触发）。
## 参数 amount：本次扣掉的血量；from：伤害来源节点，陷阱等无来源时为 null。
signal damaged(amount: int, from: Node2D)
## 进入战斗（开战）时发出；参数 target：仇恨目标节点。
signal enter_combat(target: Node2D)
## 离开战斗（丢失 / 回归）时发出。
signal leave_combat

## _validate_property() 用的"隐藏但仍序列化"标记：等价于 @export_storage，
## 保证被隐藏的参数值依然写进 .tscn，不会因为切换配置而丢失。
const HIDDEN_BUT_SAVED := PROPERTY_USAGE_NO_EDITOR | PROPERTY_USAGE_STORAGE

# 检查器分组：导出项按主题折叠，配合 _validate_property() 只显示当前这只怪用得上的参数。
@export_group("生命")
## 最大血量，同时也是血条上限。子类在检查器里覆盖即可。
@export var max_health: int = 100
## 初始血量：出生时取 min(initial_health, max_health)，可用于让敌人残血出场。
@export var initial_health: int = 3

@export_group("物理")
## 是否吃重力：true = 地面怪（默认）；false = 飞行怪，垂直方向由状态逻辑直接驱动。
@export var gravity_enabled: bool = true
## 重力加速度（像素 / 秒²），默认与玩家手感一致（2 * 3 * UNIT_SIZE / 0.5²）。
## gravity_enabled = false 时本项自动隐藏。
@export var gravity: float = 2304.0

@export_group("受击")
## 受击后的无敌帧时长（秒），由 HitTimer 计时，期间不再结算伤害。
@export var invincible_time: float = 0.3

@export_group("接触伤害")
## 接触伤害总开关：false 时贴身不掉血（纯远程怪 / 中立怪 / 装饰物）。
## 只作用于"接触"这一条路径，投射物伤害与自身受击死亡不受影响。
@export var contact_damage_enabled: bool = true
## 贴身接触或近战命中玩家时造成的伤害值。
@export var contact_damage: int = 1
## 两次伤害玩家之间的冷却（秒），避免贴身时逐帧掉血；由 ContactTimer 计时。
@export var contact_cooldown: float = 0.8


## 出生点：用于 return 状态归位与 leash 范围判定，_ready 时记录。
var spawn_position: Vector2 = Vector2.ZERO

@export_group("感知与仇恨")
## 牵引（leash）半径：目标离开出生点此距离即视为"追丢"，触发 return。
@export var leash_range: float = 700.0
## 丢失目标后多久放弃战斗（秒），用于距离/视线丢失的宽限时间。
@export var combat_lose_time: float = 10.0
## 视线丢失判定开关：true 时超出 leash 且无视线会累计丢失时间。
@export var use_line_of_sight: bool = true
## 是否允许追击（被控制效果禁用时置 false）。
@export var can_chase: bool = true
## 绑定的领地（EnemyZone）：玩家踏入该领地时令本敌人开战。
## 留空则不通过领地触发（仍可由受击开战）。在检查器里从世界的 EnemyZones 选择对应领地。
@export var enemy_zone: NodePath = NodePath()

@export_group("攻击")
## 吐出的投射物场景：留空 = 纯近战怪，launch_projectile() 直接返回，不会报错。
## 飞行怪与陆地怪共用：配上即拥有吐弹能力，attack 状态自动切到远程分支。
## 本项始终可见，且决定下面攻击相关项的显隐（见 _validate_property）。
## 值必须是 Ammo 子类的场景，换场景即换弹幕，用于做怪物个性化弹药：
##   res://scenes/projectiles/projectile.tscn        单发直射弹（默认）
##   res://scenes/projectiles/projectile_spread.tscn 散射弹：一发吐出 N 颗扇形散开
##   res://scenes/projectiles/projectile_split.tscn  延迟分裂弹：母弹先飞，到点炸成 N 颗
## 弹药可自行声明只允许某些阵营装配（见 Ammo.usable_by），越权时本函数会拒绝发射。
@export var projectile_scene: PackedScene = null
## 地面近战攻击距离（像素）：与目标距离小于该值即切到 attack 状态。
## 纯近战怪（未配 projectile_scene）用它；配了 projectile_scene 改用下面的 shoot_range，本项自动隐藏。
@export var attack_range: float = 64.0
## 投射物携带的伤害值（setup() 时传给投射物，与 contact_damage 相互独立）。
@export var projectile_damage: int = 1
## 远程射程（像素）：与目标直线距离小于该值才切到 attack 吐弹。< 0 表示沿用 chase 状态自身的默认值。
@export var shoot_range: float = -1.0
## 两次远程攻击之间的冷却（秒）：< 0 表示沿用 chase 状态自身的默认值。
@export var attack_interval: float = -1.0
## 远程追击时与目标保持的水平距离（像素）：< 0 表示沿用 chase 状态自身的默认值；0 = 贴脸。
@export var shoot_keep_distance: float = -1.0

@export_group("掉落")
## 死亡时掷的掉落表：留空则不掉落。建议做成 .tres 在多只怪之间复用。
@export var drop_table: DropTable = null
## 掉落物相对 DropMarker 的散布半径（像素）：多个掉落物时铺开一点。
@export var drop_scatter: float = 28.0

@export_group("死亡")
## 尸体保留时长（秒）：死亡后停留这么久才开始淡出。<= 0 表示尸体不消失，永久留在场上。
@export var corpse_lifetime: float = 3.0
## 尸体淡出时长（秒）：从完全不透明渐变到透明的耗时。<= 0 表示到点直接消失，不做渐变。
@export var corpse_fade_time: float = 1.0

## 战斗丢失计时器：累计"目标丢失 / 出 leash / 无视线"的时长，达到 combat_lose_time 即丢战。
var combat_timer: float = 0.0
## 当前是否处于战斗（仇恨）状态。
var combat_active: bool = false


var move_speed: float = 1.0 * Globals.UNIT_SIZE

var health: int
var move_direction: int = 1
var knockback: Vector2 = Vector2.ZERO
var dead: bool = false
var invincible: bool = false

var target: Node2D = null
var last_damage_from: Node2D = null

@onready var collision_shape: CollisionShape2D = $CollisionShape2D
@onready var attack_area: Area2D = $AttackArea
@onready var drop_marker: Marker2D = $DropMarker
## 吐弹口：没有该子节点（纯近战怪）时为 null，发射时退化为自身中心。
@onready var muzzle := get_node_or_null("Muzzle") as Marker2D

@onready var hit_timer: Timer = $Timer/HitTimer
@onready var contact_timer: Timer = $Timer/ContactTimer

@onready var animated_sprite: AnimatedSprite2D = $Animation/EnemyAnimatedSprite
@onready var action_animation_player: AnimationPlayer = $Animation/ActionAnimationPlayer

@onready var debug: CharacterDebug = $Debug
@onready var state_machine: StateMachine = $StateMachine

## 寻路节点：飞行怪与陆地怪的追击都统一由此承接，绕开障碍/地形。
@onready var navigation_agent: NavigationAgent2D = $NavigationAgent2D

## 抵达导航目标的判定距离（像素）：小于该值视为已到达并停止移动。
## 导航内部参数，默认值已够用，故不在检查器显示；确需调整时直接改 .tscn 即可。
@export_storage var nav_arrive_distance: float = 4.0

var audio_nodes: Dictionary = {}

func _ready() -> void:
	for child in $Audio.get_children():
		audio_nodes[child.name] = child

	health = mini(initial_health, max_health)
	debug.setup_health(max_health, health)

	spawn_position = global_position
	if not enemy_zone.is_empty():
		var zone := get_node_or_null(enemy_zone)
		if zone != null and zone.has_signal("player_entered") \
				and not zone.player_entered.is_connected(_on_zone_player_entered):
			zone.player_entered.connect(_on_zone_player_entered)

	if contact_timer != null:
		contact_timer.wait_time = contact_cooldown

	if attack_area != null:
		attack_area.monitoring = contact_damage_enabled
	_set_contact_area_shapes_enabled(contact_damage_enabled)

	if state_machine != null:
		state_machine.start()


func _apply_gravity(delta: float) -> void:
	if not gravity_enabled or is_on_floor():
		return
	velocity.y += gravity * delta

func _apply_vertical_motion(delta: float) -> void:
	if gravity_enabled:
		_apply_gravity(delta)


func _apply_movement() -> void:
	velocity += knockback
	knockback = lerp(knockback, Vector2.ZERO, 0.4)
	move_and_slide()


func _flip_direction() -> void:
	move_direction *= -1
	for flipped in [animated_sprite, attack_area]:
		flipped.scale.x *= -1
		flipped.reset_physics_interpolation()
	for marker in [drop_marker]:
		marker.position.x *= -1
		marker.reset_physics_interpolation()
	_flip_extra()

func _flip_extra() -> void:
	# 吐弹口跟着朝向翻转（无 Muzzle 的怪为 null，直接跳过）。
	if muzzle != null:
		muzzle.position.x *= -1
		muzzle.reset_physics_interpolation()


func take_damage(amount: int, from: Node2D = null) -> void:
	if dead or invincible:
		return
	health -= amount
	_refresh_health_bar()
	damaged.emit(amount, from)
	last_damage_from = from
	# 开战钩子：受击即拉仇恨（target 取玩家，fallback 用伤害来源）。
	_set_combat(true)

	if health <= 0:
		_dead()
		return
	if state_machine != null and state_machine.states.has(EnemyStateNames.HURT):
		state_machine.set_state(EnemyStateNames.HURT, true)
		return
	invincible = true
	hit_timer.start(invincible_time)

func _refresh_health_bar() -> void:
	debug.set_health(health, max_health)

func _dead() -> void:
	if dead:
		return
	dead = true
	_drop_loot()
	enemy_death.emit()
	_start_corpse_fade()

## 死亡后尸体的淡出清理：先停留 corpse_lifetime 秒，再用 corpse_fade_time 秒淡出并移除节点。
## 淡出改的是根节点 modulate，会沿画布层级传递给所有子节点（精灵、血条等）一起消失。
## 物理体保留到最后一刻，因此尸体在淡出期间仍可被踩踏/遮挡；如需立即不挡路，把 corpse_lifetime 调小。
func _start_corpse_fade() -> void:
	if corpse_lifetime <= 0.0:
		return
	var tween := create_tween()
	tween.tween_interval(corpse_lifetime)
	if corpse_fade_time > 0.0:
		tween.tween_property(self, "modulate:a", 0.0, corpse_fade_time)
	tween.tween_callback(queue_free)

## 死亡掉落：位置取 DropMarker（已随朝向翻转），交给 DropSpawner 统一生成。
## 生成放在 _dead() 而非 take_damage()，因此死亡动画播完（0.5s 方法轨道）才爆物品。
func _drop_loot() -> void:
	if drop_table == null:
		return
	var at := drop_marker.global_position if drop_marker != null else global_position
	DropSpawner.spawn_table(drop_table, at, drop_scatter)

func kill() -> void:
	if not dead:
		_dead()

func _on_hit_timer_timeout() -> void:
	invincible = false

## 玩家是否在视线内（无遮挡）。use_line_of_sight=false 时恒为 true。
func has_line_of_sight() -> bool:
	if not use_line_of_sight:
		return true
	var p := get_player()
	if p == null:
		return false
	var space := get_world_2d().direct_space_state
	var query := PhysicsRayQueryParameters2D.create(global_position, p.global_position)
	query.collision_mask = collision_mask
	query.exclude = [self.get_rid()]
	var result := space.intersect_ray(query)
	if result.is_empty():
		return true
	return result.get("collider", null) == p


## 目标是否仍在牵引范围内（出生点 leash_range 内）。未开战时视为在范围内。
func is_within_leash() -> bool:
	if not combat_active:
		return true
	var p := get_player()
	if p == null:
		return false
	return spawn_position.distance_to(p.global_position) <= leash_range


## 推进战斗丢失计时：目标丢失 / 出 leash / 无视线时累计，达到宽限时间则丢战。
func tick_combat(delta: float) -> void:
	if not combat_active:
		return
	var p := get_player()
	var lost := false
	if p == null:
		lost = true
	elif not is_within_leash():
		lost = true
	elif use_line_of_sight and not has_line_of_sight():
		lost = true
	if lost:
		combat_timer += delta
	else:
		combat_timer = 0.0
	if combat_timer >= combat_lose_time:
		_set_combat(false)


## 设置战斗（仇恨）状态并广播信号。开战时记录目标、清零丢失计时。
func _set_combat(active: bool) -> void:
	if combat_active == active:
		return
	combat_active = active
	combat_timer = 0.0
	if active:
		var p := get_player()
		if p != null:
			target = p
		enter_combat.emit(target)
	else:
		leave_combat.emit()

## 领地（EnemyZone）进入回调：玩家踏入本敌人绑定的领地时开战。
func _on_zone_player_entered(_zone: Node, _player: Node2D) -> void:
	enter_combat_zone()

## 由领地（EnemyZone）调用：令本敌人开战（受击开战仍由 take_damage 负责）。
func enter_combat_zone() -> void:
	if dead:
		return
	_set_combat(true)

## 用 NavigationAgent2D 计算朝 target_pos 的本帧期望速度，由追击状态调用并写回 enemy.velocity。
## speed：期望移动速度（像素/秒）。
## planar_only=true 时只保留水平分量（陆地怪仅沿 x 轴移动，垂直交给重力）。
## 已抵达终点时返回零向量；若导航网格缺失/未烘焙，agent 会原地返回，此时退化为直线趋近，保证仍可移动。
func nav_velocity(target_pos: Vector2, speed: float, planar_only: bool = false) -> Vector2:
	if navigation_agent == null:
		return Vector2.ZERO
	if global_position.distance_to(target_pos) <= nav_arrive_distance:
		return Vector2.ZERO
	navigation_agent.target_position = target_pos
	var next_pos := navigation_agent.get_next_path_position()
	# 导航网格不可用时 agent 返回自身位置，退化为直接朝目标移动。
	if next_pos.is_equal_approx(global_position):
		next_pos = target_pos
	var dir := global_position.direction_to(next_pos)
	if planar_only:
		dir.y = 0.0
		if dir.x == 0.0:
			return Vector2.ZERO
		dir = Vector2(signf(dir.x), 0.0)
	return dir * speed

func try_hit_player(from_contact: bool = true) -> bool:
	if dead or contact_timer.time_left > 0.0:
		return false
	if from_contact and not contact_damage_enabled:
		return false
	var p := get_player()
	if p == null or not p.has_method("take_damage"):
		return false
	if attack_area == null or not attack_area.overlaps_body(p):
		return false
	p.take_damage(contact_damage, self)
	contact_timer.start()
	return true

func set_contact_damage_enabled(enabled: bool) -> void:
	contact_damage_enabled = enabled
	if attack_area != null:
		attack_area.monitoring = enabled
	_set_contact_area_shapes_enabled(enabled)

func _set_contact_area_shapes_enabled(enabled: bool) -> void:
	if attack_area == null:
		return
	for child in attack_area.get_children():
		if child is CollisionShape2D:
			if enabled:
				child.position = Vector2.ZERO
			child.set_deferred("disabled", not enabled)

func get_player() -> Node2D:
	if is_instance_valid(target) and target.has_method("take_damage"):
		return target
	var players := get_tree().get_nodes_in_group("player")
	if players.is_empty():
		return null
	return players[0] as Node2D

## 吐弹（远程攻击）：从 muzzle（无则自身中心）朝目标发射一枚投射物。
## 未配置 projectile_scene 时直接返回 —— 纯近战怪的 attack 状态可无条件调用。
func launch_projectile(scene: PackedScene = null) -> void:
	var proj := scene if scene != null else projectile_scene
	if proj == null or not proj.can_instantiate():
		push_warning("%s: projectile_scene 无效或为空，跳过吐弹" % name)
		return
	var p := proj.instantiate()
	if p == null:
		push_warning("%s: 投射物实例化失败" % name)
		return
	# 统一弹药接口：根节点必须是 Ammo 子类（Projectile / ProjectileSpread / ProjectileSplit）。
	if not (p is Ammo):
		push_warning("%s: 投射物根节点不是 Ammo（缺少 fire()），已丢弃" % name)
		p.free()
		return
	# 权限校验：弹药可用 Ammo.usable_by 声明"只允许玩家装配"这类限制。
	if not p.can_be_used_by(Ammo.Faction.ENEMY):
		push_warning("%s: %s 不允许 ENEMY 阵营使用，已丢弃" % [name, proj.resource_path])
		p.free()
		return
	# 阵营由发射方写入：必须在 add_child 之前，弹药入树时才会套用正确的碰撞掩码。
	p.faction = Ammo.Faction.ENEMY
	get_tree().current_scene.add_child(p)
	var origin := muzzle.global_position if muzzle != null else global_position
	p.global_position = origin
	var dir := Vector2(move_direction, 0.0)
	var t := get_player()
	if is_instance_valid(t):
		dir = (t.global_position - origin).normalized()
	p.fire(dir, projectile_damage)

## 是否配置了远程吐弹能力：attack / chase 据此分流远程与近战两套节奏。
func has_projectile() -> bool:
	return projectile_scene != null and projectile_scene.can_instantiate()


## 检查器减负：按当前配置隐藏用不上的导出项，只影响编辑器显示，不改变数值与序列化。
## 例：飞行怪 gravity_enabled=false → 隐藏 gravity；近战怪未配 projectile_scene → 隐藏全部远程项。
## 子类（EnemyFlying 等）若要追加规则，重写后先调用 super._validate_property(property)。
func _validate_property(property: Dictionary) -> void:
	match property.name:
		"gravity":
			if not gravity_enabled:
				property.usage = HIDDEN_BUT_SAVED
		"attack_range":
			# 远程怪看 shoot_range，只有纯近战怪才需要贴身距离。
			if projectile_scene != null:
				property.usage = HIDDEN_BUT_SAVED
		"projectile_damage", "shoot_range", "attack_interval", "shoot_keep_distance":
			if projectile_scene == null:
				property.usage = HIDDEN_BUT_SAVED
		"contact_damage", "contact_cooldown":
			if not contact_damage_enabled:
				property.usage = HIDDEN_BUT_SAVED
		"drop_scatter":
			if drop_table == null:
				property.usage = HIDDEN_BUT_SAVED
