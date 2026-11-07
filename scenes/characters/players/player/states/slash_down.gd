extends PlayerState


## 进攻型状态：供 Boss 全局攻击标志识别（玩家正在攻击 = true）。
## 父类 PlayerState 已声明 is_attack（默认 false），这里在 _init 里改默认值为 true。
func _init() -> void:
	is_attack = true

@export_group("行为 Behavior")
## 下劈动作的最短持续时间（秒）：期间不接受过渡，保证俯冲到落地这段不被打断。
@export var hold_time: float = 0.3

@export_group("状态过渡 Transitions")
## 下劈落地后切往的状态（一般是 land）。
@export var target_grounded: StringName = PlayerStateNames.LAND

func enter(_from: StringName) -> void:
	# 本次挥砍的命中登记表清零（同一次下劈内可连砍多个目标，但每个目标只吃一次）。
	player.begin_attack()
	player.velocity.y = maxf(player.velocity.y, player.slash_down_dive_speed)
	_play_audio(PlayerStateNames.SLASH_DOWN)
	_play_action(PlayerStateNames.SLASH_DOWN)

func exit(_to: StringName) -> void:
	player.end_attack()

func on_attack_pressed() -> void:
	# 一次下劈 = 一次完整挥砍：动作期间不允许强制重入本状态。
	# 旧实现里连点攻击会不断重置 elapsed、重播动画、把命中登记表清空，
	# 使同一个目标被反复当成"首次命中"，进而反复触发下劈反弹（凭空无限抬升）。
	# 想连续 pogo，等本次挥砍结束后从 jump / fall 重新起手即可，且仍须真正砍中硬物。
	pass

func get_transition(_delta: float) -> StringName:
	if elapsed <= hold_time:
		return &""
	return target_grounded if player.is_on_floor() else airborne_transition()
