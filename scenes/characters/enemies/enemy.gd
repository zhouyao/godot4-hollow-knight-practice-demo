extends CharacterBody2D
class_name Enemy

## 敌人基类：只提供通用能力（重力 / 朝向 / 攻击区 / 受击 / 死亡 / 目标感知）。
## 具体 AI（patrol / chase / attack / hurt）由子类在子场景里补状态节点后继承。
## 基类自带 idle + death 两个状态，所以拖进关卡能站住、能被打死，不会报 warning。

signal enemy_death
signal damaged(amount: int, from: Node2D)

# ---- 数值：子类在检查器里覆盖 ----
@export var max_health: int = 100
## 初始血量（导出，检查器覆盖）。出生时 health = initial_health，可小于 max_health（例如残血出场）
@export var initial_health: int = 3
## 与玩家同一套重力手感：2 * 3 * UNIT_SIZE / 0.5²
@export var gravity: float = 2304.0
## 受击后的无敌帧时长，由 HitTimer 计时
@export var invincible_time: float = 0.3
## 攻击区命中玩家时造成的伤害（子类实现了 attack 状态才用得上）。
## 接触伤害小怪（区域常开）与近战挥击小怪（动画开关键帧）共用这一个值。
@export var contact_damage: int = 1
## 接触 / 近战命中玩家的冷却，与玩家自身无敌帧互补，避免每帧狂掉血
@export var contact_cooldown: float = 0.8
## 接触伤害总开关：玩家贴到这只怪身上（AttackArea 常开）是否掉血。
## false = 纯远程 / 装饰物 / 教学中立怪：碰到不掉血。
## 只作用于"接触"这条路径；投射物伤害、本体受击与死亡完全不受影响。
## 近战挥击态将来请用 try_hit_player(false)，绕过本开关。
@export var contact_damage_enabled: bool = true
## 吐东西小怪用的投射物场景（在检查器里指认 projectile.tscn；不填则 launch_projectile 无效）
@export var projectile_scene: PackedScene = null
## 投射物命中玩家造成的伤害
@export var projectile_damage: int = 1

## 不导出：要跟随 Globals.UNIT_SIZE 变化，导出项的默认值拿不到 autoload
var move_speed: float = 1.0 * Globals.UNIT_SIZE
## 是否吃重力。true = 地面怪（默认）；false = 飞行怪，垂直方向由悬停 / 追踪逻辑接管
@export var gravity_enabled: bool = true
## 悬停时的上下浮动幅度（像素）。0 = 不浮动，静止悬停在基准高度
@export var hover_amplitude: float = 0.0
## 悬停浮动频率（次 / 秒）
@export var hover_frequency: float = 0.35
## 追击时是否走 NavigationAgent2D 的路径（需要关卡里挂了 NavigationRegion2D）。
## 没有导航图 / 目标不在图上 / 地图还没完成首次同步时会自动退回直线，不会站着不动。
@export var use_navigation: bool = false

# ---- 活动范围（Leash）----
## NavigationRegion2D 只是寻路数据、不含碰撞，挡不住飞行怪。想要"守住自己的地盘"
## 就得显式配一圈活动范围：AI 取用的目标点会先被 clamp_to_leash() 夹进这个矩形，
## 玩家跑到框外时敌人贴着边界停下继续攻击，而不是一路追出去。
## 每只怪在检查器里单独配，默认关闭 = 维持原行为（可以无限追）。
@export var leash_enabled: bool = false
## 活动区域尺寸（像素，全宽 × 全高），以「出生点 + leash_offset」为中心向两侧各取一半
@export var leash_size: Vector2 = Vector2(400.0, 300.0)
## 活动区域中心相对出生点的偏移
@export var leash_offset: Vector2 = Vector2.ZERO

## 目标击飞力（Game Feel 调参）：仅水平方向命中时把敌人明显推离攻击区。
## 来自正上 / 正下的攻击（上挑、下劈）不触发怪物击退，保持上下攻击干净手感。
@export var target_knockback_x: float = 3500.0

var health: int
var move_direction: int = 1
var knockback: Vector2 = Vector2.ZERO
var dead: bool = false
var invincible: bool = false

## 侦测到的目标（玩家）。子类的 chase / attack 状态直接读它，不必自己连线。
var target: Node2D = null

# ---- 悬停：仅飞行怪（gravity_enabled = false 且 hover_amplitude > 0）使用 ----
var _hover_base_y: float = NAN
var _hover_time: float = 0.0

## 出生点（世界坐标）：活动区域的锚点，也是"放弃追击后回巢"的落点
var spawn_position: Vector2 = Vector2.ZERO
## 世界坐标下的活动区域矩形，_ready() 时按出生点算一次
var leash_rect: Rect2 = Rect2()

# ---- 节点引用：命名与 enemy.tscn 严格对应 ----
@onready var collision_shape: CollisionShape2D = $CollisionShape2D
@onready var attack_area: Area2D = $AttackArea
@onready var player_detection_area: Area2D = $PlayerDetectionArea
@onready var wall_detector: RayCast2D = $WallDetector
@onready var ledge_detector: RayCast2D = $LedgeDetector
@onready var muzzle: Marker2D = $Muzzle
@onready var drop_marker: Marker2D = $DropMarker

@onready var hit_timer: Timer = $Timer/HitTimer
@onready var contact_timer: Timer = $Timer/ContactTimer

@onready var animated_sprite: AnimatedSprite2D = $Animation/EnemyAnimatedSprite
@onready var action_animation_player: AnimationPlayer = $Animation/ActionAnimationPlayer

@onready var debug: CharacterDebug = $Debug
@onready var state_machine: StateMachine = $StateMachine
@onready var navigation_agent: NavigationAgent2D = $NavigationAgent2D

var audio_nodes: Dictionary = {}

func _ready() -> void:
	for child in $Audio.get_children():
		audio_nodes[child.name] = child

	health = mini(initial_health, max_health)
	debug.setup_health(max_health, health)
	# 记录出生点与出生高度：进树时 position 已由场景/关卡写入，这里取到的是最终位置
	spawn_position = global_position
	_hover_base_y = global_position.y
	leash_rect = _make_leash_rect(spawn_position)

	if attack_area != null:
		attack_area.monitoring = contact_damage_enabled
	_set_contact_area_shapes_enabled(contact_damage_enabled)

	if state_machine != null:
		state_machine.start()

# ---- 物理：与玩家同构，子类状态直接调用 ----
func _apply_gravity(delta: float) -> void:
	if not gravity_enabled or is_on_floor():
		return
	velocity.y += gravity * delta

## 垂直运动总入口：状态层一律调它，不必关心宿主是地面怪还是飞行怪。
## 地面怪吃重力；飞行怪围绕悬停基准高度做正弦浮动（hover_amplitude = 0 则原地悬停）。
func _apply_vertical_motion(delta: float) -> void:
	if gravity_enabled:
		_apply_gravity(delta)
	elif hover_amplitude > 0.0:
		_apply_hover(delta)

## 悬停：每帧把速度直接解到「目标高度 - 当前高度」，相比逐帧积分不会产生累积漂移；
## 命中地形时由 move_and_slide 自然挡住。
func _apply_hover(delta: float) -> void:
	if is_nan(_hover_base_y):
		_hover_base_y = global_position.y
	_hover_time += delta
	var target_y := _hover_base_y + sin(_hover_time * TAU * hover_frequency) * hover_amplitude
	velocity.y = (target_y - global_position.y) / maxf(delta, 0.0001)

## 飞行怪专用：把悬停基准高度朝 target_y 逼近（每帧最多 max_step 像素，避免瞬移）。
## 浮动的正弦量叠加在基准之上，所以追踪过程中上下摆动的观感不变。
func move_hover_base_to(target_y: float, max_step: float) -> void:
	if is_nan(_hover_base_y):
		_hover_base_y = global_position.y
	_hover_base_y = move_toward(_hover_base_y, target_y, max_step)

## 以出生点（+ leash_offset）为中心，按 leash_size 算出活动区域
func _make_leash_rect(spawn_pos: Vector2) -> Rect2:
	var center := spawn_pos + leash_offset
	return Rect2(center - leash_size * 0.5, leash_size)

## 把一个世界坐标夹进活动区域（逐轴独立，框外的点会被压到最近的边界上）。
## 未启用 / 尺寸非正时原样返回，等价于"没有活动范围"。
## 被夹住的点可以直接当追击目标用：敌人靠近它就等于"停在边界上"。
func clamp_to_leash(world_pos: Vector2) -> Vector2:
	if not leash_enabled or leash_size.x <= 0.0 or leash_size.y <= 0.0:
		return world_pos
	return Vector2(
		clampf(world_pos.x, leash_rect.position.x, leash_rect.position.x + leash_rect.size.x),
		clampf(world_pos.y, leash_rect.position.y, leash_rect.position.y + leash_rect.size.y)
	)

## 追击状态时每帧问一次「下一步该往哪走」，返回应当接近的世界坐标。
##
## 三种情况会退回直线，避免出现"接了寻路却没有导航图 → 原地漂浮"：
## 1) 关卡没有 NavigationRegion2D，或目标落在图外 → is_target_reachable() 为 false；
## 2) 地图还没完成首次同步（头几帧）→ get_next_path_position() 返回代理自身位置；
## 3) 压根没开启 use_navigation。
func get_navigation_step(target_pos: Vector2) -> Vector2:
	if not use_navigation or navigation_agent == null:
		return target_pos
	navigation_agent.target_position = target_pos
	if not navigation_agent.is_target_reachable():
		return target_pos
	var next := navigation_agent.get_next_path_position()
	if next.distance_to(global_position) < 1.0:
		return target_pos
	return next

func _apply_movement() -> void:
	velocity += knockback
	knockback = lerp(knockback, Vector2.ZERO, 0.4)
	move_and_slide()

# ---- 朝向 ----
func _flip_direction() -> void:
	move_direction *= -1
	for flipped in [animated_sprite, attack_area]:
		flipped.scale.x *= -1
		flipped.reset_physics_interpolation()
	for detector in [wall_detector, ledge_detector]:
		detector.target_position.x *= -1
		detector.reset_physics_interpolation()
	for marker in [muzzle, drop_marker]:
		marker.position.x *= -1
		marker.reset_physics_interpolation()

# ---- 受击 / 死亡 ----
func take_damage(amount: int, from: Node2D = null) -> void:
	if dead or invincible:
		return
	health -= amount
	_refresh_health_bar()
	damaged.emit(amount, from)
	
	if from != null:
		var to_self := global_position - from.global_position
		if abs(to_self.x) >= abs(to_self.y):
			var kx := target_knockback_x if to_self.x >= 0.0 else -target_knockback_x
			knockback = Vector2(kx, 0.0)

	if is_instance_valid(animated_sprite):
		animated_sprite.modulate = Color(4.0, 4.0, 4.0)
		var flash_tween := animated_sprite.create_tween()
		flash_tween.tween_property(animated_sprite, "modulate", Color.WHITE, invincible_time)
	if health <= 0:
		_dead()
		return
	invincible = true
	hit_timer.start(invincible_time)

## 扣血后刷新血条数值、颜色与文字
func _refresh_health_bar() -> void:
	debug.set_health(health, max_health)

## 由 death 动画末尾的 method track 调用（与玩家 death 动画的 _dead() 同构）
func _dead() -> void:
	if dead:
		return
	dead = true
	enemy_death.emit()

func kill() -> void:
	if not dead:
		_dead()

# ---- 信号回调 ----
func _on_hit_timer_timeout() -> void:
	invincible = false

func _on_player_detection_area_body_entered(body: Node2D) -> void:
	target = body

func _on_player_detection_area_body_exited(body: Node2D) -> void:
	if target == body:
		target = null

## ---- 对玩家造成伤害（统一出口）----
func try_hit_player(from_contact: bool = true) -> bool:
	if dead or contact_timer.time_left > 0.0:
		return false
	# 接触路径受开关控制；主动攻击绕过本开关
	if from_contact and not contact_damage_enabled:
		return false
	var p := get_player()
	if p == null or not p.has_method("take_damage"):
		return false
	# 仅当攻击区确实与玩家重叠时才结算：接触小怪区域常开、近战小怪由动画开关键帧
	if attack_area == null or not attack_area.overlaps_body(p):
		return false
	p.take_damage(contact_damage, self)
	contact_timer.start(contact_cooldown)
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

func launch_projectile(scene: PackedScene = null) -> void:
	var proj := scene if scene != null else projectile_scene
	if proj == null:
		return
	var p := proj.instantiate()
	# 先进树再 setup / 定位：树外写 global_position 拿不到父级变换，
	# 且 setup() 里的计时器要求节点已在树内
	get_tree().current_scene.add_child(p)
	p.global_position = muzzle.global_position
	var dir := Vector2(move_direction, 0.0)
	if is_instance_valid(target):
		dir = (target.global_position - muzzle.global_position).normalized()
	p.setup(dir, projectile_damage)
