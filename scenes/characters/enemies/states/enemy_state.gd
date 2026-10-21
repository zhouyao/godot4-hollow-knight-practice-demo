extends State
class_name EnemyState

## 敌人状态的类型化基类：与 PlayerState 同构，状态内可直接拿到强类型的 enemy，
## 不必每帧做 as 转换。

var _enemy: Enemy

var enemy: Enemy:
	get:
		if _enemy == null or not is_instance_valid(_enemy):
			_enemy = machine.host as Enemy if machine != null else null
		return _enemy

## 约定：每个状态都要在 update 里给 enemy.velocity.x 赋值——会移动的赋移动速度，
## 不移动的（如 idle）显式置 0，否则切状态时残余速度会让敌人继续滑行。
## 击退不走 velocity（见 Enemy._apply_movement），所以这里不需要处理击退。
func update(delta: float) -> void:
	enemy._apply_gravity(delta)
	enemy._apply_movement()

func _play_action(name: StringName) -> void:
	enemy.action_animation_player.play(name)

## 覆盖基类：敌人音频是占位节点（没填 stream），播放前先判空，避免空转报错
func _play_audio(key: StringName) -> void:
	if enemy == null:
		return
	var stream := enemy.audio_nodes.get(key) as AudioStreamPlayer2D
	if stream != null and stream.stream != null:
		stream.play()
