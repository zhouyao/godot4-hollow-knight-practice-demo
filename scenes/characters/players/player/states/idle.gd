extends PlayerState

const MOVE_EPS := 1.0

## 一旦开始移动就切到这个状态（可在检查器改指向 dash 等）
@export var target_move: StringName = PlayerStateNames.WALK

## 按住方向超过该时长才进入 look 状态；默认 0 表示按下即抬头 / 低头
## （相机侧自带平滑，轻触不会造成画面跳动；需要防误触时再调大，如 0.3）
@export var look_hold_time: float = 0.0

## 从按下方向累计的按住时长，松开即清零
var _look_hold: float = 0.0

func enter(_from: StringName) -> void:
	_look_hold = 0.0
	_play_action(PlayerStateNames.IDLE)

func get_transition(delta: float) -> StringName:
	if not player.is_on_floor():
		return airborne_transition()
	if absf(player.velocity.x) > MOVE_EPS:
		return target_move
	# 仅在 idle 按住 up / down 累计超过 look_hold_time 才进入 look 状态
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
