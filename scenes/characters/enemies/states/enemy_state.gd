extends State
class_name EnemyState

var _enemy: Enemy

var enemy: Enemy:
	get:
		if _enemy == null or not is_instance_valid(_enemy):
			_enemy = machine.host as Enemy if machine != null else null
		return _enemy

func update(delta: float) -> void:
	enemy._apply_vertical_motion(delta)
	enemy._apply_movement()
	
	if enemy.contact_damage_enabled:
		enemy.try_hit_player()

func _play_action(anim_name: StringName) -> void:
	enemy.action_animation_player.play(anim_name)

func _play_audio(key: StringName) -> void:
	if enemy == null:
		return
	var stream := enemy.audio_nodes.get(key) as AudioStreamPlayer2D
	if stream != null and stream.stream != null:
		stream.play()
