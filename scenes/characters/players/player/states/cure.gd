extends PlayerState
class_name PlayerCureState

## 回血：消耗 1 点能量回复 1 点生命（1 能换 1 血），冷却 1 秒。
## 施放期间无法移动：地面根定水平；空中施放则悬停（抵消重力，原地停住）。
## 施放结束：在地面回 idle，在空中回 fall（自然下坠）。
## 音效由 ActionAnimationPlayer 的 cure 动画轨道驱动（cure1 / cure2），无需额外 _play_audio。
## 施放入口在 PlayerState._try_cast_skill：技能条槽位里装了 id 为 cure 的技能才会进这个状态。


const SKILL_ID: StringName = &"cure"

@export_group("行为 Behavior")
## 单次施放回血量，与 SkillDefinition.energy_cost 1:1（"1 能换 1 血"）。
@export var heal_amount: int = 1
## 施放持续时长（秒）：与 ActionAnimationPlayer 的 cure 动画长度（≈1.0s）对齐。
@export var cure_duration: float = 1.0

func enter(_from: StringName) -> void:
	# 起手即扣能量并上冷却：与 dash / block 一致"起手记账、打断不退"。
	player.spend_skill_energy(SKILL_ID)
	player.start_skill_cooldown(SKILL_ID)
	# 1 能换 1 血：满血时本状态进不来（can_use_skill 已拦），这里直接回血，上限封顶。
	player.heal(heal_amount)
	_play_action(PlayerStateNames.CURE)
	player.velocity.x = 0.0
	player.knockback = Vector2.ZERO
	player.dash_carry = Vector2.ZERO

func update(_delta: float) -> void:
	# 施放期间无法移动：水平根定。
	player.velocity.x = 0.0
	# 空中施放：悬停（抵消重力），原地停住；地面则交给重力 + 地面接触自然站定。
	if not player.is_on_floor():
		player.velocity.y = 0.0
	player._apply_movement()

## 施放期间屏蔽一切玩家输入（移动 / 跳跃 / 攻击 / 再次技能），保证"无法移动"。
func handle_input(_event: InputEvent) -> void:
	pass

func get_transition(_delta: float) -> StringName:
	if elapsed < cure_duration:
		return &""
	return PlayerStateNames.FALL if not player.is_on_floor() else PlayerStateNames.IDLE
