extends EnemyState
class_name EnemyHurtState


## 受击时的水平击退强度：只在"伤害来源与自身的水平距离大于垂直距离"时才生效，
## 也就是说来自正上 / 正下方的攻击不会把怪打飞，避免飞行怪被砸出领地。
@export var knockback_x: float = 3500.0

## 硬直时长（秒）。为 0 时自动取 enemy.invincible_time，让硬直与无敌帧等长。
@export var hold_time: float = 0.0

## 硬直结束后强制切往的状态。留空则回到进入 hurt 之前的那个状态（没有记录就回 idle）。
@export var target_state: StringName = &""

var _return_from: StringName = &""

func enter(from: StringName) -> void:
	if from != EnemyStateNames.HURT:
		_return_from = from
	if enemy == null:
		return
	_flash_white()
	_play_audio(EnemyStateNames.HURT)
	if enemy.action_animation_player != null \
			and enemy.action_animation_player.has_animation(EnemyStateNames.HURT):
		_play_action(EnemyStateNames.HURT)
	enemy.velocity.x = 0.0
	_apply_damage_knockback()
	enemy.invincible = true

func update(delta: float) -> void:
	enemy.velocity.x = 0.0
	enemy._apply_vertical_motion(delta)
	enemy._apply_movement()

func get_transition(_delta: float) -> StringName:
	if elapsed <= _get_hold_time():
		return &""
	if target_state != &"":
		return target_state
	return _return_from if _return_from != &"" else EnemyStateNames.IDLE

func exit(_to: StringName) -> void:
	if enemy != null:
		enemy.invincible = false

func _apply_damage_knockback() -> void:
	var src := enemy.last_damage_from
	if src == null or not is_instance_valid(src):
		return
	var to_self := enemy.global_position - src.global_position
	if absf(to_self.x) < absf(to_self.y):
		return
	enemy.knockback = Vector2(knockback_x if to_self.x >= 0.0 else -knockback_x, 0.0)

func _get_hold_time() -> float:
	if hold_time > 0.0:
		return hold_time
	return enemy.invincible_time if enemy != null else 0.0
