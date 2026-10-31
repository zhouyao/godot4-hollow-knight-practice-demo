extends CharacterBody2D
class_name Enemy


#region 信号

## 死亡瞬间发出一次（血量归零或被 kill() 调用），状态机据此切到 death 状态。
signal enemy_death
## 每次成功结算伤害后发出（无敌帧内的伤害不会触发）。
## 参数 amount：本次扣掉的血量；from：伤害来源节点，陷阱等无来源时为 null。
signal damaged(amount: int, from: Node2D)
## 进入战斗（开战）时发出；参数 target：仇恨目标节点。
signal enter_combat(target: Node2D)
## 离开战斗（丢失 / 回归）时发出。
signal leave_combat

#endregion


#region 配置（检查器）

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
## 受击后的无敌帧时长（秒），由 hurt_invincibility_timer 计时，期间不再结算伤害。
@export var invincible_time: float = 0.3
## 受击特效表：键为来源 get_damage_kind() 返回的 StringName，值为场景。
## 约定键 &"slash" 为默认受击表现（玩家挥砍）；查不到来源种类时回落到 &"slash"；
## 仍无匹配则回落 _NAIL（通用刀光）。例：{&"slash": puff, &"fire": fire_spark}
@export var hit_effect_by_source: Dictionary = {
	&"slash": preload("res://scenes/effects/enemies/puff_hit_effect.tscn")
}
## 命中特效数量随机范围（闭区间）：每次受击按此范围摇一个数量。
@export_range(0, 24, 1, "or_greater") var hit_effect_count_min: int = 2
@export_range(0, 24, 1, "or_greater") var hit_effect_count_max: int = 4
## 多份特效在命中点周围的散布半径（像素），0 = 全部叠在同一点。
@export var hit_effect_scatter: float = 100.0

@export_group("接触伤害")
## 接触伤害总开关：false 时贴身不掉血（纯远程怪 / 中立怪 / 装饰物）。
## 只作用于"接触"这一条路径，投射物伤害与自身受击死亡不受影响。
@export var contact_damage_enabled: bool = true
## 贴身接触或近战命中玩家时造成的伤害值。
@export var contact_damage: int = 1
## 两次伤害玩家之间的冷却（秒），避免贴身时逐帧掉血；由 contact_damage_cooldown 计时。
@export var contact_cooldown: float = 0.8


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
## 绑定的领地（AuZone / EnemyZone）：玩家在领地内时本敌人开战，离开领地后还会再追一段。
## 留空则不通过领地触发（仍可由受击开战）。在检查器里从世界的 EnemyZones 选择对应领地。
@export var enemy_zone: NodePath = NodePath()
## 玩家离开领地后继续追击的时长（秒）：宽限期结束才收兵回巢，期间不再看领地条件。
## 0 = 立刻罢手（旧行为）。宽限期内同样不判 leash / 视线丢失 ——
## 领地常常比 leash 宽（level_1 的 EnemyZone3 有 1400px，Mosscreep 的 leash 只有 700），
## 若仍按 leash 判，玩家刚踏出领地就可能已经"追丢"，这段追击一秒都用不上。
## 优先级：领地宽限 > leash_range / combat_lose_time / 视线丢失（宽限期内全部短路）。
## 因此这是"时间预算"而不是"距离预算"：怪最多再追 zone_exit_chase_time × 追击速度 那么远。
@export var zone_exit_chase_time: float = 5.0

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
## 朝向死区（像素）：目标与自身的横向距离小于该值时**既不横移、也不翻面**。
## 必须与横移共用这一个阈值 —— 以前"朝向按死区不动、位移按导航方向照走"，
## 两者在玩家位于正上 / 正下方时给出相反答案，就是"walk 动画朝向反了"的根因。
## 判据统一由 EnemySteering.step_x() 裁决，各状态不要再自己算一遍。
@export var face_deadzone: float = 8.0
## 转身动作名：ActionAnimationPlayer 里的同名 clip。留空 = 关闭转身动画。
## 每次翻面（patrol 撞墙/悬崖/端点、chase 面朝目标、return 回巢）都会自动播一次，
## 播完自动回到当前状态声明的循环动作（move / idle）。敌人没配这个 clip 时行为与现在完全一致（瞬时翻面）。
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

## 抵达导航目标的判定距离（像素）：小于该值视为已到达并停止移动。
## 导航内部参数，默认值已够用，故不在检查器显示；确需调整时直接改 .tscn 即可。
@export_storage var nav_arrive_distance: float = 4.0

#endregion


#region 节点引用

@onready var collision_shape: CollisionShape2D = $BodyCollisionShape2D
@onready var drop_marker: Marker2D = $DropMarker
## 吐弹口：没有该子节点（纯近战怪）时为 null，发射时退化为自身中心。
@onready var muzzle := get_node_or_null("Muzzle") as Marker2D

## 受击无敌计时器：怪物被打中时 take_damage() 里设 invincible = true 并 hurt_invincibility_timer.start(invincible_time)，
## 超时由 _on_hurt_invincibility_timer_timeout() 把 invincible 改回 false。即"受击后短暂无敌、无法再被咬"的时长。
@onready var hurt_invincibility_timer: Timer = $Timer/hurt_invincibility_timer
## 接触伤害冷却计时器：怪物贴身/近战咬玩家的冷却，wait_time 在 _ready 里被设为
## contact_cooldown（默认 0.8s）。try_hit_player() 用 time_left > 0 当闸门防止逐帧掉血，
## 真正造成伤害的那一帧再 start() 重启冷却。与 hurt_invincibility_timer 方向相反：一个管"被咬"，一个管"咬人"。
@onready var contact_damage_cooldown: Timer = $Timer/contact_damage_cooldown

@onready var animated_sprite: AnimatedSprite2D = $Animation/EnemyAnimatedSprite
@onready var action_animation_player: AnimationPlayer = $Animation/ActionAnimationPlayer

@onready var debug: CharacterDebug = $Debug
@onready var state_machine: StateMachine = $StateMachine

## 寻路节点：飞行怪与陆地怪的追击都统一由此承接，绕开障碍/地形。
## 用 get_node_or_null 而不是 $路径：不靠导航移动的角色（BOSS 的位移由招式直接给 velocity）
## 可以在场景里省掉这个节点，不必为了满足基类路径而挂一个用不上的 NavigationAgent2D。
## 消费端 nav_velocity() 已有 null 兜底 —— 没有该节点时退化为直线趋近，而不是把角色钉在原地。
@onready var navigation_agent := get_node_or_null("NavigationAgent2D") as NavigationAgent2D

#endregion


#region 运行时状态

## 出生点：用于 return 状态归位与 leash 范围判定，_ready 时记录。
var spawn_position: Vector2 = Vector2.ZERO

## ---- 子系统 ----
## 三个子系统各自保管自己的状态，Enemy 上不再有对应的裸字段。
## 都必须在 _ready() 内、早于 state_machine.start() 调用 setup(self)。

## 转身 / 朝向表现（见 facing/enemy_facing.gd）。
var facing := EnemyFacing.new()
## 感知与仇恨：视线 / leash / 领地（见 aggro/enemy_aggro.gd）。
var aggro := EnemyAggro.new()
## 音效：子节点收集 + 衰减参数 + 镜头可见性（见 audio/enemy_audio.gd）。
var audio := EnemyAudio.new()

## 当前是否处于战斗（仇恨）状态。
## 代理到 aggro.combat_active：状态脚本读 enemy.combat_active 的调用面保持不变。
var combat_active: bool:
	get:
		return aggro.combat_active
	set(value):
		aggro.combat_active = value


var health: int
var move_direction: int = 1
var knockback: Vector2 = Vector2.ZERO
var dead: bool = false
var invincible: bool = false

var target: Node2D = null
var last_damage_from: Node2D = null

## Audio 子节点表：代理到 audio.nodes（EnemyState._play_audio 直接读它）。
var audio_nodes: Dictionary:
	get:
		return audio.nodes

## 玩家缓存：未开战时 target 为 null，若每次都扫 group 会每物理帧构造一个 Array。
## 只在引用失效（玩家换场景 / 关卡重开）时才重新扫描，其余时候直接命中。
var _player_cache: Node2D = null

## 接触判定的形状查询参数：复用同一实例，避免每物理帧新建对象与数组。
var _contact_query := PhysicsShapeQueryParameters2D.new()

#endregion


#region 生命周期

func _ready() -> void:
	# 收集 Audio 子节点 + 统一套用 2D 衰减参数。
	audio.setup(self)
	# 读素材基准朝向 + 接转身动画回调。必须早于任何翻面（state_machine.start() 会触发 enter()）。
	facing.setup(self)
	# 解析并绑定领地。同样早于 state_machine.start()。
	aggro.setup(self)

	health = mini(initial_health, max_health)
	debug.setup_health(max_health, health)

	spawn_position = global_position

	if contact_damage_cooldown != null:
		contact_damage_cooldown.wait_time = contact_cooldown

	_contact_query.collision_mask = Globals.LAYER_PLAYER
	_contact_query.collide_with_bodies = true
	_contact_query.collide_with_areas = false
	_contact_query.exclude = [self.get_rid()]

	if state_machine != null:
		state_machine.start()


## 逐物理帧的顺序契约。
## 三段的顺序**不能随便调**：领地宽限优先于战斗丢失判定（见 EnemyAggro.tick_combat 的
## 短路分支），转身兜底放在最后，保证同一帧内领地先决定收兵、转身再对齐画面朝向。
func _physics_process(delta: float) -> void:
	aggro.tick_zone_aggro()
	aggro.tick_exit_grace(delta)
	facing.tick(delta)


#endregion


#region 音效

## 收集 Audio 子节点、套用 2D 衰减参数、以及"此刻是否听得见"的判定，
## 全部实现在 audio/enemy_audio.gd，这里只做转发 —— 各状态脚本的调用面因此不变。

func is_audible() -> bool:
	return audio.is_audible()

#endregion


#region 运动与地形

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


#endregion


#region 朝向与转向

## ---- 横向裁决与施加：朝向 + 位移的唯一出口 ----
## 所有状态（chase / return / patrol …）都只提供"目标 x"，下面三个函数负责把目标 x
## 变成"朝哪 + 走哪"。判据只有一份（EnemySteering.step_x），所以朝向与位移不可能打架；
## 新增状态只要给出目标点即可，不必再复制一遍死区 / 踏空 / 翻面逻辑。

## 目标 x → 本帧横向步向（±1，0 = 站定）。deadzone <= 0 时沿用自身的 face_deadzone。
## 实现全部在 facing/enemy_facing.gd，这里只做转发 —— 各状态脚本的调用面因此不变。
func decide_step_x(target_x: float, deadzone: float = -1.0) -> int:
	return facing.decide_step_x(target_x, deadzone)


## 目标是否在朝向死区内：chase 用它区分"目标就在头顶"和"前方踏空"两种站定原因
## （前者不该累计放弃战斗的计时，后者才该）。阈值与 decide_step_x() 同源。
func is_within_face_deadzone(target_x: float, deadzone: float = -1.0) -> bool:
	return facing.is_within_face_deadzone(target_x, deadzone)


## 施加一步：翻面（含吐弹口 / 探测器 / 掉落点）+ 横移。step == 0 时站定且不翻面。
func apply_step(step: int, speed: float) -> void:
	facing.apply_step(step, speed)


## 只改朝向、不移动（站定吐弹 / 够不到目标的张望）。带死区，避免目标在正上方时原地抖动翻面。
func face_toward(target_x: float, deadzone: float = -1.0) -> void:
	facing.face_toward(target_x, deadzone)


## 按方向（±1）设置朝向，不移动。0 = 保持当前朝向。
func face_step(step: int) -> void:
	facing.face_step(step)


## 播放 ActionAnimationPlayer 里的动作：动画不存在（如某只怪没建 attack clip）时静默跳过，不刷错误。
## 实现全部在 facing/enemy_facing.gd，这里只做转发 —— 各状态脚本的调用面因此不变。
func _play_action(anim_name: StringName) -> void:
	facing.play_action(anim_name)

## 声明本状态"应当持续播放"的循环动作（move / idle），并立刻播放。
## 一次性演出（attack / hurt / death / appear / bury）请继续用 _play_action()，
## 它们不该成为转身动画的恢复目标。
func set_locomotion_clip(clip: StringName) -> void:
	facing.set_locomotion_clip(clip)


## ---- 翻面的子类扩展点 ----
## 翻面的完整流程（逻辑朝向翻转 → 本扩展点 → 画面朝向派生）在 EnemyFacing._flip_direction()，
## 它会回调到这里；子类（EnemyGround）只需重写本方法把探测器挂进来，不要自己搬流程。
## 画面朝向的派生、转身动画时序与 DEBUG 自检都在 facing/enemy_facing.gd。

func _flip_extra() -> void:
	# 吐弹口跟着朝向翻转（无 Muzzle 的怪为 null，直接跳过）。
	if muzzle != null:
		muzzle.position.x *= -1
		muzzle.reset_physics_interpolation()


## 画面朝向是否与 move_direction 一致（转身动画播放那 0.15s 按设计为 false）。
func is_facing_consistent() -> bool:
	return facing.is_facing_consistent()


#endregion


#region 伤害、死亡与掉落

func take_damage(amount: int, from: Node2D = null) -> void:
	if dead or invincible:
		return
	# 受击命中特效：谁被砍谁生成（场景由本节点配置决定，可按来源种类细分）。
	HitEffect.spawn(self, global_position, get_tree().current_scene,
			hit_effect_count_min, hit_effect_count_max, hit_effect_scatter, from)
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
	hurt_invincibility_timer.start(invincible_time)

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

func _on_hurt_invincibility_timer_timeout() -> void:
	invincible = false

#endregion


#region 感知、仇恨与领地

## 感知 / 仇恨 / 领地的全部状态与实现都在 aggro/enemy_aggro.gd，
## 这里只保留一行转发 —— 各状态脚本的调用面因此不变。

## 玩家是否在视线内（无遮挡）。use_line_of_sight = false 时恒为 true。
func has_line_of_sight() -> bool:
	return aggro.has_line_of_sight()

## 目标是否仍在牵引范围内（出生点 leash_range 内）。未开战时视为在范围内。
func is_within_leash() -> bool:
	return aggro.is_within_leash()

## 玩家此刻是否在本敌人绑定的领地里。没配领地 / 领地已失效时为 false。
func player_in_zone() -> bool:
	return aggro.player_in_zone()

## 推进战斗丢失计时：目标丢失 / 出 leash / 无视线时累计，达到 combat_lose_time 则丢战。
## 由 chase / attack 逐帧调用。
func tick_combat(delta: float) -> void:
	aggro.tick_combat(delta)

## 令本敌人开战。三个调用方：领地进入、接触命中、受击（经 _set_combat）。
func enter_combat_zone() -> void:
	aggro.enter_combat_zone()

## 设置战斗（仇恨）状态并广播 enter_combat / leave_combat。
## 状态与计时器存在 aggro 里，信号由宿主广播 —— 子系统不越过宿主发信号。
func _set_combat(active: bool) -> void:
	if not aggro.set_combat(active, get_player()):
		return
	if active:
		enter_combat.emit(target)
	else:
		leave_combat.emit()

#endregion


#region 导航、接触与投射物

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
	if dead or contact_damage_cooldown.time_left > 0.0:
		return false
	if from_contact and not contact_damage_enabled:
		return false
	var p := get_player()
	if p == null or not p.has_method("take_damage"):
		return false
	# 玩家正处在无敌帧（受击无敌 / 冲刺无敌）时既不结算伤害、也不刷新接触冷却，
	# 免得无敌帧刚结束就被贴身的怪立刻咬一口 —— 原来会白跑一次 contact_damage_cooldown。
	if p.has_method("is_damage_immune") and p.is_damage_immune():
		return false
	if not _body_overlaps_player(p):
		return false
	p.take_damage(contact_damage, self)
	contact_damage_cooldown.start()
	return true

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


#endregion


#region 检查器显隐

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
		"zone_exit_chase_time":
			# 没绑领地就没有"离开领地"这回事，宽限时长用不上。
			if enemy_zone.is_empty():
				property.usage = HIDDEN_BUT_SAVED

#endregion
