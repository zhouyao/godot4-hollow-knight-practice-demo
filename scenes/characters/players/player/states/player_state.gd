extends State
class_name PlayerState


const ATTACK_ACTION: StringName = &"attack"

## 该状态是否处于"攻击动作中"：供 Boss AI 的全局攻击标志判断玩家是否在进攻。
## 只有进攻型状态（挥砍 / 冲刺斩 / 法术…）需要重写为 true，其余保持默认 false。
## 集中由 PlayerInitial 监听 state_changed 读取本属性，新增攻击招式无需改动 Boss 侧。
var is_attack: bool = false

## 技能 id → 玩家状态名。新技能想被技能条施放，除了在 SkillRegistry 上架，还要在这张表里登记。
const SKILL_STATES: Dictionary = {&"dash": PlayerStateNames.DASH, &"block": PlayerStateNames.BLOCK, &"cure": PlayerStateNames.CURE}

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
	# 地面跳 / 土狼跳 / 空中振翅统一交给玩家裁决，这里只负责把结果切进对应状态。
	if event.is_action_pressed(&"jump"):
		var jump_state := player.try_jump()
		if jump_state != &"":
			if machine != null:
				machine.set_state(jump_state, true)
			return
		# 条件不满足（振翅用完 / 还没落地）：记一笔缓冲，落地瞬间自动补跳。
		player.buffer_jump()
	elif event.is_action_released(&"jump") and player.velocity.y < player.min_jump_velocity:
		# 松键截断对地面跳与振翅一视同仁：按住越久跳得越高。
		player.velocity.y = player.min_jump_velocity
	if _try_cast_skill(event):
		return
	if event.is_action_pressed(ATTACK_ACTION):
		on_attack_pressed()


## 按技能条槽位按键施放：空槽、没登记的技能、冷却未走完、能量不够、当前状态不允许时什么都不做。
## 冷却中 / 能量不足的按键直接吞掉（不再往下传给 attack），不给任何反馈。
## 受击（hurt 自己屏蔽了输入）与死亡（machine.active=false）天然进不到这里。
func _try_cast_skill(event: InputEvent) -> bool:
	for slot in InputBindings.SKILL_SLOT_ACTIONS.size():
		if not event.is_action_pressed(InputBindings.slot_action(slot)):
			continue
		var skill_id: StringName = Settings.skill_bar.get_skill(slot)
		var target: StringName = SKILL_STATES.get(skill_id, &"")
		if target != &"" and machine != null \
				and player.is_skill_ready(skill_id) and player.can_use_skill(skill_id):
			machine.set_state(target, true)
		return true
	return false

func on_attack_pressed() -> void:
	if machine == null:
		return
	if Input.is_action_pressed(&"up"):
		machine.set_state(PlayerStateNames.SLASH_UP, true)
		return
	if not player.is_on_floor() and Input.is_action_pressed(&"down"):
		machine.set_state(PlayerStateNames.SLASH_DOWN, true)
		return
	machine.set_state(PlayerStateNames.SLASH_FORWARD)

func _play_action(anim_name: StringName, custom_scale: float = 1.0) -> void:
	player.action_animation_player.play(anim_name, -1.0, custom_scale)

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
