extends CharacterBody2D
class_name PlayerInitial

signal player_death

var speed: float = 4 * Globals.UNIT_SIZE
var min_jump_height: float = 0.2 * Globals.UNIT_SIZE
var max_jump_height: float = 3 * Globals.UNIT_SIZE
var min_jump_velocity: float
var max_jump_velocity: float
var jump_duration: float = 0.5
var gravity: float
var move_direction: int = 1

var dash_distance: float = 3.5 * Globals.UNIT_SIZE
var dash_duration: float = 0.2
var dash_speed: float

## 下劈命中敌人的反弹高度（在 _ready 里换算成向上初速度）
var slash_down_bounce_height: float = 1.5 * Globals.UNIT_SIZE
var slash_down_bounce_velocity: float
## 起手向下俯冲的速度：与当前下落速度取较大值，保证空中下劈有"砸下去"的手感
var slash_down_dive_speed: float = 5.0 * Globals.UNIT_SIZE

## 三段挥砍（前刺 / 上挑 / 下劈）共用的伤害值
@export var slash_damage: int = 1

var knockback: Vector2 = Vector2.ZERO

var dead: bool = false

## 相机跟随锚点：只提供位置，真正的相机决策全在 AuCameraDirector
@onready var camera_marker: Marker2D = $CameraPosition

@onready var collision_shape = $CollisionShape2D
@onready var enemy_detection_area = $EnemyDetectionArea
@onready var front_attack_area = $FrontAttackArea

@onready var hit_timer: Timer = $Timer/HitTimer

@onready var player_animated_sprite: AnimatedSprite2D = $Animation/PlayerAnimatedSprite
@onready var slash_forward_animated_sprite: AnimatedSprite2D = $Animation/SlashForwardAnimatedSprite

@onready var action_animation_player = $Animation/ActionAnimationPlayer
@onready var secondary_animation_player = $Animation/SecondaryAnimationPlayer

@onready var state_label: Label = $Debug/MarginContainer/StateName

@onready var state_machine: StateMachine = $StateMachine

var audio_nodes: Dictionary = {}

func _ready() -> void:
	for child in $Audio.get_children():
		audio_nodes[child.name] = child

	gravity = 2.0 * max_jump_height / pow(jump_duration, 2)
	max_jump_velocity = -sqrt(2.0 * gravity * max_jump_height)
	min_jump_velocity = -sqrt(2.0 * gravity * min_jump_height)
	dash_speed = dash_distance / dash_duration
	slash_down_bounce_velocity = -sqrt(2.0 * gravity * slash_down_bounce_height)

	# 自己上报相机跟随锚点：这样即使死亡重生（本节点被重建），相机也能重新挂上，
	# 不用依赖关卡脚本重新赋值。
	AuCameraDirector.set_follow(camera_marker)

	# 放在最后：此时本节点的 @onready 成员已就绪，状态机进入初始状态是安全的
	if state_machine != null:
		state_machine.start()


func _apply_gravity(delta):
	if velocity.y < 2000:
		velocity.y += gravity * delta

func _apply_movement():
	move_and_slide()
	knockback = lerp(knockback, Vector2.ZERO, 0.4)

func _flip_direction():
	for flipped in [player_animated_sprite,slash_forward_animated_sprite,front_attack_area]:
		flipped.scale.x *= -1
		flipped.reset_physics_interpolation()

	camera_marker.position.x = -camera_marker.position.x
	camera_marker.reset_physics_interpolation()

func _handle_move_input():
	var direction = int(Input.get_axis("left", "right"))
	
	if direction != 0 and direction != move_direction:
		_flip_direction()
		move_direction = direction
	
	velocity.x = direction * speed
	velocity += knockback
	if(velocity.y < max_jump_velocity):
		velocity.y = max_jump_velocity


func _dead():
	if dead:
		return
	dead = true
	player_death.emit()

func kill():
	if(!dead):
		_dead()
		
# ---- 攻击 / 受击判定 ----
# 三个攻击判定区默认 disabled；由 ActionAnimationPlayer 在挥砍帧打开对应判定区、
# 动画结束帧再关闭。

func _on_front_attack_area_body_entered(body: Node2D) -> void:
	_hit_enemy(body)


func _on_up_attack_area_body_entered(body: Node2D) -> void:
	_hit_enemy(body)


func _on_down_attack_area_body_entered(body: Node2D) -> void:
# 	只有 slash_down 动画会打开该判定区
	if state_machine == null or state_machine.get_state_name() != PlayerStateNames.SLASH_DOWN:
		return
	# 只有怪物才结算伤害并弹起：劈到地面 / 道具什么都不做
	if not (body is Enemy):
		return
	_hit_enemy(body)
	velocity.y = slash_down_bounce_velocity

## 只对敌人结算伤害。击退方向交给敌人自己按攻击来源位置推算，
## 所以这里不用关心玩家朝哪个方位砍（前刺推开 / 上挑顶起 / 下劈砸下）。
func _hit_enemy(body: Node2D) -> void:
	if body is Enemy:
		body.take_damage(slash_damage, self)

func _on_enemy_detection_area_body_entered(_body: Node2D) -> void:
	pass
