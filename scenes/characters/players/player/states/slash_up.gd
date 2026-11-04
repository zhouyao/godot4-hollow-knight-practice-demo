extends PlayerState


## 进攻型状态：供 Boss 全局攻击标志识别（玩家正在攻击 = true）。
## 父类 PlayerState 已声明 is_attack（默认 false），这里在 _init 里改默认值为 true。
func _init() -> void:
	is_attack = true

@export_group("行为 Behavior")
## 上挑动作的最短持续时间（秒）：期间不接受过渡，保证挥砍不被打断。
@export var hold_time: float = 0.3

@export_group("状态过渡 Transitions")
## 动作结束时已松开上键，切往的状态（一般是 idle）。
@export var target_next: StringName = PlayerStateNames.IDLE

## 动作结束时仍按住上键，切往的状态（一般是 look_up），用来衔接连续上挑。
@export var target_hold_up: StringName = PlayerStateNames.LOOK_UP

func enter(_from: StringName) -> void:
	# 本次挥砍的命中登记表清零：之后每个目标各结算一次，多个目标可穿透。
	player.begin_attack()
	_play_audio(PlayerStateNames.SLASH_UP)
	_play_action(PlayerStateNames.SLASH_UP)

func exit(_to: StringName) -> void:
	player.end_attack()

func on_attack_pressed() -> void:
	pass

func get_transition(_delta: float) -> StringName:
	if elapsed <= hold_time:
		return &""
	if not player.is_on_floor():
		return airborne_transition()
	return target_hold_up if Input.is_action_pressed(&"up") else target_next
