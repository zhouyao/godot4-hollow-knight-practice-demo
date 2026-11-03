extends PlayerState
class_name PlayerBlockState

## 格挡：举盾挡下正面来袭的伤害，持续 block_duration 秒。
## 进入即上冷却（1.5s，读 SkillDefinition）、不消耗能量（energy_cost=0）。
## 地面施放期间根定水平、忽略一切玩家输入（纯防守）；空中（跳跃中）施放则保留起跳时的
## 水平动量，让玩家带着惯性继续滑翔，但仍受重力（之后下坠）。
## "只挡正面"的判定在 PlayerInitial.take_damage 里按伤害来源方向做，这里只开关 block_invincible。

const SKILL_ID: StringName = &"block"

@export var block_duration: float = 0.5
@export var target_grounded: StringName = PlayerStateNames.IDLE

func enter(_from: StringName) -> void:
	player.spend_skill_energy(SKILL_ID)   # 0 消耗，空操作，保留"起手记账"范式
	player.start_skill_cooldown(SKILL_ID)  # 上 1.5s 冷却
	player.start_block_invincible()        # 开启正面格挡
	_play_action(PlayerStateNames.BLOCK)
	player.knockback = Vector2.ZERO
	player.dash_carry = Vector2.ZERO
	# 地面施放则根定水平；空中（跳跃中）施放保留起跳时的水平动量，update 里不再清零。
	if player.is_on_floor():
		player.velocity.x = 0.0

func exit(_to: StringName) -> void:
	player.end_block_invincible()

func update(delta: float) -> void:
	# 地面：根定水平（纯防守）；空中：保留水平动量，仅走重力与位移。
	if player.is_on_floor():
		player.velocity.x = 0.0
	player._apply_gravity(delta)
	player._apply_movement()

func handle_input(_event: InputEvent) -> void:   # 纯防守，屏蔽移动/跳跃/攻击/技能
	pass

func get_transition(_delta: float) -> StringName:
	if elapsed < block_duration:
		return &""
	return PlayerStateNames.FALL if not player.is_on_floor() else target_grounded
