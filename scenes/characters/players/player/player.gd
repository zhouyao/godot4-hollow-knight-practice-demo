extends CharacterBody2D
class_name PlayerInitial

## 玩家死亡瞬间发出一次（血量归零或被 kill() 调用），状态机据此切到 death 状态。
signal player_death

## 技能进入冷却（start_skill_cooldown 写入冷却表时）发出一次，供技能条按需开始刷新对应槽位，
## 避免技能条每帧无条件轮询所有槽位。
signal skill_cooldown_started(skill_id: StringName)

## 能量值变化（施放消耗 / 命中回复）发出，供技能条按需重算"付不起就变黑"的图标态。
signal energy_changed(energy: int)

## 生命值变化（受伤 / 回血）发出，供技能条重算"满血就变灰"的图标态（如 cure）。
signal health_changed(health: int)

var speed: float = 4 * Globals.UNIT_SIZE
var min_jump_height: float = 0.2 * Globals.UNIT_SIZE
var max_jump_height: float = 3 * Globals.UNIT_SIZE
var min_jump_velocity: float
var max_jump_velocity: float
var jump_duration: float = 0.5
var gravity: float
var move_direction: int = 1

var dash_distance: float = 3.5 * Globals.UNIT_SIZE
var dash_duration: float = 0.2
var dash_speed: float

## 下劈命中敌人后的反弹高度，单位是"格"（在 _ready 里乘 UNIT_SIZE 换算成像素）。
## 之所以导出格数而不是像素：导出项的默认表达式取不到 autoload，写成像素就跟不上 UNIT_SIZE 调整。
@export var slash_down_bounce_height_units: float = 1.6
var slash_down_bounce_height: float
var slash_down_bounce_velocity: float
var slash_down_dive_speed: float = 5.0 * Globals.UNIT_SIZE

## 三段挥砍（前刺 / 上挑 / 下劈）共用的伤害值。
@export var slash_damage: int = 1

var knockback: Vector2 = Vector2.ZERO

## 冲刺被打断成挥砍时残留的水平冲量：指数衰减（与物理帧率解耦），让挥砍带着冲刺的位移滑出去。
var dash_carry: Vector2 = Vector2.ZERO

## 冲量初速 = 冲刺速度 × 该比例，0.6 表示保留六成冲刺速度。
@export var dash_carry_ratio: float = 0.6
## 冲量残留时间的指数衰减速率（每秒），与物理帧率解耦：
## 实际每帧衰减 = lerp(..., 1 - exp(-rate * delta))。rate 越大滑得越近，越小滑得越远。
## 默认 17.3 ≈ 60Hz 下"每帧衰减 0.25"（保留 0.75）。
@export var dash_carry_decay: float = 17.3

## 击退的指数衰减速率（每秒），与物理帧率解耦：实际每帧乘子 = exp(-rate * delta)。
## 默认 30.65 ≈ 60Hz 下"每帧衰减 0.4"（保留 0.6）。
@export var knockback_decay_rate: float = 30.65

## 技能冷却剩余时间表：skill_id -> 剩余秒数。每物理帧递减，归零自动移除条目。
## 放在玩家身上而不是状态里：受击 / 死亡 / 切状态都要继续走表，
## 而且暂停（paused=true）时随物理帧一起冻结，恢复后接着数。
var _skill_cooldowns: Dictionary = {}

## 命中敌人后玩家自身的水平反冲力：沿攻击反方向弹开，走击退通道并逐帧衰减，制造"出手后一顿"的手感。
## 量级远小于受击击退，纯粹是手感调参。
@export var attacker_recoil_x: float = 1000.0

## 受击时的水平击退强度：把玩家弹离伤害来源。
@export var damage_knockback_x: float = 3000.0
## 伤害来源明显在上方 / 下方时附加的垂直弹力（一次性初速度，之后交给重力走弧线）：
## 来源在下方 → 向上弹起，来源在上方 → 向下砸下。同高度命中不附加。
@export var damage_knockback_y: float = 1200.0
## 判定"来源在上 / 下方"的垂直距离阈值（像素）：低于该值视为同高度的水平命中，不附加垂直弹力。
@export var damage_vertical_threshold: float = 16.0

## 最大生命值，同时也是血条上限。
@export var max_health: int = 10
## 初始血量：出生时取 min(initial_health, max_health)，可让角色残血出场。
@export var initial_health: int = 8
## 受击后的无敌帧时长（秒），由 hurt_invincibility_timer 计时，期间不再结算伤害。
@export var invincible_time: float = 0.3
## 冲刺（dash）期间是否免疫伤害：关掉后冲刺只保留位移，不提供无敌帧。
@export var dash_invincible_enabled: bool = true

## 最大能量值，同时也是能量条上限。
@export var max_energy: int = 10
## 初始能量：出生时取 min(initial_energy, max_energy)。命中敌人会 +1，可用于大招消耗。
@export var initial_energy: int = 5

var health: int
var energy: int
var dead: bool = false
var invincible: bool = false

## 冲刺无敌帧标记：只在 dash 状态期间为 true，由 dash 的 enter / exit 成对开关。
## 独立于受击无敌帧 invincible —— 两个来源互不覆盖：dash 退出时只清自己这一位，
## 既不会抹掉受击剩下的无敌帧，也不会被 hurt_invincibility_timer 的 timeout 顺手清掉。
var dash_invincible: bool = false

## 格挡无敌标记：只在 block 状态期间为 true，由 block 的 enter / exit 成对开关。
## 独立于受击无敌帧 invincible 与冲刺无敌帧 dash_invincible，三者互不覆盖。
var block_invincible: bool = false

@onready var camera_marker: Marker2D = $CameraPosition

@onready var collision_shape = $BodyCollisionShape2D
@onready var front_attack_area = $FrontAttackArea
@onready var up_attack_area = $UpAttackArea
@onready var down_attack_area = $DownAttackArea

@onready var hurt_invincibility_timer: Timer = $Timer/hurt_invincibility_timer

@onready var player_animated_sprite: AnimatedSprite2D = $Animation/PlayerAnimatedSprite

@onready var action_animation_player: AnimationPlayer = $Animation/ActionAnimationPlayer
@onready var secondary_animation_player: AnimationPlayer = $Animation/SecondaryAnimationPlayer

@onready var debug: CharacterDebug = $Debug

@onready var state_machine: StateMachine = $StateMachine

var audio_nodes: Dictionary = {}

func _ready() -> void:
	for child in $Audio.get_children():
		audio_nodes[child.name] = child

	# 防止换场景 / 重开战斗后残留 true。
	PlayerCombat.is_attacking = false

	gravity = 2.0 * max_jump_height / pow(jump_duration, 2)
	max_jump_velocity = -sqrt(2.0 * gravity * max_jump_height)
	min_jump_velocity = -sqrt(2.0 * gravity * min_jump_height)
	dash_speed = dash_distance / dash_duration
	slash_down_bounce_height = slash_down_bounce_height_units * Globals.UNIT_SIZE
	slash_down_bounce_velocity = -sqrt(2.0 * gravity * slash_down_bounce_height)

	AuCameraDirector.set_follow(camera_marker)

	health = mini(initial_health, max_health)
	debug.setup_health(max_health, health)

	energy = mini(initial_energy, max_energy)
	debug.setup_energy(max_energy, energy)

	if state_machine != null:
		state_machine.state_changed.connect(_on_player_state_changed)
		state_machine.start()


func _physics_process(delta: float) -> void:
	_tick_skill_cooldowns(delta)


## 冷却逐帧递减：keys() 返回的是拷贝，遍历中 erase 安全。
func _tick_skill_cooldowns(delta: float) -> void:
	for skill_id in _skill_cooldowns.keys():
		var left: float = float(_skill_cooldowns[skill_id]) - delta
		if left <= 0.0:
			_skill_cooldowns.erase(skill_id)
		else:
			_skill_cooldowns[skill_id] = left


## 技能是否在可用状态（不在冷却表里就是可用）。
func is_skill_ready(skill_id: StringName) -> bool:
	return not _skill_cooldowns.has(skill_id)


## 起手即上冷却：时长查 SkillDefinition，未配置冷却（<=0）的技能不进表。
func start_skill_cooldown(skill_id: StringName) -> void:
	var duration := Skills.cooldown_of(skill_id)
	if skill_id == &"" or duration <= 0.0:
		return
	_skill_cooldowns[skill_id] = duration
	skill_cooldown_started.emit(skill_id)


## 剩余冷却秒数（未冷却返回 0）。
func skill_cooldown_left(skill_id: StringName) -> float:
	return float(_skill_cooldowns.get(skill_id, 0.0))


## 剩余冷却比例：1 = 刚用完，0 = 可用（技能条画遮罩用）。
func skill_cooldown_ratio(skill_id: StringName) -> float:
	var total := Skills.cooldown_of(skill_id)
	return 0.0 if total <= 0.0 else clampf(skill_cooldown_left(skill_id) / total, 0.0, 1.0)


## 付得起该技能的起手消耗（消耗 0 的技能恒为 true）。
func can_afford_skill(skill_id: StringName) -> bool:
	return energy >= Skills.energy_cost_of(skill_id)


## 技能当前是否"可用"（图标不该变灰）：能量够 + 技能特定前提。
## 通用技能只看能量；cure 还需非满血（满血回血无意义，按不出去也该变灰）。
func can_use_skill(skill_id: StringName) -> bool:
	if skill_id == &"cure":
		return can_afford_skill(skill_id) and health < max_health
	return can_afford_skill(skill_id)


## 扣掉该技能的起手消耗：能量不足时返回 false 且不动数值，调用方据此放弃施放。
func spend_skill_energy(skill_id: StringName) -> bool:
	var cost := Skills.energy_cost_of(skill_id)
	if energy < cost:
		return false
	energy = maxi(energy - cost, 0)
	_refresh_energy_bar()
	energy_changed.emit(energy)
	return true


func _apply_gravity(delta):
	if velocity.y < 2000:
		velocity.y += gravity * delta

func _apply_movement():
	var dt := get_physics_process_delta_time()
	move_and_slide()
	knockback *= exp(-knockback_decay_rate * dt)
	dash_carry = lerp(dash_carry, Vector2.ZERO, 1.0 - exp(-dash_carry_decay * dt))


## 注入一段沿朝向的水平冲量（冲刺被打断成挥砍时调用），已有余速会被覆盖。
func start_dash_carry(dir: int) -> void:
	dash_carry = Vector2(float(dir) * dash_speed * dash_carry_ratio, 0.0)

func _flip_direction():
	for flipped in [player_animated_sprite,front_attack_area]:
		flipped.scale.x *= -1
		flipped.reset_physics_interpolation()

	camera_marker.position.x = -camera_marker.position.x
	camera_marker.reset_physics_interpolation()

func _handle_move_input():
	var direction = int(Input.get_axis("left", "right"))

	if direction != 0 and direction != move_direction:
		_flip_direction()
		move_direction = direction

	velocity.x = direction * speed
	velocity += knockback + dash_carry
	if(velocity.y < max_jump_velocity):
		velocity.y = max_jump_velocity


## 治疗（食物掉落用）：不会超过 max_health，死亡状态下无效。
func heal(amount: int) -> void:
	if dead or amount <= 0:
		return
	health = mini(health + amount, max_health)
	_refresh_health_bar()
	health_changed.emit(health)

func _dead():
	if dead:
		return
	dead = true
	player_death.emit()

func kill():
	if(!dead):
		_dead()


func take_damage(amount: int, from: Node2D = null) -> void:
	if dead or is_damage_immune():
		return
	# 格挡：正面来袭的伤害被挡下，不掉血、不进受击硬直，仅给反馈。
	if _is_blocking(from):
		_on_blocked(from)
		return
	health -= amount
	_refresh_health_bar()
	health_changed.emit(health)
	if is_instance_valid(player_animated_sprite):
		player_animated_sprite.modulate = Color(4.0, 4.0, 4.0)
		var flash_tween := player_animated_sprite.create_tween()
		flash_tween.tween_property(player_animated_sprite, "modulate", Color.WHITE, invincible_time)
	if health <= 0:
		_dead()
		return
	invincible = true
	hurt_invincibility_timer.start(invincible_time)
	_apply_damage_knockback(from)
	if state_machine != null:
		state_machine.set_state(PlayerStateNames.HURT, true)


## 是否正在格挡且伤害来自正面：来源在玩家朝向一侧即视为正面。
## 对投射物同样有效——body_entered 触发瞬间弹体中心仍在来袭侧，signf 符号正确。
func _is_blocking(from: Node2D) -> bool:
	if not block_invincible or from == null:
		return false
	var side := signf(from.global_position.x - global_position.x)
	return side == float(move_direction)


## 格挡成功反馈：再响一次格挡音（"铛"），并在身前生成格挡火花特效。
func _on_blocked(_from: Node2D) -> void:
	var s := audio_nodes.get(PlayerStateNames.BLOCK) as AudioStreamPlayer2D
	if s != null:
		s.play()
	PlayerBlockEffect.spawn(self, get_parent())

func _apply_damage_knockback(from: Node2D) -> void:
	if from == null:
		knockback = Vector2(float(-move_direction) * damage_knockback_x, 0.0)
		return
	var away := global_position - from.global_position
	var dir_x := signf(away.x)
	if dir_x == 0.0:
		dir_x = float(-move_direction)
	knockback = Vector2(dir_x * damage_knockback_x, 0.0)
	if absf(away.y) > damage_vertical_threshold:
		velocity.y = signf(away.y) * damage_knockback_y

func set_attack_areas_disabled(disabled: bool) -> void:
	for area in [front_attack_area, up_attack_area, down_attack_area]:
		if area == null:
			continue
		var shape := area.get_node_or_null("CollisionPolygon2D") as CollisionPolygon2D
		if shape != null:
			shape.set_deferred("disabled", disabled)

func end_attack() -> void:
	set_attack_areas_disabled(true)
	# 兜底清零：挥砍中途被受击打断（hurt.enter 也会走这里）时登记表不带入下一次挥砍。
	_slash_hit_targets.clear()

func _refresh_health_bar() -> void:
	debug.set_health(health, max_health)

func _refresh_energy_bar() -> void:
	debug.set_energy(energy, max_energy)

func _on_hurt_invincibility_timer_timeout() -> void:
	invincible = false


## 是否免疫伤害：受击无敌帧（hurt_invincibility_timer 计时）或冲刺无敌帧（dash 状态）任一为真即免疫。
## 接触伤害（Enemy.try_hit_player）与投射物伤害（projectile.gd）都走 take_damage，
## 因此这一处判定对两类伤害同时生效；敌人也可据此跳过接触冷却（见 Enemy.try_hit_player）。
func is_damage_immune() -> bool:
	return invincible or dash_invincible


## 开启冲刺无敌帧：dash.enter() 调用；总开关 dash_invincible_enabled 关闭时为空操作。
func start_dash_invincible() -> void:
	dash_invincible = dash_invincible_enabled


## 结束冲刺无敌帧：dash.exit() 调用（自然结束 / 被 jump 或挥砍打断 / 死亡都会走到）。
## 只清冲刺这一位，受击无敌帧仍交给 hurt_invincibility_timer。
func end_dash_invincible() -> void:
	dash_invincible = false


## 开启格挡无敌帧：block.enter() 调用。
func start_block_invincible() -> void:
	block_invincible = true


## 结束格挡无敌帧：block.exit() 调用（自然结束 / 被打断 / 死亡都会走到）。
## 只清格挡这一位，受击 / 冲刺无敌帧不受影响。
func end_block_invincible() -> void:
	block_invincible = false


## 每当玩家自身状态机切换，就把"是否正在攻击"同步到全局标志。
## 读取的是状态节点上的声明式标签 is_attack（进攻型状态置 true），
## 因此 Boss 侧完全不依赖具体状态名 —— 将来玩家加多少攻击态都不用改这里。
func _on_player_state_changed(new_state: StringName, _old_state: StringName) -> void:
	PlayerCombat.is_attacking = false
	var node = state_machine.states.get(new_state, null)
	if is_instance_valid(node) and node.get("is_attack") == true:
		PlayerCombat.is_attacking = true


## 本次挥砍已结算过的目标表（键 = 被砍节点，值忽略，当集合用；节点按实例 id 比较）。
## 生命周期 = 一次挥砍：slash_* 状态的 enter() 调 begin_attack() 清空，end_attack() 兜底再清。
## 去重只按"目标"不按"次数" —— 所以一次挥砍能穿透多个敌人，
## 但同一敌人只吃一次伤害、只回一次能量、只施加一次反冲。
var _slash_hit_targets: Dictionary = {}


## 起手一次挥砍：清空命中登记表。
## 判定区不动 —— 它由动画轨道在 0.1s 处打开，这里提前打开会被 t=0 的关键帧（disabled=true）覆盖。
func begin_attack() -> void:
	_slash_hit_targets.clear()


## 申领一次命中：本次挥砍内首次命中该目标返回 true（可以结算），重复命中返回 false。
func _claim_hit(target: Node) -> bool:
	if target == null or _slash_hit_targets.has(target):
		return false
	_slash_hit_targets[target] = true
	return true


func _on_front_attack_area_body_entered(body: Node2D) -> void:
	if state_machine == null or state_machine.get_state_name() != PlayerStateNames.SLASH_FORWARD:
		return
	_hit_enemy(body)

func _on_up_attack_area_body_entered(body: Node2D) -> void:
	if state_machine == null or state_machine.get_state_name() != PlayerStateNames.SLASH_UP:
		return
	_hit_enemy(body)

func _on_down_attack_area_body_entered(body: Node2D) -> void:
	if state_machine == null or state_machine.get_state_name() != PlayerStateNames.SLASH_DOWN:
		return
	# --- 暂不只针对于怪物，20261031
	#if not (body is Enemy):
	#	return
	# 只在本次挥砍首次命中该目标时结算并反弹：弹起后再落回同一敌人既不结算、也不再弹。
	if _hit_enemy(body):
		velocity.y = slash_down_bounce_velocity

## 结算一次挥砍命中，返回是否真的结算 —— 同一目标在一次挥砍内只返回一次 true。
## 调用方（下劈）据此决定要不要追加"命中后反弹"这类演出。
func _hit_enemy(body: Node2D) -> bool:
	# 去重：本次挥砍已结算过该目标就直接跳过，伤害 / 能量 / 反冲 / 反弹一律不重复给。
	if not _claim_hit(body):
		return false
	if body is Enemy:
		var landed: bool = not body.dead and not body.invincible
		body.take_damage(slash_damage, self)
		if landed:
			energy = mini(energy + 1, max_energy)
			_refresh_energy_bar()
			energy_changed.emit(energy)
		if state_machine != null and state_machine.get_state_name() == PlayerStateNames.SLASH_DOWN:
			return true
		# 反冲只在本次挥砍的首个命中目标上施加：穿透多个敌人时逐个覆盖会让手感发飘。
		if _slash_hit_targets.size() > 1:
			return true
		var away := global_position - body.global_position
		var recoil_dir_x: float = float(-move_direction)
		if away.x > 0.0:
			recoil_dir_x = 1.0
		elif away.x < 0.0:
			recoil_dir_x = -1.0
		knockback = Vector2(recoil_dir_x, 0.0) * attacker_recoil_x
	return true

## 伤害来源种类：供被砍目标按来源选择特效。默认 &"slash"，不同技能可返回不同种类
## （如冲刺斩返回 &"dash"）。目标在 hit_effect_by_source 里配置对应种类即可细分特效。
func get_damage_kind() -> StringName:
	return &"slash"

# ---- 反馈 B：攻击区域命中草等 Area2D 对象（草是 Area2D，body_entered 检测不到） ----
func _on_attack_area_area_entered(area: Node) -> void:
	if state_machine == null:
		return
	# 只在挥砍状态下结算，避免走动擦碰时误触发
	var state := state_machine.get_state_name()
	if state != PlayerStateNames.SLASH_FORWARD and state != PlayerStateNames.SLASH_UP \
			and state != PlayerStateNames.SLASH_DOWN:
		return
	# 跳过玩家自身的攻击子区域，只命中外部可受伤对象（草、宝箱等）
	if area == self or area.get_parent() == self:
		return
	# 与 body 路径同一套去重：草 / 宝箱等 Area2D 目标在一次挥砍里同样只结算一次。
	if area.has_method("take_damage") and _claim_hit(area):
		area.take_damage(slash_damage, self)
