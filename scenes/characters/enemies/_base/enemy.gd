extends CharacterBody2D
class_name Enemy


## 死亡瞬间发出一次（血量归零或被 kill() 调用），状态机据此切到 death 状态。
signal enemy_death
## 每次成功结算伤害后发出（无敌帧内的伤害不会触发）。
## 参数 amount：本次扣掉的血量；from：伤害来源节点，陷阱等无来源时为 null。
signal damaged(amount: int, from: Node2D)
## 进入战斗（开战）时发出；参数 target：仇恨目标节点。
signal enter_combat(target: Node2D)
## 离开战斗（丢失 / 回归）时发出。
signal leave_combat

## _validate_property() 用的"隐藏但仍序列化"标记：等价于 @export_storage，
## 保证被隐藏的参数值依然写进 .tscn，不会因为切换配置而丢失。
const HIDDEN_BUT_SAVED := PROPERTY_USAGE_NO_EDITOR | PROPERTY_USAGE_STORAGE

# 检查器分组：导出项按主题折叠，配合 _validate_property() 只显示当前这只怪用得上的参数。
@export_group("生命")
## 最大血量，同时也是血条上限。子类在检查器里覆盖即可。
@export var max_health: int = 100
## 初始血量：出生时取 min(initial_health, max_health)，可用于让敌人残血出场。
@export var initial_health: int = 3

@export_group("运动介质")
## 运动模式：决定垂直方向怎么动、导航是否只取水平分量、死后尸体怎么处理。
## 换这一个资源就能把地面怪变成飞行怪 / 水下怪，无需改动任何状态代码。
##   地面 res://resources/characters/enemies/_shared/locomotion/ground.tres（默认）
##   飞行 res://resources/characters/enemies/_shared/locomotion/flying.tres
##   水下 res://resources/characters/enemies/_shared/locomotion/swimming.tres
## 详见 resources/characters/enemies/_shared/locomotion/enemy_locomotion.gd。
@export var locomotion: EnemyLocomotion = preload("res://resources/characters/enemies/_shared/locomotion/ground.tres")

@export_group("调参预设")
## 整类怪的数值预设：巡逻 / 追击 / 攻击 / 返回的所有数值都可以写进这一个资源，
## 一份 .tres 在多只怪之间复用。留空则完全沿用下面各导出项与各状态自身的默认值。
## 取值优先级：tuning > 本节点同名导出（逐只微调） > 状态脚本默认值。
## 详见 resources/characters/enemies/_shared/enemy_tuning.gd。
@export var tuning: EnemyTuning = null

@export_group("移动")
## 基础移动速度（像素 / 秒）：巡逻 / 追击 / 返回的所有倍率都乘以它。
## 想整体调快调慢一只怪改这里（或改 tuning.move_speed），
## 想只调某一种行为改对应的倍率，不必再逐个状态节点改三处。
@export var move_speed: float = 1.0 * Globals.UNIT_SIZE
## 追击速度倍率（乘以 enemy.move_speed）：< 0 表示沿用 chase 状态自身的默认值。
## 地面怪与飞行怪共用同一套名字：逐只覆盖在世界场景里改这一项即可。
@export var chase_speed_multiplier: float = -1.0

@export_group("受击")
## 受击后的无敌帧时长（秒），由 HitTimer 计时，期间不再结算伤害。
@export var invincible_time: float = 0.3

@export_group("接触伤害")
## 接触伤害总开关：false 时贴身不掉血（纯远程怪 / 中立怪 / 装饰物）。
## 只作用于"接触"这一条路径，投射物伤害与自身受击死亡不受影响。
@export var contact_damage_enabled: bool = true
## 贴身接触或近战命中玩家时造成的伤害值。
@export var contact_damage: int = 1
## 两次伤害玩家之间的冷却（秒），避免贴身时逐帧掉血；由 ContactTimer 计时。
@export var contact_cooldown: float = 0.8


## 出生点：用于 return 状态归位与 leash 范围判定，_ready 时记录。
var spawn_position: Vector2 = Vector2.ZERO

@export_group("巡逻")
## 巡逻总开关：true（默认）= 出生后绕出生点 / 领地来回巡逻；false = 原地待机（站岗 / 悬停）。
## 关闭后仍可被受击 / 领地触发进入战斗，战斗结束后回到巡逻状态继续待机。
## 地面怪与飞行怪共用本开关：两边"怎么巡逻"不同（沿地往返 / 全 2D 飘移），但那是
## 各自 patrol 状态里 _patrol_move() 的差异，开关本身没有任何分支，没必要各存一份。
@export var patrol_enabled: bool = true

## 出生 / 战斗结束后的"驻留"状态：关巡逻＝idle，否则＝patrol。
## return / hurt 回流时统一走这里，避免把"关巡逻的怪"错误送回巡逻逻辑。
func resting_state() -> StringName:
	return EnemyStateNames.IDLE if not patrol_enabled else EnemyStateNames.PATROL

@export_group("感知与仇恨")
## 牵引（leash）半径：目标离开出生点此距离即视为"追丢"，触发 return。
@export var leash_range: float = 700.0
## 丢失目标后多久放弃战斗（秒），用于距离/视线丢失的宽限时间。
@export var combat_lose_time: float = 10.0
## 视线丢失判定开关：true 时超出 leash 且无视线会累计丢失时间。
@export var use_line_of_sight: bool = true
## 绑定的领地（EnemyZone）：玩家踏入该领地时令本敌人开战。
## 留空则不通过领地触发（仍可由受击开战）。在检查器里从世界的 EnemyZones 选择对应领地。
@export var enemy_zone: NodePath = NodePath()

@export_group("攻击")
## 吐出的投射物场景：留空 = 纯近战怪，launch_projectile() 直接返回，不会报错。
## 飞行怪与陆地怪共用：配上即拥有吐弹能力，attack 状态自动切到远程分支。
## 本项始终可见，且决定下面攻击相关项的显隐（见 _validate_property）。
## 值必须是 Ammo 子类的场景，换场景即换弹幕，用于做怪物个性化弹药：
##   res://scenes/projectiles/projectile.tscn        单发直射弹（默认）
##   res://scenes/projectiles/projectile_spread.tscn 散射弹：一发吐出 N 颗扇形散开
##   res://scenes/projectiles/projectile_split.tscn  延迟分裂弹：母弹先飞，到点炸成 N 颗
## 弹药可自行声明只允许某些阵营装配（见 Ammo.usable_by），越权时本函数会拒绝发射。
@export var projectile_scene: PackedScene = null
## 近战触发距离（像素）：与目标距离小于该值即切到 attack 状态。< 0 表示沿用 chase 状态自身的默认值。
## 纯近战怪（未配 projectile_scene）用它；配了 projectile_scene 改用下面的 shoot_range，本项自动隐藏。
## 地面怪与飞行怪共用：地面默认 64（贴身）、飞行默认 140（扑击），默认值各自写在 chase 状态里。
@export var melee_attack_range: float = -1.0
## 投射物携带的伤害值（setup() 时传给投射物，与 contact_damage 相互独立）。
@export var projectile_damage: int = 1
## 远程射程（像素）：与目标直线距离小于该值才切到 attack 吐弹。< 0 表示沿用 chase 状态自身的默认值。
## 地面怪与飞行怪共用：地面默认 400、飞行默认 500，默认值各自写在 chase 状态里。
@export var shoot_range: float = -1.0
## 两次远程攻击之间的冷却（秒）：< 0 表示沿用 chase 状态自身的默认值。
@export var attack_interval: float = -1.0
## 远程追击时与目标保持的水平距离（像素）：< 0 表示沿用 chase 状态自身的默认值；0 = 贴脸。
## 地面怪与飞行怪共用：地面默认 140、飞行默认 120，默认值各自写在 chase 状态里。
@export var shoot_keep_distance: float = -1.0

@export_group("掉落")
## 死亡时掷的掉落表：留空则不掉落。建议做成 .tres 在多只怪之间复用。
@export var drop_table: DropTable = null
## 掉落物相对 DropMarker 的散布半径（像素）：多个掉落物时铺开一点。
@export var drop_scatter: float = 28.0

@export_group("死亡")
## 尸体保留时长（秒）：死亡后停留这么久才开始淡出。<= 0 表示尸体不消失，永久留在场上。
@export var corpse_lifetime: float = 3.0
## 尸体淡出时长（秒）：从完全不透明渐变到透明的耗时。<= 0 表示到点直接消失，不做渐变。
@export var corpse_fade_time: float = 1.0
## 尸体纵向偏移（像素）：死亡落地后把尸体精灵沿 y 轴挪动这么多，
## 用于微调躺尸的纵向位置，让不同素材的尸体贴合地面（正 = 向下，负 = 向上）。0 = 不偏移。
@export var corpse_y_offset: float = 0.0

@export_group("转身")
## 转身动作名：ActionAnimationPlayer 里的同名 clip。留空 = 关闭转身动画。
## 每次翻面（patrol 撞墙/悬崖/端点、chase 面朝目标、return 回巢）都会自动播一次，
## 播完自动回到翻面前正在播的那个动作。敌人没配这个 clip 时行为与现在完全一致（瞬时翻面）。
@export var turn_animation: StringName = &"turn"
## 两次转身动画之间的最小间隔（秒）：目标在朝向死区边缘抖动时，防止把动画反复重放到卡顿。
@export var turn_min_interval: float = 0.2

@export_group("音效")
## 只在镜头内发声：true 时本敌人的所有音效（attack / hurt / death / walk …）都要求
## 自己位于当前镜头可视矩形内才播放。屏幕外很远就开打、远远吐弹的敌人不该把声音送进耳朵。
## 置 false 可退回"无条件播放"（此时仍受 sfx_max_distance 衰减限制）。
@export var sfx_only_on_screen: bool = true
## 可视矩形外扩（像素）：刚走出画面的敌人仍允许发声，避免声音在画面边缘被硬切。
## sfx_only_on_screen = false 时本项自动隐藏。
@export var sfx_screen_margin: float = 240.0
## 音效衰减到静音的距离（像素）：_ready 时写入本敌人所有 AudioStreamPlayer2D.max_distance。
## AudioStreamPlayer2D 默认 2000 太远（本作 1 单位 = 96 像素），隔着大半张地图的攻击声都听得见。
## 默认取略大于一屏对角线（1920×1080 的对角线半径约 1100），保证画面内的声音不会提前闷掉。
@export var sfx_max_distance: float = 1400.0
## 衰减曲线指数：越大越"近处响、远处迅速变轻"，1 = 引擎默认。
@export_range(0.1, 6.0) var sfx_attenuation: float = 1.0

## 战斗丢失计时器：累计"目标丢失 / 出 leash / 无视线"的时长，达到 combat_lose_time 即丢战。
var combat_timer: float = 0.0
## 当前是否处于战斗（仇恨）状态。
var combat_active: bool = false

## 转身表现状态：正在播放 / 播完后要恢复的动作名 / 上次播放时刻（毫秒，负值 = 从未播放过）/ 攒下的翻面次数。
var _turning: bool = false
var _turn_resume: StringName = &""
var _turn_last_ms: int = -1000000
var _turn_pending: int = 0


var health: int
var move_direction: int = 1
var knockback: Vector2 = Vector2.ZERO
var dead: bool = false
var invincible: bool = false

var target: Node2D = null
var last_damage_from: Node2D = null

@onready var collision_shape: CollisionShape2D = $BodyCollisionShape2D
@onready var drop_marker: Marker2D = $DropMarker
## 吐弹口：没有该子节点（纯近战怪）时为 null，发射时退化为自身中心。
@onready var muzzle := get_node_or_null("Muzzle") as Marker2D

@onready var hit_timer: Timer = $Timer/HitTimer
@onready var contact_timer: Timer = $Timer/ContactTimer

@onready var animated_sprite: AnimatedSprite2D = $Animation/EnemyAnimatedSprite
@onready var action_animation_player: AnimationPlayer = $Animation/ActionAnimationPlayer

@onready var debug: CharacterDebug = $Debug
@onready var state_machine: StateMachine = $StateMachine

## 寻路节点：飞行怪与陆地怪的追击都统一由此承接，绕开障碍/地形。
@onready var navigation_agent: NavigationAgent2D = $NavigationAgent2D

## 抵达导航目标的判定距离（像素）：小于该值视为已到达并停止移动。
## 导航内部参数，默认值已够用，故不在检查器显示；确需调整时直接改 .tscn 即可。
@export_storage var nav_arrive_distance: float = 4.0

var audio_nodes: Dictionary = {}

## 接触判定的形状查询参数：复用同一实例，避免每物理帧新建对象与数组。
var _contact_query := PhysicsShapeQueryParameters2D.new()

func _ready() -> void:
	_setup_audio()

	health = mini(initial_health, max_health)
	debug.setup_health(max_health, health)

	spawn_position = global_position
	if not enemy_zone.is_empty():
		var zone := get_node_or_null(enemy_zone)
		if zone != null and zone.has_signal("player_entered") \
				and not zone.player_entered.is_connected(_on_zone_player_entered):
			zone.player_entered.connect(_on_zone_player_entered)

	if contact_timer != null:
		contact_timer.wait_time = contact_cooldown

	if action_animation_player != null:
		if not action_animation_player.animation_finished.is_connected(_on_action_animation_finished):
			action_animation_player.animation_finished.connect(_on_action_animation_finished)
		if not action_animation_player.animation_changed.is_connected(_on_action_animation_changed):
			action_animation_player.animation_changed.connect(_on_action_animation_changed)

	_contact_query.collision_mask = Globals.LAYER_PLAYER
	_contact_query.collide_with_bodies = true
	_contact_query.collide_with_areas = false
	_contact_query.exclude = [self.get_rid()]

	if state_machine != null:
		state_machine.start()


## 收集 Audio 子节点，并统一写入 2D 衰减参数（距离衰减由引擎做，音量随距离自然变轻）。
## 各敌人场景只需在 Audio 下挂 AudioStreamPlayer2D，距离参数在这里一次性接管。
func _setup_audio() -> void:
	var audio_root := get_node_or_null("Audio")
	if audio_root == null:
		return
	for child in audio_root.get_children():
		audio_nodes[child.name] = child
		if child is AudioStreamPlayer2D:
			child.max_distance = sfx_max_distance
			child.attenuation = sfx_attenuation


## 本敌人此刻是否"玩家该听得见"：以当前镜头的可视矩形（四周外扩 sfx_screen_margin）为准。
## 判定放在播放那一帧：屏幕外的敌人不发声，屏幕内的敌人照旧，且随距离自然衰减。
## 拿不到相机（还没进树 / 关卡没相机）时退化为"距玩家 sfx_max_distance 内可听"，避免整场静音。
func is_audible() -> bool:
	if not sfx_only_on_screen:
		return true
	var rect := _audible_rect()
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return _within_sfx_distance()
	return rect.has_point(global_position)

## 可听矩形：镜头中心 ± 半屏（按 zoom 折算）再外扩 sfx_screen_margin。
## 用 get_screen_center_position() 而不是 camera.global_position —— 相机被 limit 卡住时
## 两者不相等，前者才是真正的画面中心。
func _audible_rect() -> Rect2:
	var vp := get_viewport()
	if vp == null:
		return Rect2()
	var cam := vp.get_camera_2d()
	if cam == null or cam.zoom.x <= 0.0 or cam.zoom.y <= 0.0:
		return Rect2()
	var half := vp.get_visible_rect().size * 0.5 / cam.zoom
	return Rect2(cam.get_screen_center_position() - half, half * 2.0).grow(sfx_screen_margin)

## 无相机时的兜底判定：与玩家的距离在衰减半径内即可听。
func _within_sfx_distance() -> bool:
	var p := get_player()
	if p == null:
		return true
	return global_position.distance_to(p.global_position) <= sfx_max_distance


## 垂直运动：整体委托给 locomotion，基类不再替子类做重力 / 悬停 / 浮力分支。
## 没有配 locomotion（理论上不会）时退化为"不动"，与飞行怪存活期的行为一致。
func _apply_vertical_motion(delta: float) -> void:
	if locomotion != null:
		locomotion.apply_vertical(self, delta)


func _apply_movement() -> void:
	velocity += knockback
	knockback = lerp(knockback, Vector2.ZERO, 0.4)
	move_and_slide()


## ---- 地形探测：地面专属，基类给"通行无阻"的默认实现 ----
## 飞行怪 / 水下怪没有落脚点的概念，直接沿用基类默认即可，地面怪（EnemyGround）重写。
## chase / return / patrol 的通用逻辑一律通过这几个函数问路，不要写 `as EnemyGround` 强转：
## 强转会让整段逻辑对第三种怪（水下）直接不可用。

## move_x（±1）方向的前方有没有落脚点。返回 true = 有地，可以走。
func has_ground_ahead(_move_x: float) -> bool:
	return true

## 挑一个"踩得实"的横向方向：优先 preferred_x，它踏空时退而用另一侧；两侧都踏空返回 0.0。
func safe_step_x(preferred_x: float) -> float:
	return preferred_x

## 当前朝向的前方是否撞墙。地面怪查 WallDetector；飞行 / 水下怪恒 false。
func wall_ahead() -> bool:
	return false


## 左右换向：逻辑朝向（move_direction，+1 = 向右）立刻翻转，
## 掉落点、以及子类挂在 _flip_extra() 上的探测器 / 吐弹口也跟着立刻翻（它们只影响逻辑）；
## 接触判定用的是身体碰撞形状（居中对称），不需要跟着翻。
## 精灵画面朝向则可能被转身动画接管，见 _flip_sprite()。
## 注意精灵是"按 scale.x 当前符号取反"，所以素材本身朝左的怪（如 crawlid）
## 必须在场景里把 EnemyAnimatedSprite.scale.x 预置成 -1，让它与 move_direction = +1 对齐；
## 那不是多余的镜像，删掉就会出现"头朝反方向走路"。
func _flip_direction() -> void:
	move_direction *= -1
	for marker in [drop_marker]:
		marker.position.x *= -1
		marker.reset_physics_interpolation()
	_flip_extra()
	_flip_sprite()

func _flip_extra() -> void:
	# 吐弹口跟着朝向翻转（无 Muzzle 的怪为 null，直接跳过）。
	if muzzle != null:
		muzzle.position.x *= -1
		muzzle.reset_physics_interpolation()

## 精灵的左右翻面：能播转身动画时交给动画收尾，否则立即翻。
## 关键点：turn 素材的两帧本身画了 180° 转向（第 0 帧画旧朝向、最后一帧画新朝向），
## 所以动画期间必须保持旧的 scale，等播完再翻一次。若像最早那样"先翻 scale 再播动画"，
## 画面会变成 新朝向 → 第0帧退回旧朝向 → 第1帧又到新朝向，看起来就是"多扭一次/多回一次头"。
## 动画中又翻面（目标来回横跳）时不打断动画，只把翻面次数攒起来，播完一次性结算。
func _flip_sprite() -> void:
	if _turning and action_animation_player != null \
			and action_animation_player.current_animation == turn_animation:
		_turn_pending += 1
		return
	if _try_start_turn():
		_turn_pending = 1
		return
	_apply_sprite_flip()  # 没配转身动画 / 还在冷却：退回瞬时翻面

func _apply_sprite_flip() -> void:
	animated_sprite.scale.x *= -1
	animated_sprite.reset_physics_interpolation()

## 尝试起一次转身动画。守卫让"不是每只怪都配了转身动画"成为默认值：
##   1. turn_animation 为空 / 没有同名 clip → false（调用方立刻翻面，行为与以前一致）；
##   2. 距上次转身不足 turn_min_interval → false（防目标在朝向死区边缘抖动把动画打卡顿）。
func _try_start_turn() -> bool:
	var player := action_animation_player
	if player == null or turn_animation == &"" or not player.has_animation(turn_animation):
		return false
	var now := Time.get_ticks_msec()
	if now - _turn_last_ms < int(turn_min_interval * 1000.0):
		return false
	_turn_last_ms = now
	_turning = true
	_turn_pending = 0
	# 记下当前动作：转身是一次性动画，播完必须还给 idle / walk。
	var current := player.current_animation
	if current == &"" or current == turn_animation or not player.has_animation(current):
		current = &"idle"
	_turn_resume = current if player.has_animation(current) else &""
	player.play(turn_animation)
	return true

## 收尾：把转身期间攒下的精灵翻面一次性结算（奇数才真的翻），并清空状态。
## 绝不能漏掉这一步 —— 否则精灵会一直停在旧朝向，与 move_direction 长期不一致。
func _finish_turn() -> void:
	_turning = false
	if _turn_pending % 2 == 1:
		_apply_sprite_flip()
	_turn_pending = 0
	_turn_resume = &""

## 转身动画播完：把动作还给原来那个（idle / walk），并结算精灵翻面。
## 顺序很重要：先 play + seek 把精灵切到恢复动画的第 0 帧，再翻 scale。
## 反过来的话会有一帧出现"scale 已翻、精灵还停在 turn 最后一帧"的组合，
## 那一帧的朝向会弹回旧方向（轻微版"多回一次头"）。两者在同一回调内完成，渲染前不会露出来。
func _on_action_animation_finished(anim_name: StringName) -> void:
	if anim_name != turn_animation:
		return
	var resume := _turn_resume
	var player := action_animation_player
	_turning = false  # 先落旗，避免下面的 play() 触发 animation_changed 时重复结算
	if player != null and resume != &"" and player.has_animation(resume):
		player.play(resume)
		player.seek(0.0, true)
	_finish_turn()

## 转身动画被别的动作顶掉（受击硬直、切状态抢播 idle、死亡等）：
## 立刻结算精灵翻面，别让它停在旧朝向。
## 注：本回调在 play(_turn_resume) 时也会触发，但那时 _turning 已为 false，不会重复结算。
func _on_action_animation_changed(_old_name: StringName, new_name: StringName) -> void:
	if _turning and new_name != turn_animation:
		_finish_turn()


func take_damage(amount: int, from: Node2D = null) -> void:
	if dead or invincible:
		return
	health -= amount
	_refresh_health_bar()
	damaged.emit(amount, from)
	last_damage_from = from
	# 开战钩子：受击即拉仇恨（target 取玩家，fallback 用伤害来源）。
	_set_combat(true)

	if health <= 0:
		_dead()
		return
	if state_machine != null and state_machine.states.has(EnemyStateNames.HURT):
		state_machine.set_state(EnemyStateNames.HURT, true)
		return
	invincible = true
	hit_timer.start(invincible_time)

func _refresh_health_bar() -> void:
	debug.set_health(health, max_health)

func _dead() -> void:
	if dead:
		return
	dead = true
	_drop_loot()
	enemy_death.emit()
	_start_corpse_fade()

## 死亡后尸体的淡出清理：先停留 corpse_lifetime 秒，再用 corpse_fade_time 秒淡出并移除节点。
## 淡出改的是根节点 modulate，会沿画布层级传递给所有子节点（精灵、血条等）一起消失。
## 物理体保留到最后一刻，因此尸体在淡出期间仍可被踩踏/遮挡；如需立即不挡路，把 corpse_lifetime 调小。
func _start_corpse_fade() -> void:
	if corpse_lifetime <= 0.0:
		return
	var tween := create_tween()
	tween.tween_interval(corpse_lifetime)
	if corpse_fade_time > 0.0:
		tween.tween_property(self, "modulate:a", 0.0, corpse_fade_time)
	tween.tween_callback(queue_free)

## 死亡掉落：位置取 DropMarker（已随朝向翻转），交给 DropSpawner 统一生成。
## 生成放在 _dead() 而非 take_damage()，因此死亡动画播完（0.5s 方法轨道）才爆物品。
func _drop_loot() -> void:
	if drop_table == null:
		return
	var at := drop_marker.global_position if drop_marker != null else global_position
	DropSpawner.spawn_table(drop_table, at, drop_scatter)

func kill() -> void:
	if not dead:
		_dead()

func _on_hit_timer_timeout() -> void:
	invincible = false

## 视线检测用的碰撞层：默认沿用 collision_mask。
## 水下怪等可在 Locomotion.sight_mask 上单独指定（例如让视线穿过水体本身），0 = 沿用。
func _sight_mask() -> int:
	if locomotion != null:
		return locomotion.get_sight_mask(collision_mask)
	return collision_mask

## 玩家是否在视线内（无遮挡）。use_line_of_sight=false 时恒为 true。
func has_line_of_sight() -> bool:
	if not use_line_of_sight:
		return true
	var p := get_player()
	if p == null:
		return false
	var space := get_world_2d().direct_space_state
	var query := PhysicsRayQueryParameters2D.create(global_position, p.global_position)
	query.collision_mask = _sight_mask()
	query.exclude = [self.get_rid()]
	var result := space.intersect_ray(query)
	if result.is_empty():
		return true
	return result.get("collider", null) == p


## 目标是否仍在牵引范围内（出生点 leash_range 内）。未开战时视为在范围内。
func is_within_leash() -> bool:
	if not combat_active:
		return true
	var p := get_player()
	if p == null:
		return false
	return spawn_position.distance_to(p.global_position) <= leash_range


## 推进战斗丢失计时：目标丢失 / 出 leash / 无视线时累计，达到宽限时间则丢战。
func tick_combat(delta: float) -> void:
	if not combat_active:
		return
	var p := get_player()
	var lost := false
	if p == null:
		lost = true
	elif not is_within_leash():
		lost = true
	elif use_line_of_sight and not has_line_of_sight():
		lost = true
	if lost:
		combat_timer += delta
	else:
		combat_timer = 0.0
	if combat_timer >= combat_lose_time:
		_set_combat(false)


## 设置战斗（仇恨）状态并广播信号。开战时记录目标、清零丢失计时。
func _set_combat(active: bool) -> void:
	if combat_active == active:
		return
	combat_active = active
	combat_timer = 0.0
	if active:
		var p := get_player()
		if p != null:
			target = p
		enter_combat.emit(target)
	else:
		leave_combat.emit()

## 领地（EnemyZone）进入回调：玩家踏入本敌人绑定的领地时开战。
func _on_zone_player_entered(_zone: Node, _player: Node2D) -> void:
	enter_combat_zone()

## 由领地（EnemyZone）调用：令本敌人开战（受击开战仍由 take_damage 负责）。
func enter_combat_zone() -> void:
	if dead:
		return
	_set_combat(true)

## 是否只沿水平移动（贴地走 = true，全向 = false）。由 locomotion 决定，
## 调用点不再传 planar_only —— 那会把"运动介质"泄漏到每个状态里。
func is_planar_mover() -> bool:
	return locomotion != null and locomotion.nav_planar_only

## 本敌人此刻是否处在可活动的介质中：地面怪 / 飞行怪恒 true；
## 水下怪只在水体内为 true —— 出水即搁浅，chase / patrol 会据此放弃当前行为转 return 回巢。
## 由 locomotion.can_occupy() 判定（见 resources/characters/enemies/_shared/locomotion/enemy_locomotion.gd），
## SwimmingLocomotion 已重写该函数，消费端（本函数与各状态）无需再动。
func is_in_medium() -> bool:
	if locomotion == null:
		return true
	return locomotion.can_occupy(self, global_position)

## 用 NavigationAgent2D 计算朝 target_pos 的本帧期望速度，由追击状态调用并写回 enemy.velocity。
## speed：期望移动速度（像素/秒）。
## 是否只取水平分量由 locomotion.nav_planar_only 决定（见 is_planar_mover）。
## 已抵达终点时返回零向量；若导航网格缺失/未烘焙，agent 会原地返回，此时退化为直线趋近，保证仍可移动。
func nav_velocity(target_pos: Vector2, speed: float) -> Vector2:
	if global_position.distance_to(target_pos) <= nav_arrive_distance:
		return Vector2.ZERO
	var next_pos := target_pos
	# 没有 NavigationAgent2D 子节点时 next_pos 保持为目标点，退化为直线趋近，
	# 而不是返回零向量把怪钉在原地。
	if navigation_agent != null:
		navigation_agent.target_position = target_pos
		next_pos = navigation_agent.get_next_path_position()
		# 导航网格不可用时 agent 返回自身位置，退化为直接朝目标移动。
		if next_pos.is_equal_approx(global_position):
			next_pos = target_pos
	var dir := global_position.direction_to(next_pos)
	if is_planar_mover():
		dir.y = 0.0
		if dir.x == 0.0:
			return Vector2.ZERO
		dir = Vector2(signf(dir.x), 0.0)
	return dir * speed

## 接触判定：拿自己的身体碰撞形状去查玩家，替代原来的 AttackArea.overlaps_body()。
## 用 intersect_shape 而不是矩形相交：玩家是 80×150 的胶囊（player.tscn 的 2_capsule），
## 把玩家当点测会要求玩家中心深陷怪物体内，手感不对。
## 身体形状换成多边形（ConvexPolygonShape2D 等）时本函数无需改动。
func _body_overlaps_player(p: Node2D) -> bool:
	if collision_shape == null or collision_shape.shape == null or p == null:
		return false
	_contact_query.shape = collision_shape.shape
	_contact_query.transform = collision_shape.global_transform
	var hits := get_world_2d().direct_space_state.intersect_shape(_contact_query, 1)
	return not hits.is_empty() and hits[0].get("collider", null) == p

func try_hit_player(from_contact: bool = true) -> bool:
	if dead or contact_timer.time_left > 0.0:
		return false
	if from_contact and not contact_damage_enabled:
		return false
	var p := get_player()
	if p == null or not p.has_method("take_damage"):
		return false
	if not _body_overlaps_player(p):
		return false
	p.take_damage(contact_damage, self)
	contact_timer.start()
	return true

## 玩家缓存：未开战时 target 为 null，若每次都扫 group 会每物理帧构造一个 Array。
## 只在引用失效（玩家换场景 / 关卡重开）时才重新扫描，其余时候直接命中。
var _player_cache: Node2D = null

func get_player() -> Node2D:
	if is_instance_valid(target) and target.has_method("take_damage"):
		return target
	if is_instance_valid(_player_cache) and _player_cache.has_method("take_damage"):
		return _player_cache
	var players := get_tree().get_nodes_in_group("player")
	_player_cache = players[0] as Node2D if not players.is_empty() else null
	return _player_cache

## 吐弹（远程攻击）：从 muzzle（无则自身中心）朝目标发射一枚投射物。
## 未配置 projectile_scene 时直接返回 —— 纯近战怪的 attack 状态可无条件调用。
func launch_projectile(scene: PackedScene = null) -> void:
	var proj := scene if scene != null else projectile_scene
	if proj == null or not proj.can_instantiate():
		push_warning("%s: projectile_scene 无效或为空，跳过吐弹" % name)
		return
	var p := proj.instantiate()
	if p == null:
		push_warning("%s: 投射物实例化失败" % name)
		return
	# 统一弹药接口：根节点必须是 Ammo 子类（Projectile / ProjectileSpread / ProjectileSplit）。
	if not (p is Ammo):
		push_warning("%s: 投射物根节点不是 Ammo（缺少 fire()），已丢弃" % name)
		p.free()
		return
	# 权限校验：弹药可用 Ammo.usable_by 声明"只允许玩家装配"这类限制。
	if not p.can_be_used_by(Ammo.Faction.ENEMY):
		push_warning("%s: %s 不允许 ENEMY 阵营使用，已丢弃" % [name, proj.resource_path])
		p.free()
		return
	# 阵营由发射方写入：必须在 add_child 之前，弹药入树时才会套用正确的碰撞掩码。
	p.faction = Ammo.Faction.ENEMY
	get_tree().current_scene.add_child(p)
	var origin := muzzle.global_position if muzzle != null else global_position
	p.global_position = origin
	var dir := Vector2(move_direction, 0.0)
	var t := get_player()
	if is_instance_valid(t):
		dir = (t.global_position - origin).normalized()
	p.fire(dir, projectile_damage)

## 是否配置了远程吐弹能力：attack / chase 据此分流远程与近战两套节奏。
func has_projectile() -> bool:
	return projectile_scene != null and projectile_scene.can_instantiate()


## 检查器减负：按当前配置隐藏用不上的导出项，只影响编辑器显示，不改变数值与序列化。
## 例：近战怪未配 projectile_scene → 隐藏全部远程项。
## 子类（EnemyGround 等）若要追加规则，重写后先调用 super._validate_property(property)。
## 注意：新增一种运动介质通常**不需要**改这里 —— 介质专属参数应挂在对应的
## EnemyLocomotion 资源上（如 SwimmingLocomotion），而不是往基类继续堆导出项。
func _validate_property(property: Dictionary) -> void:
	match property.name:
		"melee_attack_range":
			# 远程怪看 shoot_range，只有纯近战怪才需要贴身距离。
			if projectile_scene != null:
				property.usage = HIDDEN_BUT_SAVED
		"projectile_damage", "shoot_range", "attack_interval", "shoot_keep_distance":
			if projectile_scene == null:
				property.usage = HIDDEN_BUT_SAVED
		"contact_damage", "contact_cooldown":
			if not contact_damage_enabled:
				property.usage = HIDDEN_BUT_SAVED
		"drop_scatter":
			if drop_table == null:
				property.usage = HIDDEN_BUT_SAVED
		"sfx_screen_margin":
			if not sfx_only_on_screen:
				property.usage = HIDDEN_BUT_SAVED
