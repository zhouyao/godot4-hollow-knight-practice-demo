extends StateMachine

func _ready():
	add_state("idle")
	add_state("walk")
	add_state("jump")
	add_state("fall")
	add_state("dead")
	call_deferred("set_state", states.idle)
	
func _input(event):
	if Globals.level_preparing or parent.dead:
		return
		
	if [states.idle, states.walk].has(state) and parent.is_on_floor():
		if event.is_action_pressed("jump"):
			parent.velocity.y = parent.max_jump_velocity
			parent.jumping = true
	if event.is_action_released("jump") and parent.velocity.y < parent.min_jump_velocity:
		parent.velocity.y = parent.min_jump_velocity
		
		
func _state_logic(delta):
	parent.state_label.text = states.find_key(state)
	
	if state != states.dead:
		if !Globals.level_preparing:
			parent._handle_move_input()
			
		parent._apply_gravity(delta)
		parent._apply_movement()

func _get_transition(_delta):
	match state:
		states.idle:
			if parent.dead:
				return states.dead
			elif !parent.is_on_floor():
				if parent.velocity.y < 0:
					return states.jump
				elif parent.velocity.y > 0:
					return states.fall
			elif parent.velocity.x != 0:
				return states.walk
		states.walk:
			if parent.dead:
				return states.dead
			elif !parent.is_on_floor():
				if parent.velocity.y < 0:
					return states.jump
				elif parent.velocity.y > 0:
					return states.fall
			elif parent.velocity.x == 0:
				return states.idle
		states.jump:
			if parent.dead:
				return states.dead
			elif parent.is_on_floor():
				return states.idle
			elif parent.velocity.y >= 0:
				return states.fall
		states.fall:
			if parent.dead:
				return states.dead
			elif parent.is_on_floor():
				return states.idle
			elif parent.velocity.y < 0:
				return states.jump

func _enter_state(new_state, _old_state):
	match new_state:
		states.idle:
			parent.action_animation_player.play("idle")
		states.walk:
			parent.action_animation_player.play("walk")
			parent.walk_audio.play()
	
	
func _exit_state(old_state, new_state):
	parent.action_animation_player.stop()
	parent.walk_audio.stop()
