extends PlayerState

## 冲刺：沿朝向前冲 dash_distance，期间不受重力、不吃移动输入，且全程免疫伤害（无敌帧）。
## 可被跳跃（需站在地面）与任意挥砍打断；结束后按是否落地回到 idle 或 fall。
## 施放入口在 PlayerState._try_cast_skill：技能条槽位里装了 id 为 dash 的技能才会进这个状态。
## 能量在这里挂钩子是不够的——准入检查在施放入口做（能量不够根本不进这个状态），
## enter() 只负责按 SkillDefinition.energy_cost 记账，与冷却一样"起手即扣、打断不退"。


@export var target_grounded: StringName = PlayerStateNames.IDLE
@export var target_airborne: StringName = PlayerStateNames.FALL

## 动画速度倍率上限，防止 dash_duration 调得过短导致动画快到看不清。
const MAX_SPEED_SCALE := 20.0

## 与 PlayerState.SKILL_STATES 的 key 一致，施放时按它登记冷却。
const SKILL_ID: StringName = &"dash"

## 当前 dash 产生的残影实例；exit 时收尾并置空，保证一份 dash 对应一份残影（重复触发约束）。
var _dash_effect: PlayerDashEffect


func enter(_from: StringName) -> void:
	# 起手即扣能量并上冷却：冲刺本身的 0.2 秒也计入，中途被 jump / 挥砍打断不退还。
	player.spend_skill_energy(SKILL_ID)
	player.start_skill_cooldown(SKILL_ID)
	# 无敌帧与冲刺同生共死：进入即生效，覆盖到自然结束或被打断为止。
	player.start_dash_invincible()
	# 生成冲刺残影（地面 / 空中共用，内部按 is_on_floor() 做状态判定）。
	# 冷却与能量门槛已在 PlayerState._try_cast_skill 把关，进入本状态即代表一次合法 dash，
	# 因此这里每次 enter 只生成一份，天然满足"冷却 / 重复触发约束"；exit 时统一收尾。
	_dash_effect = PlayerDashEffect.spawn(player, player.get_parent())
	var anim := PlayerStateNames.DASH if player.is_on_floor() else PlayerStateNames.DASH_AIR
	_play_audio(PlayerStateNames.DASH)
	# 倍率必须加在 AnimationPlayer 上：帧号由它的 frame 轨道驱动，
	# 只调 AnimatedSprite2D.speed_scale 会被轨道每帧覆写，动画照样卡在开头。
	_play_action(anim, _anim_speed_scale(anim))
	player.velocity.y = 0.0
	player.knockback = Vector2.ZERO
	player.dash_carry = Vector2.ZERO


## 只有"冲刺接前刺"继承冲刺位移：上挑 / 下劈自己有垂直演出，再加横向余速会飘。
func exit(_to: StringName) -> void:
	# 无敌帧随 dash 一起结束：自然结束 / 被 jump 或挥砍打断 / 死亡切 DEATH 都会走到这里。
	# 只清冲刺这一位，受击无敌帧仍由 hurt_invincibility_timer 自己走完。
	player.end_dash_invincible()
	if _to == PlayerStateNames.SLASH_FORWARD:
		player.start_dash_carry(player.move_direction)
	# dash 结束（自然结束 / 被打断 / 死亡切 DEATH）统一收尾：淡出并自动销毁残影。
	if is_instance_valid(_dash_effect):
		_dash_effect.finish()
		_dash_effect = null


## 冲刺期间水平匀速，朝向锁定进入时的方向，不吃重力。
func update(_delta: float) -> void:
	player.velocity.x = player.move_direction * player.dash_speed
	player._apply_movement()


## 冲刺中途可被 jump（需站在地面）与任意挥砍打断，不必等 dash_duration 走完。
## 挥砍统一交给 on_attack_pressed() 分流（上挑 / 下劈 / 前刺），只屏蔽 _try_cast_skill 的二次冲刺。
func handle_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"jump") and player.is_on_floor():
		player.velocity.y = player.max_jump_velocity
		machine.set_state(PlayerStateNames.JUMP, true)
		return
	if event.is_action_pressed(ATTACK_ACTION):
		on_attack_pressed()


func get_transition(_delta: float) -> StringName:
	if elapsed < player.dash_duration:
		return &""
	return target_airborne if not player.is_on_floor() else target_grounded


## 冲刺动画本身是 1 秒的，把它压进 dash_duration 里播完，否则 0.2 秒只看得到前两帧。
func _anim_speed_scale(anim: StringName) -> float:
	var frames := player.player_animated_sprite.sprite_frames
	if frames == null or not frames.has_animation(anim):
		return 1.0
	var natural := float(frames.get_frame_count(anim)) / maxf(frames.get_animation_speed(anim), 1.0)
	return clampf(natural / maxf(player.dash_duration, 0.01), 1.0, MAX_SPEED_SCALE)
