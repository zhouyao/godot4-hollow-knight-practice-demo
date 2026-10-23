extends PlayerState


## 进入低头状态后延迟多久才推动镜头（秒）：避免轻点一下方向键画面就晃。
@export var camera_look_delay: float = 1.0

func enter(_from: StringName) -> void:
	_play_action(PlayerStateNames.LOOK_DOWN)

func exit(_to: StringName) -> void:
	AuCameraDirector.clear_look()

func update(_delta: float) -> void:
	if elapsed >= camera_look_delay:
		AuCameraDirector.look_down()
	player._apply_gravity(_delta)
	player._apply_movement()

func get_transition(_delta: float) -> StringName:
	if not player.is_on_floor():
		return airborne_transition()
	if Input.is_action_pressed(&"left") or Input.is_action_pressed(&"right"):
		return PlayerStateNames.IDLE
	if Input.is_action_pressed(&"down"):
		return &""
	return PlayerStateNames.IDLE
