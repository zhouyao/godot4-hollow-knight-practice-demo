extends PlayerState


const MOVE_EPS := 1.0

## 检测到横向移动后切往的目标状态（一般是 walk）。
@export var target_move: StringName = PlayerStateNames.WALK

## 抬头 / 低头需要按住的时长（秒）：避免轻点一下方向键就切到 look 状态。设为 0 表示立即切换。
@export var look_hold_time: float = 0.0

var _look_hold: float = 0.0

func enter(_from: StringName) -> void:
	_look_hold = 0.0
	_play_action(PlayerStateNames.IDLE)

func get_transition(delta: float) -> StringName:
	if not player.is_on_floor():
		return airborne_transition()
	if absf(player.velocity.x) > MOVE_EPS:
		return target_move
	if Input.is_action_pressed(&"up") or Input.is_action_pressed(&"down"):
		_look_hold += delta
	else:
		_look_hold = 0.0
	if _look_hold > look_hold_time:
		if Input.is_action_pressed(&"up"):
			return PlayerStateNames.LOOK_UP
		if Input.is_action_pressed(&"down"):
			return PlayerStateNames.LOOK_DOWN
	return &""
