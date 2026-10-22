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

## custom_scale：播放速率倍率（1.0 = 原速），用于把动画时长对齐到状态时长
func _play_action(anim_name: StringName, custom_scale: float = 1.0) -> void:
	player.action_animation_player.play(anim_name, -1.0, custom_scale)

## 播放动作动画，并把它的实际时长对齐到 duration 秒。
## 动画资源本身按固定长度制作（三段挥砍与受击都是 0.3s），状态侧的 hold_time 才是可调旋钮。
## 这里用播放速率等比拉伸，避免"改了 hold_time 却忘了重做动画"造成错位：
##   动画比状态长 → 尾部的判定区关闭帧 / 刀光隐藏帧被下一状态打断而残留；
##   动画比状态短 → 状态后段僵在动画最后一帧。
## duration <= 0 或动画缺失时退回原速播放。
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
