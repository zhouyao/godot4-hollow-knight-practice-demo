extends State
class_name PlayerState


const ATTACK_ACTION: StringName = &"attack"

var _player: PlayerInitial

var player: PlayerInitial:
	get:
		if _player == null or not is_instance_valid(_player):
			_player = machine.host as PlayerInitial if machine != null else null
		return _player

func update(delta: float) -> void:
	player._handle_move_input()
	player._apply_gravity(delta)
	player._apply_movement()

func handle_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"jump") and player.is_on_floor():
		player.velocity.y = player.max_jump_velocity
	if event.is_action_released(&"jump") and player.velocity.y < player.min_jump_velocity:
		player.velocity.y = player.min_jump_velocity
	if event.is_action_pressed(ATTACK_ACTION):
		on_attack_pressed()

func on_attack_pressed() -> void:
	if machine == null:
		return
	if Input.is_action_pressed(&"up"):
		machine.set_state(PlayerStateNames.SLASH_UP, true)
		return
	if not player.is_on_floor() and Input.is_action_pressed(&"down"):
		machine.set_state(PlayerStateNames.SLASH_DOWN, true)
		return
	machine.set_state(PlayerStateNames.SLASH_FORWARD)

func _play_action(anim_name: StringName, custom_scale: float = 1.0) -> void:
	player.action_animation_player.play(anim_name, -1.0, custom_scale)

func _play_action_for(anim_name: StringName, duration: float) -> void:
	var ap: AnimationPlayer = player.action_animation_player
	if duration <= 0.0 or not ap.has_animation(anim_name):
		_play_action(anim_name)
		return
	var anim: Animation = ap.get_animation(anim_name)
	if anim == null or anim.length <= 0.0:
		_play_action(anim_name)
		return
	_play_action(anim_name, anim.length / duration)


func airborne_transition() -> StringName:
	return PlayerStateNames.JUMP if player.velocity.y < 0.0 else PlayerStateNames.FALL
