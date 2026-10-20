extends PlayerState

## 死亡态：不可逆。进入即冻结（置 machine.active=false），由 AnimationPlayer 自身播放死亡动画。

func enter(_from: StringName) -> void:
	_play_action(PlayerStateNames.DEATH)
	_play_audio(PlayerStateNames.DEATH)
	# 彻底冻结：关闭状态机调度（死亡动画不依赖 active，仍会播完）
	machine.active = false

func update(_delta: float) -> void:
	pass

func get_transition(_delta: float) -> StringName:
	return &""   # 死亡不可逆
