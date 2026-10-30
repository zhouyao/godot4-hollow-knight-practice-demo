extends PlayerState


const STOP_EPS := 1.0

## 横向速度衰减到阈值以下时切往的目标状态（一般是 idle）。
@export var target_stop: StringName = PlayerStateNames.IDLE

## 脚步声间隔（秒）：跟随走路动画，每个循环左右脚各响一次。
## 设为 0（默认）则自动取走路动画时长的一半作为步点，无需手动配。
@export var step_interval: float = 0.0

var _step_timer: float = 0.0

func enter(_from: StringName) -> void:
	_play_default_step()
	_play_action(PlayerStateNames.WALK)
	_step_timer = 0.0
	if step_interval <= 0.0:
		var ap := player.action_animation_player
		if ap.has_animation(PlayerStateNames.WALK):
			step_interval = ap.get_animation(PlayerStateNames.WALK).length * 0.5

func update(delta: float) -> void:
	super.update(delta)
	if step_interval > 0.0:
		_step_timer += delta
		if _step_timer >= step_interval:
			_step_timer -= step_interval
			_play_default_step()

func _play_default_step() -> void:
	# 处于声明了地面材质(surface)的区域时，脚步声由 zone 的 FootstepBehavior 提供，
	# 这里压掉玩家自带的默认脚步，避免双重脚步声。
	var director = get_node_or_null("/root/AuZoneDirector")
	if director != null and director.surface() != &"default":
		return
	_play_audio(PlayerStateNames.WALK)

func exit(_to: StringName) -> void:
	_stop_audio(PlayerStateNames.WALK)

func get_transition(_delta: float) -> StringName:
	if not player.is_on_floor():
		return airborne_transition()
	if absf(player.velocity.x) < STOP_EPS:
		return target_stop
	return &""
