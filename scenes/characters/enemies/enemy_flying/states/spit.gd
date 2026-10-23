extends EnemyFlyingState
class_name EnemySpitState


## 吐息后的后摇（秒）：期间停在 spit 状态，结束后切回 chase 并重新开始计冷却。
@export var spit_recover: float = 0.2

var _recover := 0.0

func enter(_from: StringName) -> void:
	enemy.launch_projectile()
	_play_audio(&"attack")
	_recover = 0.0
	_spit_timer = 0.0

func update(delta: float) -> void:
	_recover += delta
	super.update(delta)

func get_transition(_delta: float) -> StringName:
	if _recover >= spit_recover:
		return EnemyStateNames.CHASE
	return &""
