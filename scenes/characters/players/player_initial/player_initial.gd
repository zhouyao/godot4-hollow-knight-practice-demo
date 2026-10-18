extends CharacterBody2D

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

var shake_fade: float
var camera_modifier: int
var current_shake_strength: float = 0.0
var camera_inital_offset: Vector2
var rng = RandomNumberGenerator.new()

var knockback: Vector2 = Vector2.ZERO

var dead: bool = false
var jumping: bool = false

@onready var look_up_timer: Timer = $Timers/LookUpTimer
@onready var look_down_timer: Timer = $Timers/LookDownTimer
@onready var hit_timer: Timer = $Timers/HitTimer

@onready var camera: Camera2D = $Visual/Camera2D
@onready var camera_marker: Marker2D = $CameraPosition

@onready var state_label: Label = $Visual/MarginContainer/Label

@onready var action_animation_player = $ActionAnimationPlayer
@onready var secondary_animation_player = $SecondaryAnimationPlayer

@onready var player_animated_sprite: AnimatedSprite2D = $Visual/PlayerAnimatedSprite

@onready var collision_shape = $CollisionShape2D
@onready var enemy_detection_area = $EnemyDetectionArea
@onready var front_attack_area = $FrontAttackArea

@onready var walk_audio = $Audio/Walk

func _ready() -> void:
	gravity = 2.0 * max_jump_height / pow(jump_duration, 2)
	max_jump_velocity = -sqrt(2.0 * gravity * max_jump_height)
	min_jump_velocity = -sqrt(2.0 * gravity * min_jump_height)
	dash_speed = dash_distance / dash_duration
	camera_inital_offset = camera.offset
	Globals.connect("camera_shake", apply_shake)


func _physics_process(delta: float) -> void:
	_update_camera_position()

func _process(delta):
	_update_camera_shake(delta)

func _apply_gravity(delta):
	if velocity.y < 2000:
		velocity.y += gravity * delta

func _apply_movement():
	if Globals.level_preparing:
		velocity.x = 0
	move_and_slide()
	knockback = lerp(knockback, Vector2.ZERO, 0.4)
	Globals.player_pos = global_position

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


func apply_shake(strength, new_shake_fade):
	current_shake_strength = strength
	shake_fade = new_shake_fade

func randomOffset() -> Vector2:
	return Vector2(rng.randf_range(-current_shake_strength, current_shake_strength), rng.randf_range(-current_shake_strength, current_shake_strength))

func _update_camera_shake(delta):
	if current_shake_strength > 0:
		current_shake_strength = lerp(current_shake_strength, 0.0, shake_fade * delta)
		camera.offset = camera_inital_offset + randomOffset()

func _update_camera_position():
	var cam_mod: float
	if Globals.look_ups.has(true) and camera_modifier < 0:
		cam_mod = camera_modifier
	elif Globals.look_downs.has(true) and camera_modifier > 0:
		cam_mod = camera_modifier
	
	if !Globals.vertical_locks.is_empty():
		camera.global_position.y = Globals.vertical_locks.back() + cam_mod
	else:
		camera.global_position.y = camera_marker.global_position.y + cam_mod
	
	if !Globals.horizontal_locks.is_empty():
		camera.global_position.x = Globals.horizontal_locks.back() + cam_mod
	else:
		camera.global_position.x = camera_marker.global_position.x


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
