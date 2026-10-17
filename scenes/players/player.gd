extends CharacterBody2D

# 极简可玩占位玩家（侧视平台版）。
# 受重力、贴地站立；左右移动，上/W 或 空格 跳跃，下落中按 下 快速下落。
# 自带 Camera2D 跟随，并加入 "player" 组供 Door 识别。

const SPEED := 220.0
const JUMP_VELOCITY := -420.0
var _gravity: float = 980.0


func _ready() -> void:
	_gravity = ProjectSettings.get_setting("physics/2d/default_gravity", 980.0)
	add_to_group("player")


func _physics_process(delta: float) -> void:
	# 重力
	if not is_on_floor():
		velocity.y += _gravity * delta

	# 左右移动
	var dir := Input.get_axis("left", "right")
	velocity.x = dir * SPEED

	# 跳跃：上(W) 或 空格
	if (Input.is_action_just_pressed("jump") or Input.is_action_just_pressed("up")) and is_on_floor():
		velocity.y = JUMP_VELOCITY

	# 下落中按 下 快速下落
	if Input.is_action_pressed("down") and not is_on_floor():
		velocity.y += _gravity * 1.5 * delta

	move_and_slide()
