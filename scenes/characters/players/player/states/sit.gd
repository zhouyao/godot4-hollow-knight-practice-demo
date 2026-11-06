extends PlayerState
class_name PlayerSitState

## 坐下（休息）：由长椅 / 椅子触发（Bench.sit_on_enter → PlayerInitial.sit_down）。
##
## 行为：
##   · 坐下期间原地不动：有座位锚点（椅子）时被钉在座位上，没有时只保留重力贴住地面；
##   · 每 restore_interval 秒回一次血与能量，均不超过上限（默认 0.5s → +1 血 +1 能）；
##   · 玩家按方向键 / 跳跃 / 攻击 / 技能槽位键即起身回 idle；受击 / 死亡由外部强制切走。
##
## 动画：ActionAnimationPlayer 的 sit（0.5s，含坐下的烟雾特效），播完停在坐姿。
## 起身后由椅子监听 state_changed 重新上冷却，避免站在原地反复被按进坐姿。

@export_group("行为 Behavior")
## 回血回能的间隔（秒）：0.5 表示每半秒一跳。
@export var restore_interval: float = 0.5
## 每跳回血量，上限封顶 max_health。
@export var restore_health: int = 1
## 每跳回能量，上限封顶 max_energy。
@export var restore_energy: int = 1
## 坐下后多久才响应起身输入（秒）：防止进场瞬间的方向键 / 攻击键立刻把角色叫起来。
@export var min_sit_time: float = 0.15

@export_group("状态过渡 Transitions")
## 起身后切往的状态（一般是 idle）。
@export var target_stand: StringName = PlayerStateNames.IDLE

## 距离下一跳回复还差多少秒。
var _restore_timer: float = 0.0


func enter(_from: StringName) -> void:
	_restore_timer = 0.0
	player.velocity = Vector2.ZERO
	player.knockback = Vector2.ZERO
	player.dash_carry = Vector2.ZERO
	_play_action(PlayerStateNames.SIT)


func update(delta: float) -> void:
	player.velocity.x = 0.0
	# 有座位（椅子上）：位置已由 sit_down() 钉住，这里不再走重力 / 位移，
	# 否则角色会从椅面滑到地面，看起来像"坐在地上"。
	if player.sit_anchor != Vector2.INF:
		player.velocity = Vector2.ZERO
		player.global_position = player.sit_anchor
		_tick_restore(delta)
		return
	# 没有座位（平地坐下）：只走重力 + 位移，保证贴在椅子所在的地面上。
	player._apply_gravity(delta)
	player._apply_movement()
	_tick_restore(delta)


## 起身 / 受击 / 死亡：交还重力，让角色自己落回地面，下次坐下重新取座位。
func exit(_to: StringName) -> void:
	player.sit_anchor = Vector2.INF
	player.effect_animated_sprite.visible = false

## 每 restore_interval 秒补一次血与能量；用 while 而不是 if，掉帧时不会少给。
func _tick_restore(delta: float) -> void:
	if restore_interval <= 0.0:
		return
	_restore_timer += delta
	while _restore_timer >= restore_interval:
		_restore_timer -= restore_interval
		if player.health < player.max_health:
			player.heal(restore_health)
		if player.energy < player.max_energy:
			player.restore_energy(restore_energy)


func handle_input(event: InputEvent) -> void:
	if elapsed < min_sit_time:
		return
	if not _is_leave_pressed(event):
		return
	if machine != null:
		machine.set_state(target_stand, true)


## 起身输入：方向键 / 跳跃 / 攻击 / 技能槽位键。
## 只看"按下瞬间"，所以进场时一直按着方向键不会立刻站起来。
func _is_leave_pressed(event: InputEvent) -> bool:
	for action in [&"left", &"right", &"up", &"down", &"jump", ATTACK_ACTION]:
		if event.is_action_pressed(action):
			return true
	for slot in InputBindings.SKILL_SLOT_ACTIONS.size():
		if event.is_action_pressed(InputBindings.slot_action(slot)):
			return true
	return false
