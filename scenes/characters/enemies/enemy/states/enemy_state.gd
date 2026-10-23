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

	enemy.try_hit_player()

func _play_action(anim_name: StringName) -> void:
	enemy.action_animation_player.play(anim_name)

func _play_audio(key: StringName) -> void:
	if enemy == null:
		return
	var stream := enemy.audio_nodes.get(key) as AudioStreamPlayer2D
	if stream != null and stream.stream != null:
		stream.play()

func _flash_white(duration: float = -1.0) -> void:
	if enemy == null or not is_instance_valid(enemy.animated_sprite):
		return
	var d := enemy.invincible_time if duration <= 0.0 else duration
	enemy.animated_sprite.modulate = Color(4.0, 4.0, 4.0)
	var tween := enemy.animated_sprite.create_tween()
	tween.tween_property(enemy.animated_sprite, "modulate", Color.WHITE, d)

func _face_x(world_x: float) -> void:
	var desired := 1 if world_x >= enemy.global_position.x else -1
	if desired != enemy.move_direction:
		enemy._flip_direction()

func _move_toward(goal: Vector2, speed_multiplier: float = 1.0) -> void:
	var step := enemy.get_navigation_step(goal)
	if absf(step.x - enemy.global_position.x) <= 1.0:
		enemy.velocity.x = 0.0
		return
	_face_x(step.x)
	enemy.velocity.x = float(enemy.move_direction) * enemy.move_speed * speed_multiplier
