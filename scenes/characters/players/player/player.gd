extends CharacterBody2D
class_name PlayerInitial

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

## 下劈命中敌人的反弹高度（单位：格，检查器可调）。
## 这里导出的是"格数"而非像素值：导出项的默认表达式拿不到 autoload（Globals.UNIT_SIZE），
## 与 enemy.gd 的 move_speed 同族处理——像素值在 _ready 里换算，保证跟随 UNIT_SIZE 变化。
@export var slash_down_bounce_height_units: float = 1.6
## 反弹高度（像素 = 格数 * UNIT_SIZE），由 _ready 换算，供调试 / 其他系统读取
var slash_down_bounce_height: float
var slash_down_bounce_velocity: float
## 起手向下俯冲的速度：与当前下落速度取较大值，保证空中下劈有"砸下去"的手感
var slash_down_dive_speed: float = 5.0 * Globals.UNIT_SIZE

## 三段挥砍（前刺 / 上挑 / 下劈）共用的伤害值
@export var slash_damage: int = 1

var knockback: Vector2 = Vector2.ZERO

## 攻击反冲力（Game Feel 调参）：命中瞬间玩家沿攻击反方向的小幅击退。
## 水平 attacker_recoil_x、垂直 0，制造"出手后被弹回"的后坐感，量级远小于敌人击飞。
## 走 knockback 通道、每帧向零衰减，形成"一挫即回弹"的短促手感。
@export var attacker_recoil_x: float = 1000.0

## 受击击退（与攻击反冲同一通道，量级更大）：水平把玩家弹离伤害来源。
@export var damage_knockback_x: float = 3000.0
## 伤害来源明显在上 / 下方时附加的垂直弹力（一次性初速度，之后交给重力走弧线）：
## 来源在下方 → 向上弹起；来源在上方 → 向下砸下。水平方向的命中不附加，保持手感干净。
@export var damage_knockback_y: float = 1200.0
## 判定"来源在上 / 下方"的垂直阈值（像素）：低于该值视为同高度的水平命中，不附加垂直弹力
@export var damage_vertical_threshold: float = 16.0

## 最大生命值（导出，检查器覆盖）。与怪物血条一致。
@export var max_health: int = 100
## 初始血量（导出，检查器覆盖）。出生时 health = initial_health，可小于 max_health（例如残血出场）
@export var initial_health: int = 90
## 受击后的无敌帧时长，由 HitTimer 计时（与怪物一致）
@export var invincible_time: float = 0.3

## 最大能量值（导出，检查器覆盖）。能量条初始为满，击中怪物 +1。
@export var max_energy: int = 100
## 初始能量（导出，检查器覆盖）。出生时 energy = initial_energy，可小于 max_energy
@export var initial_energy: int = 100

var health: int
var energy: int
var dead: bool = false
var invincible: bool = false

## 相机跟随锚点：只提供位置，真正的相机决策全在 AuCameraDirector
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

	# 自己上报相机跟随锚点：这样即使死亡重生（本节点被重建），相机也能重新挂上，
	# 不用依赖关卡脚本重新赋值。
	AuCameraDirector.set_follow(camera_marker)

	health = mini(initial_health, max_health)
	debug.setup_health(max_health, health)

	energy = mini(initial_energy, max_energy)
	debug.setup_energy(max_energy, energy)

	# 放在最后：此时本节点的 @onready 成员已就绪，状态机进入初始状态是安全的
	if state_machine != null:
		state_machine.start()


func _apply_gravity(delta):
	if velocity.y < 2000:
		velocity.y += gravity * delta

func _apply_movement():
	move_and_slide()
	knockback = lerp(knockback, Vector2.ZERO, 0.4)

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
	velocity += knockback
	if(velocity.y < max_jump_velocity):
		velocity.y = max_jump_velocity


func _dead():
	if dead:
		return
	dead = true
	player_death.emit()

func kill():
	if(!dead):
		_dead()

# ---- 受击 / 血条（与怪物一致）----
func take_damage(amount: int, from: Node2D = null) -> void:
	if dead or invincible:
		return
	health -= amount
	_refresh_health_bar()
	# 受击闪白：瞬间提亮精灵，再用 tween 渐回正常
	if is_instance_valid(player_animated_sprite):
		player_animated_sprite.modulate = Color(4.0, 4.0, 4.0)
		var flash_tween := player_animated_sprite.create_tween()
		flash_tween.tween_property(player_animated_sprite, "modulate", Color.WHITE, invincible_time)
	if health <= 0:
		_dead()
		return
	invincible = true
	hit_timer.start(invincible_time)
	# 死亡分支已 return，这里一定是"活着被打中"：算击退并进入受击硬直
	_apply_damage_knockback(from)
	if state_machine != null:
		state_machine.set_state(PlayerStateNames.DAMAGE, true)

## 受击击退：弹开方向统一取 away = 玩家 - 伤害来源。
##   水平：来源在左 → away.x > 0 → 往右弹开；来源在右 → 往左弹开。
##         正上 / 正下的来源水平分量为 0，退化为朝玩家背后弹开。
##   垂直：来源在下方 → away.y < 0 → 向上弹起；来源在上方 → away.y > 0 → 向下砸下；
##         同高度的水平命中（|away.y| 未过阈值）不附加，保持手感干净。
## 水平走 knockback 通道（每帧向零衰减，"一挫即回弹"）；垂直是一次性初速度，交给重力走弧线。
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

## 统一开关三个攻击判定区。受击硬直时强制关闭，避免挥砍被打断后判定区残留开启。
## 后续挥砍动画的关键帧会重新按需要打开它们，二者不冲突。
func set_attack_areas_disabled(disabled: bool) -> void:
	for area in [front_attack_area, up_attack_area, down_attack_area]:
		if area == null:
			continue
		var shape := area.get_node_or_null("CollisionPolygon2D") as CollisionPolygon2D
		if shape != null:
			# 必须延迟：受击 / 打断通常发生在 body_entered 回调里，此刻物理服务器正在
			# flush queries，直接写 disabled 会被拒绝（"Can't change this state while
			# flushing queries"）并被静默丢弃——判定区看起来关了、实际还开着。
			shape.set_deferred("disabled", disabled)

## 攻击收尾：关闭三个判定区 + 隐藏三段挥砍特效。
## 挥砍动画的判定区（0.05~0.15s 开启）与特效精灵（0.05~0.15s 可见）都由关键帧驱动，
## 一旦在窗口中间被打断（受击 / 死亡 / 其它），动画被换掉后最后一帧的值会永久留下
## （判定区开启 + 刀光可见），而 damage / death / idle 等动画都没有对应轨道收尾。
## 由各攻击状态的 exit() 调用：状态机切到任何状态都会先跑 exit()，覆盖所有打断原因。
func end_attack() -> void:
	set_attack_areas_disabled(true)
	for sprite in [slash_forward_animated_sprite, slash_up_animated_sprite, slash_down_animated_sprite]:
		if is_instance_valid(sprite):
			sprite.visible = false

## 扣血后刷新血条数值、颜色与文字
func _refresh_health_bar() -> void:
	debug.set_health(health, max_health)

## 无敌帧结束
func _on_hit_timer_timeout() -> void:
	invincible = false
		
# ---- 攻击 / 受击判定 ----
# 三个攻击判定区默认 disabled；由 ActionAnimationPlayer 在挥砍帧打开对应判定区、
# 动画结束帧再关闭。

# 只有 slash_forward 动画会打开该判定区（与下劈同构的状态守卫）
func _on_front_attack_area_body_entered(body: Node2D) -> void:
	if state_machine == null or state_machine.get_state_name() != PlayerStateNames.SLASH_FORWARD:
		return
	_hit_enemy(body)

# 只有 slash_up 动画会打开该判定区
func _on_up_attack_area_body_entered(body: Node2D) -> void:
	if state_machine == null or state_machine.get_state_name() != PlayerStateNames.SLASH_UP:
		return
	_hit_enemy(body)


func _on_down_attack_area_body_entered(body: Node2D) -> void:
# 	只有 slash_down 动画会打开该判定区
	if state_machine == null or state_machine.get_state_name() != PlayerStateNames.SLASH_DOWN:
		return
	# 只有怪物才结算伤害并弹起：劈到地面 / 道具什么都不做
	if not (body is Enemy):
		return
	_hit_enemy(body)
	velocity.y = slash_down_bounce_velocity

## 只对敌人结算伤害。击退方向交给敌人自己按攻击来源位置推算，
## 所以这里不用关心玩家朝哪个方位砍（前刺推开 / 上挑顶起 / 下劈砸下）。
## 命中瞬间触发：玩家攻击反冲 + 敌人击飞。
func _hit_enemy(body: Node2D) -> void:
	if body is Enemy:
		# 仅当这一击真正生效（敌人未死亡且不在无敌帧）时才积累能量
		var landed: bool = not body.dead and not body.invincible
		body.take_damage(slash_damage, self)
		if landed:
			energy = mini(energy + 1, max_energy)
			debug.set_energy(energy, max_energy)
		# 下劈走 Pogo 反弹（向上弹起），不走横向反冲，保持手感干净
		if state_machine != null and state_machine.get_state_name() == PlayerStateNames.SLASH_DOWN:
			return
		# 攻击反冲：沿「远离敌人」方向给玩家小幅水平击退，制造"出手后被弹回"的后坐感。
		# away = 玩家 - 敌人：其 x 的正负号就是玩家远离敌人的方向
		# （玩家在敌人右 → away.x>0 → +1 向右远离；在左 → away.x<0 → -1 向左远离）。
		var away := global_position - body.global_position
		var recoil_dir_x: float = float(-move_direction)
		if away.x > 0.0:
			recoil_dir_x = 1.0
		elif away.x < 0.0:
			recoil_dir_x = -1.0
		knockback = Vector2(recoil_dir_x, 0.0) * attacker_recoil_x
