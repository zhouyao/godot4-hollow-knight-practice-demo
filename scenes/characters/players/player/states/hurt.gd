extends PlayerState


@export_group("行为 Behavior")
## 受击硬直时长（秒）。为 0 时自动取玩家的 invincible_time，让硬直与无敌帧等长。
@export var hold_time: float = 0.0

@export_group("状态过渡 Transitions")
## 硬直结束且已落地时切往的状态（一般是 idle）；还在空中则交给 airborne_transition()。
@export var target_grounded: StringName = PlayerStateNames.IDLE

func _get_hold_time() -> float:
	if hold_time > 0.0:
		return hold_time
	return player.invincible_time if player != null else 0.0

func enter(_from: StringName) -> void:
	_play_audio(PlayerStateNames.HURT)
	_play_action_for(PlayerStateNames.HURT, _get_hold_time())
	player.end_attack()
	player.velocity.x = 0.0

func update(delta: float) -> void:
	player.velocity.x = player.knockback.x
	player._apply_gravity(delta)
	player._apply_movement()

func handle_input(_event: InputEvent) -> void:
	pass

func get_transition(_delta: float) -> StringName:
	if elapsed <= _get_hold_time():
		return &""
	return airborne_transition() if not player.is_on_floor() else target_grounded
