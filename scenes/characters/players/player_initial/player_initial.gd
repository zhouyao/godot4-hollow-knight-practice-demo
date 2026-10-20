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

var knockback: Vector2 = Vector2.ZERO

var dead: bool = false

## 相机跟随锚点：只提供位置，真正的相机决策全在 AuCameraDirector
@onready var camera_marker: Marker2D = $CameraPosition

@onready var collision_shape = $CollisionShape2D
@onready var enemy_detection_area = $EnemyDetectionArea
@onready var front_attack_area = $FrontAttackArea

@onready var look_up_timer: Timer = $Timer/LookUpTimer
@onready var look_down_timer: Timer = $Timer/LookDownTimer
@onready var hit_timer: Timer = $Timer/HitTimer

@onready var player_animated_sprite: AnimatedSprite2D = $Animation/PlayerAnimatedSprite
@onready var action_animation_player = $Animation/ActionAnimationPlayer
@onready var secondary_animation_player = $Animation/SecondaryAnimationPlayer

@onready var state_label: Label = $Visual/MarginContainer/Label

@onready var state_machine: StateMachine = $StateMachine

var audio_nodes: Dictionary = {}

func _ready() -> void:
	for child in $Audio.get_children():
		audio_nodes[child.name] = child

	gravity = 2.0 * max_jump_height / pow(jump_duration, 2)
	max_jump_velocity = -sqrt(2.0 * gravity * max_jump_height)
	min_jump_velocity = -sqrt(2.0 * gravity * min_jump_height)
	dash_speed = dash_distance / dash_duration

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
	for flipped in [player_animated_sprite, collision_shape,enemy_detection_area, front_attack_area]:
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
		
# ---- 攻击 / 受击判定（占位）----
# 四个 Area 默认 disabled；等攻击状态接入后，由 ActionAnimationPlayer 在挥砍帧
# 打开对应判定区、动画结束帧再关闭。

func _on_front_attack_area_body_entered(_body: Node2D) -> void:
	pass


func _on_up_attack_area_body_entered(_body: Node2D) -> void:
	pass


func _on_down_attack_area_body_entered(_body: Node2D) -> void:
	pass


func _on_enemy_detection_area_body_entered(_body: Node2D) -> void:
	pass


## 视野上下偏移：按住 up / down 超过 LookUpTimer.wait_time 才生效，松开立即归位。
## 这里只上报意图，具体怎么偏移由 AuCameraDirector 决定（还要看当前区域是否允许）。
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"up"):
		look_up_timer.start()
	elif event.is_action_released(&"up"):
		look_up_timer.stop()
		_reset_look()
	elif event.is_action_pressed(&"down"):
		look_down_timer.start()
	elif event.is_action_released(&"down"):
		look_down_timer.stop()
		_reset_look()


func _on_look_up_timer_timeout() -> void:
	AuCameraDirector.look_up()


func _on_look_down_timer_timeout() -> void:
	AuCameraDirector.look_down()


func _reset_look() -> void:
	AuCameraDirector.clear_look()
