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
	# 按住 ↑ + 攻击：地面 / 空中都直接上劈，不需要先进入 look_up 抬头姿态
	if Input.is_action_pressed(&"up"):
		machine.set_state(PlayerStateNames.SLASH_UP, true)
		return
	# 地面按 ↓ + 攻击仍是平砍；只有空中按住 ↓ + 攻击才进下劈（force 允许连续踩踏重入）
	if not player.is_on_floor() and Input.is_action_pressed(&"down"):
		machine.set_state(PlayerStateNames.SLASH_DOWN, true)
		return
	machine.set_state(PlayerStateNames.SLASH_FORWARD)

func _play_action(name: StringName) -> void:
	player.action_animation_player.play(name)


func airborne_transition() -> StringName:
	return PlayerStateNames.JUMP if player.velocity.y < 0.0 else PlayerStateNames.FALL
