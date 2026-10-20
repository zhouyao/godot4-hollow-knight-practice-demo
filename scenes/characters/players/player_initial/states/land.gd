extends PlayerState

## 落地过渡态：播放 land 音效，短暂保持后回到 idle。
## 没有 land 专属动画，落地瞬间用 idle 姿态过渡。

## 落地保持时长（秒）；状态机自动维护 elapsed
@export var hold_time: float = 0.1

## 保持结束后的去向
@export var target_next: StringName = PlayerStateNames.IDLE

func enter(_from: StringName) -> void:
	_play_audio(PlayerStateNames.LAND)
	_play_action(PlayerStateNames.IDLE)

func get_transition(_delta: float) -> StringName:
	return target_next if elapsed > hold_time else &""
