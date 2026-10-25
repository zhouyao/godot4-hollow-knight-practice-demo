extends CharacterBody2D
class_name PlayerInitial


## 玩家死亡瞬间发出一次（血量归零或被 kill() 调用），状态机据此切到 death 状态。
signal player_death

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

## 冲刺被打断成挥砍时残留的水平冲量：逐帧衰减，让挥砍带着冲刺的位移滑出去。
var dash_carry: Vector2 = Vector2.ZERO

## 冲量初速 = 冲刺速度 × 该比例，0.6 表示保留六成冲刺速度。
@export var dash_carry_ratio: float = 0.6
## 冲量每物理帧的衰减系数：越小滑得越远（0.25 ≈ 滑 0.7 格）。
@export var dash_carry_decay: float = 0.25

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
## 受击后的无敌帧时长（秒），由 HitTimer 计时，期间不再结算伤害。
@export var invincible_time: float = 0.3

## 最大能量值，同时也是能量条上限。
@export var max_energy: int = 10
## 初始能量：出生时取 min(initial_energy, max_energy)。命中敌人会 +1，可用于大招消耗。
@export var initial_energy: int = 5

var health: int
var energy: int
var dead: bool = false
var invincible: bool = false

@onready var camera_marker: Marker2D = $CameraPosition

@onready var collision_shape = $CollisionShape2D
@onready var front_attack_area = $FrontAttackArea
@onready var up_attack_area = $UpAttackArea
@onready var down_attack_area = $DownAttackArea

@onready var hit_timer: Timer = $Timer/HitTimer

@onready var player_animated_sprite: AnimatedSprite2D = $Animation/PlayerAnimatedSprite
@onready var slash_forward_animated_sprite: AnimatedSprite2D = $Animation/SlashForwardAnimatedSprite
@onready var slash_up_animated_sprite: AnimatedSprite2D = $Animation/SlashUpAnimatedSprite
@onready var slash_down_animated_sprite: AnimatedSprite2D = $Animation/SlashDownAnimatedSprite

@onready var action_animation_player: AnimationPlayer = $Animation/ActionAnimationPlayer
@onready var secondary_animation_player: AnimationPlayer = $Animation/SecondaryAnimationPlayer

@onready var debug: CharacterDebug = $Debug

@onready var state_machine: StateMachine = $StateMachine

var audio_nodes: Dictionary = {}

func _ready() -> void:
	for child in $Audio.get_children():
		audio_nodes[child.name] = child

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


## 扣掉该技能的起手消耗：能量不足时返回 false 且不动数值，调用方据此放弃施放。
func spend_skill_energy(skill_id: StringName) -> bool:
	var cost := Skills.energy_cost_of(skill_id)
	if energy < cost:
		return false
	energy = maxi(energy - cost, 0)
	_refresh_energy_bar()
	return true


func _apply_gravity(delta):
	if velocity.y < 2000:
		velocity.y += gravity * delta

func _apply_movement():
	move_and_slide()
	knockback = lerp(knockback, Vector2.ZERO, 0.4)
	dash_carry = lerp(dash_carry, Vector2.ZERO, dash_carry_decay)


## 注入一段沿朝向的水平冲量（冲刺被打断成挥砍时调用），已有余速会被覆盖。
func start_dash_carry(dir: int) -> void:
	dash_carry = Vector2(float(dir) * dash_speed * dash_carry_ratio, 0.0)

func _flip_direction():
	for flipped in [player_animated_sprite,slash_forward_animated_sprite,front_attack_area]:
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

func _dead():
	if dead:
		return
	dead = true
	player_death.emit()

func kill():
	if(!dead):
		_dead()


func take_damage(amount: int, from: Node2D = null) -> void:
	if dead or invincible:
		return
	health -= amount
	_refresh_health_bar()
	if is_instance_valid(player_animated_sprite):
		player_animated_sprite.modulate = Color(4.0, 4.0, 4.0)
		var flash_tween := player_animated_sprite.create_tween()
		flash_tween.tween_property(player_animated_sprite, "modulate", Color.WHITE, invincible_time)
	if health <= 0:
		_dead()
		return
	invincible = true
	hit_timer.start(invincible_time)
	_apply_damage_knockback(from)
	if state_machine != null:
		state_machine.set_state(PlayerStateNames.HURT, true)

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
	for sprite in [slash_forward_animated_sprite, slash_up_animated_sprite, slash_down_animated_sprite]:
		if is_instance_valid(sprite):
			sprite.visible = false

func _refresh_health_bar() -> void:
	debug.set_health(health, max_health)

func _refresh_energy_bar() -> void:
	debug.set_energy(energy, max_energy)

func _on_hit_timer_timeout() -> void:
	invincible = false


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
	if not (body is Enemy):
		return
	_hit_enemy(body)
	velocity.y = slash_down_bounce_velocity

func _hit_enemy(body: Node2D) -> void:
	if body is Enemy:
		var landed: bool = not body.dead and not body.invincible
		body.take_damage(slash_damage, self)
		if landed:
			energy = mini(energy + 1, max_energy)
			_refresh_energy_bar()
		if state_machine != null and state_machine.get_state_name() == PlayerStateNames.SLASH_DOWN:
			return
		var away := global_position - body.global_position
		var recoil_dir_x: float = float(-move_direction)
		if away.x > 0.0:
			recoil_dir_x = 1.0
		elif away.x < 0.0:
			recoil_dir_x = -1.0
		knockback = Vector2(recoil_dir_x, 0.0) * attacker_recoil_x
