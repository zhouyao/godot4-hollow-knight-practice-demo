extends CharacterBody2D
class_name Enemy

## 敌人基类：只提供通用能力（重力 / 朝向 / 攻击区 / 受击 / 死亡 / 目标感知）。
## 具体 AI（patrol / chase / attack / hurt）由子类在子场景里补状态节点后继承。
## 基类自带 idle + death 两个状态，所以拖进关卡能站住、能被打死，不会报 warning。

signal enemy_death
signal damaged(amount: int, from: Node2D)

# ---- 数值：子类在检查器里覆盖 ----
@export var max_health: int = 3
## 与玩家同一套重力手感：2 * 3 * UNIT_SIZE / 0.5²
@export var gravity: float = 2304.0
## 受击后的无敌帧时长，由 HitTimer 计时
@export var invincible_time: float = 0.3
## 攻击区命中玩家时造成的伤害（子类实现了 attack 状态才用得上）
@export var contact_damage: int = 1

## 不导出：要跟随 Globals.UNIT_SIZE 变化，导出项的默认值拿不到 autoload
var move_speed: float = 1.0 * Globals.UNIT_SIZE
## 受击击退强度。实际位移约为 force/24（衰减系数 0.4 下的等比级数求和），
## 想调手感就改这里，不必动衰减系数。
var knockback_force: float = 8.0 * Globals.UNIT_SIZE

var health: int
var move_direction: int = 1
var knockback: Vector2 = Vector2.ZERO
var dead: bool = false
var invincible: bool = false

## 侦测到的目标（玩家）。子类的 chase / attack 状态直接读它，不必自己连线。
var target: Node2D = null

# ---- 节点引用：命名与 enemy.tscn 严格对应 ----
@onready var collision_shape: CollisionShape2D = $CollisionShape2D
@onready var attack_area: Area2D = $AttackArea
@onready var player_detection_area: Area2D = $PlayerDetectionArea
@onready var wall_detector: RayCast2D = $WallDetector
@onready var ledge_detector: RayCast2D = $LedgeDetector
@onready var muzzle: Marker2D = $Muzzle
@onready var drop_marker: Marker2D = $DropMarker

@onready var hit_timer: Timer = $Timer/HitTimer

@onready var animated_sprite: AnimatedSprite2D = $Animation/EnemyAnimatedSprite
@onready var action_animation_player: AnimationPlayer = $Animation/ActionAnimationPlayer

@onready var state_label: Label = $Debug/MarginContainer/StateName
@onready var state_machine: StateMachine = $StateMachine

var audio_nodes: Dictionary = {}

func _ready() -> void:
	for child in $Audio.get_children():
		audio_nodes[child.name] = child
	health = max_health
	# 放在最后：此时本节点的 @onready 成员已就绪，状态机进入初始状态是安全的
	if state_machine != null:
		state_machine.start()

# ---- 物理：与玩家同构，子类状态直接调用 ----
func _apply_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y += gravity * delta

## 击退走独立通道：用 move_and_collide 单独做位移，它不碰 velocity，
## 所以击退分量不会混进 velocity.y 的重力积分里、逐帧叠加成加速
## （直接 velocity += knockback 会让上挑把敌人越顶越快）。
## 位移 = knockback * delta，配合 0.4 的衰减系数，总位移约为 knockback_force/24。
func _apply_movement() -> void:
	if not knockback.is_zero_approx():
		move_and_collide(knockback * get_physics_process_delta_time())
		knockback = lerp(knockback, Vector2.ZERO, 0.4)
	move_and_slide()

# ---- 朝向 ----
## 翻转朝向：精灵与攻击区用 scale.x 镜像；射线翻 target_position.x；锚点翻 position.x。
## 每个改完都要 reset_physics_interpolation()——项目开启了 physics_interpolation，
## 不调用会在翻转瞬间拖一帧残影。
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
	damaged.emit(amount, from)
	# 击退方向按攻击来源位置推算：下方上挑会把敌人往上顶，空中下劈把它砸下去，
	# 平砍则是水平推开。放在敌人侧算，将来投射物 / 爆炸也能复用同一套。
	if from != null:
		knockback = (global_position - from.global_position).normalized() * knockback_force
	if health <= 0:
		_dead()
		return
	invincible = true
	hit_timer.start(invincible_time)

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

## 攻击区由子类 attack 动画的关键帧开关；基类没有 attack 状态，这里只留空钩子，
## 子类在自己的场景里把信号改连到自己的处理函数。
func _on_attack_area_body_entered(_body: Node2D) -> void:
	pass
