extends CharacterBody2D
class_name Enemy


## 死亡瞬间发出一次（血量归零或被 kill() 调用），状态机据此切到 death 状态。
signal enemy_death
## 每次成功结算伤害后发出（无敌帧内的伤害不会触发）。
## 参数 amount：本次扣掉的血量；from：伤害来源节点，陷阱等无来源时为 null。
signal damaged(amount: int, from: Node2D)

## 最大血量，同时也是血条上限。子类在检查器里覆盖即可。
@export var max_health: int = 100
## 初始血量：出生时取 min(initial_health, max_health)，可用于让敌人残血出场。
@export var initial_health: int = 3
## 重力加速度（像素 / 秒²），默认与玩家手感一致（2 * 3 * UNIT_SIZE / 0.5²）。
@export var gravity: float = 2304.0
## 受击后的无敌帧时长（秒），由 HitTimer 计时，期间不再结算伤害。
@export var invincible_time: float = 0.3
## 贴身接触或近战命中玩家时造成的伤害值。
@export var contact_damage: int = 1
## 两次伤害玩家之间的冷却（秒），避免贴身时逐帧掉血；由 ContactTimer 计时。
@export var contact_cooldown: float = 0.8
## 接触伤害总开关：false 时贴身不掉血（纯远程怪 / 中立怪 / 装饰物）。
## 只作用于"接触"这一条路径，投射物伤害与自身受击死亡不受影响。
@export var contact_damage_enabled: bool = true

var move_speed: float = 1.0 * Globals.UNIT_SIZE
## 是否吃重力：true = 地面怪（默认）；false = 飞行怪，垂直方向由状态逻辑直接驱动。
@export var gravity_enabled: bool = true
## 该敌人专属的导航区域：寻路在其多边形内进行，活动范围也取它的包围盒（回巢 / 脱战用）。
## 不配则退化为直线移动，且不做活动范围夹取。
## 注意：不同敌人引用的 region 必须占用不同的 navigation_layers 位，否则多个 agent 会互相串场。
@export var navigation_region: NavigationRegion2D = null

var health: int
var move_direction: int = 1
var knockback: Vector2 = Vector2.ZERO
var dead: bool = false
var invincible: bool = false

var target: Node2D = null
var last_damage_from: Node2D = null

var spawn_position: Vector2 = Vector2.ZERO
var activity_rect: Rect2 = Rect2()
var _territory_sensor: Area2D = null

@onready var collision_shape: CollisionShape2D = $CollisionShape2D
@onready var attack_area: Area2D = $AttackArea
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
	spawn_position = global_position

	if contact_timer != null:
		contact_timer.wait_time = contact_cooldown

	if attack_area != null:
		attack_area.monitoring = contact_damage_enabled
	_set_contact_area_shapes_enabled(contact_damage_enabled)

	_bind_navigation_region.call_deferred()

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


func _bind_navigation_region() -> void:
	if navigation_region == null or navigation_agent == null:
		return
	navigation_agent.navigation_layers = navigation_region.navigation_layers
	var poly: NavigationPolygon = navigation_region.navigation_polygon
	if poly == null:
		return
	var verts: PackedVector2Array = poly.get_vertices()
	if verts.is_empty():
		return
	var min_p := navigation_region.to_global(verts[0])
	var max_p := min_p
	for c in verts:
		var wp := navigation_region.to_global(c)
		min_p = min_p.min(wp)
		max_p = max_p.max(wp)
	activity_rect = Rect2(min_p, max_p - min_p)
	_territory_sensor = navigation_region.get_node_or_null("TerritorySensor")
	if _territory_sensor == null:
		_territory_sensor = Area2D.new()
		_territory_sensor.name = "TerritorySensor"
		_territory_sensor.collision_layer = 0
		_territory_sensor.collision_mask = 1
		navigation_region.add_child(_territory_sensor)
	var s_shape_node := _territory_sensor.get_node_or_null("CollisionShape2D")
	if s_shape_node == null:
		s_shape_node = CollisionShape2D.new()
		_territory_sensor.add_child(s_shape_node)
	if s_shape_node.shape == null or not (s_shape_node.shape is RectangleShape2D):
		s_shape_node.shape = RectangleShape2D.new()
	s_shape_node.shape.size = activity_rect.size
	s_shape_node.position = Vector2.ZERO
	_territory_sensor.global_position = activity_rect.get_center()
	if not _territory_sensor.body_entered.is_connected(_on_territory_body_entered):
		_territory_sensor.body_entered.connect(_on_territory_body_entered)
	if not _territory_sensor.body_exited.is_connected(_on_territory_body_exited):
		_territory_sensor.body_exited.connect(_on_territory_body_exited)

func clamp_to_activity(world_pos: Vector2) -> Vector2:
	if navigation_region == null or activity_rect.size.x <= 0.0 or activity_rect.size.y <= 0.0:
		return world_pos
	return Vector2(
		clampf(world_pos.x, activity_rect.position.x, activity_rect.position.x + activity_rect.size.x),
		clampf(world_pos.y, activity_rect.position.y, activity_rect.position.y + activity_rect.size.y)
	)


func get_navigation_step(target_pos: Vector2) -> Vector2:
	if navigation_region == null or navigation_agent == null:
		return target_pos
	var goal := clamp_to_activity(target_pos)
	navigation_agent.target_position = goal
	if not navigation_agent.is_target_reachable():
		return goal
	var next := navigation_agent.get_next_path_position()
	if next.distance_to(global_position) < 1.0:
		return goal
	return next


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
	pass


func take_damage(amount: int, from: Node2D = null) -> void:
	if dead or invincible:
		return
	health -= amount
	_refresh_health_bar()
	damaged.emit(amount, from)
	last_damage_from = from

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
	enemy_death.emit()

func kill() -> void:
	if not dead:
		_dead()


func _on_hit_timer_timeout() -> void:
	invincible = false

func _on_territory_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		target = body

func _on_territory_body_exited(body: Node2D) -> void:
	if body.is_in_group("player") and target == body:
		target = null


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


func launch_projectile(_scene: PackedScene = null) -> void:
	pass
