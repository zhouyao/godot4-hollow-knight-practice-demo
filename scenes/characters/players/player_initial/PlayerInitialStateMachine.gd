extends StateMachine

enum State { IDLE, WALK, JUMP, FALL }

## 基类只把 parent 存成 Node，这里按需转成具体宿主
var player: PlayerInitial:
	get:
		return parent as PlayerInitial

func _ready() -> void:
	state_changed.connect(_on_state_changed)

	set_state.call_deferred(State.IDLE)

func _on_state_changed(new_state: int, _old_state: int) -> void:
	player.state_label.text = String(State.keys()[new_state])

func _handle_input(event: InputEvent) -> void:
	if event.is_action_pressed("jump") and (state == State.IDLE or state == State.WALK) and player.is_on_floor():
		player.velocity.y = player.max_jump_velocity
	elif event.is_action_released("jump") and player.velocity.y < player.min_jump_velocity:
		player.velocity.y = player.min_jump_velocity

func _state_logic(delta: float) -> void:
	player._handle_move_input()
	player._apply_gravity(delta)
	player._apply_movement()

func _get_transition(_delta: float) -> int:
	var on_floor := player.is_on_floor()
	match state:
		State.IDLE, State.WALK:
			if not on_floor:
				return State.JUMP if player.velocity.y < 0 else State.FALL
			return State.WALK if player.velocity.x != 0 else State.IDLE
		State.JUMP:
			if on_floor:
				return State.IDLE
			if player.velocity.y >= 0:
				return State.FALL
		State.FALL:
			if on_floor:
				return State.IDLE
			if player.velocity.y < 0:
				return State.JUMP
	return -1

func _enter_state(new_state: int, _old_state: int) -> void:
	match new_state:
		State.IDLE:
			player.action_animation_player.play("idle")
		State.WALK:
			player.action_animation_player.play("walk")
			player.walk_audio.play()
		State.JUMP:
			player.action_animation_player.play("jump")
			player.jump_audio.play()
		State.FALL:
			player.action_animation_player.play("fall")

func _exit_state(old_state: int, new_state: int) -> void:
	player.walk_audio.stop()
	player.jump_audio.stop()

	# 落地音
	if old_state == State.FALL and new_state == State.IDLE:
		player.land_audio.play()
