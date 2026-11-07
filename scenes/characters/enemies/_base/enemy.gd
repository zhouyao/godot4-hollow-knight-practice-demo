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

# ============================================================================
# 对外配置：在 enemy.tscn 中选中 Enemy 根节点时，Inspector 里能改的就是这一段。
# 逐项的 ## 文档注释会变成 Inspector 的悬浮提示，因此只写"作用 / 单位 / 取值约定"。
# 约定：
#   1. 只调默认值与文档注释，不要改属性名 —— 各敌人场景及 level_1.tscn 按名字显式存了
#      覆盖值（max_health、patrol_enabled、enemy_zone、corpse_* 等），改名会让值失联。
#      逐只调数值优先在 .tscn 里改；整类怪一起调才动脚本默认值或 tuning 预设。
#   2. 分组顺序 = Inspector 显示顺序：生命 → 运动介质 → 调参预设 → 移动 → 受击 →
#      接触伤害 → 巡逻 → 感知与仇恨 → 攻击 → 掉落 → 死亡 → 转身 → 音效 → 高级。
#      @export_group 一直作用到下一个 group，新增导出项要放进对应组，别插在组外。
#   3. 单位：距离 / 射程 / 半径一律像素，时间一律秒，衰减速率一律"每秒"；
#      只有 move_speed_units 是格，_ready 里乘 Globals.UNIT_SIZE 换成像素 / 秒
#      （同 player.gd 的对外配置约定：导出项默认值取不到 autoload）。
#   4. 三层取值（仅用于标了"< 0 沿用状态默认值"的行为数值，见 EnemyState._tuning()）：
#        tuning 预设（整类怪） > 本节点同名导出（逐只微调） > 状态节点 / 脚本默认值
#      负值 = 不覆盖、往下层要值；0 是合法覆盖值。tuning 里没有根节点同名导出的字段
#      （如 patrol_radius）会跳过中间层，直接落到状态默认值。生命、受击、感知、掉落、
#      死亡、转身、音效等导出项不参与这条链，改多少生效多少。
#   5. 用不上的项由 _validate_property() 自动从检查器收起（近战 / 远程、接触伤害、
#      掉落、屏幕外音效、领地宽限）。隐藏只影响显示，值仍会写进 .tscn。
#   6. 不在这段的配置：运动介质细节在 locomotion 资源；巡逻 / 追击 / 攻击 / 返回的
#      逐类默认数值在 StateMachine 的各状态节点上；音效与动作 clip 由 Audio 子节点、
#      ActionAnimationPlayer 的动画名决定。
# ============================================================================

## _validate_property() 用的"隐藏但仍序列化"标记：等价于 @export_storage，
## 保证被隐藏的参数值依然写进 .tscn，不会因为切换配置而丢失。
const HIDDEN_BUT_SAVED := PROPERTY_USAGE_NO_EDITOR | PROPERTY_USAGE_STORAGE

@export_group("存档")
## 唯一 ID：留空 = 普通杂兵，重新进关会刷新；
## 非空 = 一次性敌人（BOSS / 精英），击败后写入存档，读档时不再生成。
## 同一 ID 在全存档内只生效一次，BOSS 场景已各自填好。
@export var persistent_id: String = ""

@export_group("生命")
## 最大血量，同时也是血条上限。enemy.tscn 根节点已显式覆盖为 5（脚本默认 100）。
@export var max_health: int = 5
## 初始血量：出生时取 min(initial_health, max_health)，可用于让敌人残血出场。
@export var initial_health: int = 5

@export_group("运动介质")
## 运动模式：决定垂直方向怎么动、导航是否只取水平分量、死后尸体怎么处理（落地 / 下沉）。
## 换这一个资源就能把地面怪变成飞行怪 / 水下怪，无需改动任何状态代码。
## 三选一，均在 res://resources/characters/enemies/_shared/locomotion/：
##   ground.tres（默认）/ flying.tres / swimming.tres
## 资源在多只怪之间共享，只放整类参数，不要存逐敌人状态；见 enemy_locomotion.gd。
@export var locomotion: EnemyLocomotion = preload("res://resources/characters/enemies/_shared/locomotion/ground.tres")

@export_group("调参预设")
## 整类怪的行为数值预设：把巡逻 / 追击 / 攻击 / 返回共 18 个数值集中到一个 .tres，
## 一份资源给多只怪复用。留空（默认）= 完全沿用本节点导出与各状态节点的默认值。
## 只覆盖行为数值：生命、受击、感知、掉落、死亡、转身、音效等导出项不受影响。
## 18 个字段中只有 5 个（chase_speed_multiplier / melee_attack_range / shoot_range /
## attack_interval / shoot_keep_distance）在本节点有同名导出可逐只微调，
## 其余字段只能用 tuning 或状态节点覆盖。字段 -1 = 不覆盖，>= 0 才生效；
## 字段清单见 enemy_tuning.gd。注：当前还没有 EnemyTuning 的 .tres 实例，入口是预留的。
@export var tuning: EnemyTuning = null

## 运行期不变的两项解析结果，_ready 里算一次后缓存，状态侧只读这两个值：
## 基础移动速度、朝向死区每帧都被 chase / patrol 取用，走 _tuning() 的字符串反射太浪费。
## tuning_move_speed 覆盖的是换算后的像素 / 秒（不是 move_speed_units 的格数）。
## 注意 face_deadzone 目前不在 EnemyTuning 的字段表里，这一项的 tuning 层实际不生效，
## 生效的只有本节点 face_deadzone；保留同规则解析是为了日后加字段时不用改这里。
var tuning_move_speed: float = 0.0
var tuning_face_deadzone: float = 0.0

@export_group("移动")
## 基础移动速度（格 / 秒）：巡逻 / 追击 / 返回的所有倍率都乘以它。
## 导出格数而不是像素：导出项默认值取不到 autoload，写成像素就跟不上 UNIT_SIZE 调整。
## _ready 里换算成 move_speed（像素 / 秒）；tuning.move_speed >= 0 时覆盖换算后的值。
## 想整体调快调慢改这里（或 tuning.move_speed），只调某一种行为改对应状态的倍率。
@export var move_speed_units: float = 1.0
## 实际移动速度（像素 / 秒）：_ready 里由 move_speed_units 换算，非导出；状态机只读这个。
var move_speed: float
## 追击速度倍率（乘以 enemy.move_speed）：< 0 沿用 chase 状态节点的默认值（脚本里 1.0）。
## 走"tuning > 本项 > 状态默认值"链；逐只覆盖在世界场景里改这一项即可。
@export var chase_speed_multiplier: float = -1.0

@export_group("导航")
## 是否让 NavigationAgent2D 参与 nav_velocity() 的路径查询（默认关）。
## 当前各关卡的 NavigationPolygon 都是一整块凸四边形、没有按 Obstacles 挖洞，
## A* 给出来的就是"直线到目标"，开着没有任何绕障收益；节点与 NavigationRegion2D
## 都保留，等以后烘焙出带洞的导航网格再逐只 / 整类打开即可。
## 关掉时退化为直线趋近：飞行怪的绕障由 EnemyFlightNavigation 负责，贴地怪由
## WallDetector / LedgeDetector 负责，行为与现在等价。与 flight_avoidance_enabled
## 相互独立（后者只管飞行怪的射线避障）。
@export var use_navigation: bool = false

@export_group("飞行寻路")
## 全向怪（飞行 / 水下）的局部避障开关：关卡导航多边形常常是一整块大矩形，
## NavigationAgent2D 会给出穿过掩体的直线，本项打开后由 EnemyFlightNavigation
## 用前视射线绕开实体，并在玩家被掩体挡住时主动寻找有视线的射击位。贴地怪不受影响。
@export var flight_avoidance_enabled: bool = true
## 前视探测距离 = 本帧速度 × 本值（秒），再夹到 [96, 240] 像素。
## 太小会来不及转向、直接撞上平台；太大会在离掩体很远时就开始绕路。
@export_range(0.2, 2.0, 0.05) var flight_lookahead_time: float = 0.9
## 视线被挡时重新挑选射击位的间隔（秒）：0.25 秒一次足够跟上玩家移动，
## 又不会每物理帧做几十次物理查询。
@export_range(0.05, 1.0, 0.05) var flight_replan_interval: float = 0.25

@export_group("受击")
## 受击后的无敌帧时长（秒）：由 hurt_invincibility_timer 计时，期间不再结算伤害；
## 同时决定受击白闪时长，以及 hurt 状态没配 hold_time 时的硬直时长。
@export var invincible_time: float = 0.3
## 受击特效表：键为来源 get_damage_kind() 返回的 StringName，值为 PackedScene。
## 查表优先级：来源种类 > 约定键 &"slash"（玩家挥砍的默认表现）> _NAIL 通用刀光。
## 例：{&"slash": puff, &"fire": fire_spark}；解析见 hit_effect.gd。
@export var hit_effect_by_source: Dictionary = {
	&"slash": preload("res://scenes/effects/enemies/puff_hit_effect.tscn")
}
## 单次受击生成的特效数量下限（闭区间随机；min > max 时由 HitEffect.spawn 自动交换）。
@export_range(0, 24, 1, "or_greater") var hit_effect_count_min: int = 2
## 单次受击生成的特效数量上限，与下限一起决定每命中一次摇出的特效数量。
@export_range(0, 24, 1, "or_greater") var hit_effect_count_max: int = 4
## 多份特效在命中点周围的散布半径（像素），0 = 全部叠在同一点。
@export var hit_effect_scatter: float = 100.0

@export_group("接触伤害")
## 接触伤害总开关：false 时贴身不掉血、也不因贴身开战（纯远程怪 / 中立怪 / 装饰物）。
## 只作用于"接触"这一条路径：投射物伤害、受击开战与自身死亡不受影响。
## 关闭时 contact_damage / contact_cooldown 自动从检查器隐藏。
@export var contact_damage_enabled: bool = true
## 身体碰撞形状碰到玩家时造成的伤害值（见 try_hit_player）。
@export var contact_damage: int = 1
## 两次伤害玩家之间的冷却（秒）：由 contact_damage_cooldown 计时，避免贴身逐帧掉血。
## 玩家处于无敌帧时既不结算、也不刷新冷却，免得无敌刚结束就被咬一口。
@export var contact_cooldown: float = 0.8


@export_group("巡逻")
## 巡逻总开关：true（默认）= 出生后绕出生点 / 领地来回巡逻；false = 原地待机（站岗 / 悬停）。
## 关闭后仍可由领地 / 受击 / 接触进入战斗，战斗结束后经 resting_state() 回到 idle。
## 地面与飞行"怎么巡逻"的差异在各场景的 patrol 节点上，本开关无类型分支。
@export var patrol_enabled: bool = true

# ---- 以下是由配置派生的只读行为，不是配置项 ----
## 出生 / 战斗结束后的"驻留"状态：关巡逻＝idle，否则＝patrol。
## return / hurt 回流时统一走这里，避免把"关巡逻的怪"错误送回巡逻逻辑。
func resting_state() -> StringName:
	return EnemyStateNames.IDLE if not patrol_enabled else EnemyStateNames.PATROL

@export_group("感知与仇恨")
## 牵引（leash）半径（像素）：战斗中目标离出生点超过此距离即计入"丢失"计时，
## 累计满 combat_lose_time 才收兵回巢；玩家仍在绑定领地内时不参与此判定。
@export var leash_range: float = 700.0
## 丢失目标后多久放弃战斗（秒）：目标缺失 / 超出 leash / 失去视线任一成立即累计，
## 条件恢复则清零；领地追击宽限期内不累计（见 zone_exit_chase_time）。
@export var combat_lose_time: float = 10.0
## 视线丢失判定开关：true 时目标被地形挡住也计入"丢失"计时（与 leash 是"或"关系）；
## false 时只按目标是否存在 / 是否在 leash 内判定。
## 射线掩码由 locomotion.sight_mask 指定，为 0 时回落本节点的 collision_mask。
@export var use_line_of_sight: bool = true
## 绑定的领地（AuZone；旧名 EnemyZone 按同名信号兼容）：玩家进入领地时本敌人开战，
## 离开领地后再追 zone_exit_chase_time 秒。留空则不通过领地触发（仍可由受击开战）。
## 在世界场景里从 EnemyZones 下选对应领地节点；未绑领地时宽限项自动隐藏。
@export var enemy_zone: NodePath = NodePath()
## 玩家离开领地后继续追击的时长（秒）：0 = 立刻罢手。
## 宽限期内不判 leash / 视线丢失 —— 领地常比 leash 宽（level_1 的领地宽 1000 / 1200px，
## 而 leash 默认 700px），玩家刚踏出领地时往往已在 leash 之外。
## 优先级：领地宽限 > leash / 视线 / combat_lose_time；这是"时间预算"而非"距离预算"，
## 怪最多再追 zone_exit_chase_time × 追击速度 那么远。
@export var zone_exit_chase_time: float = 5.0

@export_group("攻击")
## 吐出的投射物场景：留空 = 纯近战怪，launch_projectile() 直接返回，不会报错。
## 配上即拥有吐弹能力，attack / chase 自动走远程分支。根节点必须是 Ammo 子类，
## 且允许 ENEMY 阵营使用（见 ammo.gd 的 usable_by），否则发射时会被拒绝。
## 可选场景（scenes/projectiles/）：projectile.tscn 单发 / projectile_spread.tscn 散射 /
## projectile_split.tscn 延迟分裂。本项始终可见，并决定下面攻击数值项的显隐。
@export var projectile_scene: PackedScene = null
## 近战触发距离（像素）：与目标距离小于该值即切到 attack。< 0 沿用 chase 节点默认值（64）。
## 仅纯近战怪使用；配了 projectile_scene 时本项自动隐藏。
@export var melee_attack_range: float = -1.0
## 投射物携带的伤害值（发射时传给弹药），与 contact_damage 相互独立；可为 0。
## 配了 projectile_scene 时才显示。
@export var projectile_damage: int = 1
## 远程射程（像素）：与目标直线距离小于该值才切到 attack 吐弹。
## < 0 沿用 chase 节点默认值（脚本 400；飞行场景覆盖为 500）。
@export var shoot_range: float = -1.0
## 两次攻击之间的冷却（秒）：远程吐弹与近战扑击共用。< 0 沿用 chase 节点默认值 1.5。
## 近战取值建议 >= contact_cooldown，否则会出现"扑击有声、实际没打到"的空洞反馈。
@export var attack_interval: float = -1.0
## 远程追击时与目标保持的水平距离（像素）：追到该距离内就停下吐弹。
## < 0 沿用 chase 节点默认值（脚本 140；飞行场景覆盖为 120）；0 = 贴脸，是合法覆盖值。
@export var shoot_keep_distance: float = -1.0

@export_group("掉落")
## 死亡时掷的掉落表：留空则不掉落，drop_scatter 自动隐藏。
## 建议做成 .tres 在多只怪之间复用（见 resources/drops/enemy_basic.tres）。
@export var drop_table: DropTable = null
## 掉落物相对 DropMarker 的散布半径（像素）：多个掉落物时铺开一点。
## DropMarker 随朝向翻转；默认 28 与 DropSpawner.spawn_table 的默认值一致。
@export var drop_scatter: float = 28.0

@export_group("死亡")
## 尸体保留时长（秒）：死亡后停留这么久才开始淡出。<= 0 = 尸体不消失、永久留场
## （crawlid / mosscreep / vengefly 均设为 -1）。
@export var corpse_lifetime: float = 3.0
## 尸体淡出时长（秒）：从完全不透明渐变到透明的耗时。<= 0 = 到点直接消失，不做渐变。
## 淡出改的是根节点 modulate，所有子节点一起变化；碰撞形状在 death 状态里会更早禁用。
@export var corpse_fade_time: float = 1.0
## 尸体纵向偏移（像素）：尸体落地 / 沉底后把精灵沿 y 轴挪动这么多，让不同素材贴合地面
## （正 = 向下，负 = 向上）。0 = 不偏移；由 death 状态只应用一次。
@export var corpse_y_offset: float = 0.0

@export_group("转身")
## 朝向死区（像素）：目标与自身的横向距离小于该值时既不横移、也不翻面。
## 必须与横移共用这一个阈值（判据统一由 EnemySteering.step_x() 裁决），
## 否则目标在正上 / 正下方时朝向与位移会给出相反答案，表现为 walk 动画朝向反了。
## decide_step_x / is_within_face_deadzone / face_toward 三处都从这一项取默认值。
@export var face_deadzone: float = 8.0
## 转身动作名：ActionAnimationPlayer 里的同名 clip。留空 / clip 不存在 = 关闭转身动画，
## 翻面瞬时完成。翻面时会尝试播一次，但要过三关：clip 存在、当前在播循环动作
## （move / idle）、距上次转身已满 turn_min_interval；播完自动回到循环动作。
## 见 enemy_facing.gd。
@export var turn_animation: StringName = &"turn"
## 两次转身动画之间的最小间隔（秒）：目标在死区边缘抖动时，防止把动画反复重放到卡顿。
@export var turn_min_interval: float = 0.2

@export_group("音效")
## 只在镜头内发声：true 时本敌人 Audio 下的所有音效（attack / hurt / death / walk …）
## 都要求自身位于当前镜头可视矩形内才播放；屏幕外很远就开打、吐弹的敌人不该出声。
## 置 false = 无条件播放（仍受 sfx_max_distance 距离衰减限制，且 sfx_screen_margin 自动隐藏）。
@export var sfx_only_on_screen: bool = true
## 可视矩形外扩（像素）：刚走出画面的敌人仍允许发声，避免声音在画面边缘被硬切。
## sfx_only_on_screen = false 时本项自动隐藏。
@export var sfx_screen_margin: float = 240.0
## 音效衰减到静音的距离（像素）：_ready 时写入本敌人所有 AudioStreamPlayer2D.max_distance。
## 引擎默认 2000 太远（本作 1 格 = 96 像素），隔着大半张地图的攻击声都听得见；
## 默认取略大于一屏半对角线（1920×1080 约 1100），保证画面内的声音不会提前闷掉。
@export var sfx_max_distance: float = 1400.0
## 衰减曲线指数：越大越"近处响、远处迅速变轻"，1 = 引擎默认。
@export_range(0.1, 6.0) var sfx_attenuation: float = 1.0

@export_group("高级")
## 击退的指数衰减速率（每秒），与物理帧率解耦：每帧乘子 = exp(-rate * delta)。
## 默认 30.65 ≈ 60Hz 下"每帧衰减 0.4"（保留 0.6）。
@export var knockback_decay_rate: float = 30.65
## 抵达导航目标的判定距离（像素）：小于该值视为已到达并停止移动，
## 同时用于 patrol 状态的端点判定。默认值已够用，故不在检查器显示（@export_storage）；
## 确需调整时直接改 .tscn 里的 nav_arrive_distance。
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

# 这一段全部不导出：由配置区的导出项在 _ready 换算，或由状态机逐帧维护。
# Inspector 里看不到；调手感请改配置区，别在这里直接改数值（同 player.gd 的"运行时量"约定）。

## 出生点：用于 return 状态归位与 leash 范围判定，_ready 时记录。
var spawn_position: Vector2 = Vector2.ZERO

## ---- 子系统 ----
## 各子系统自己保管自己的状态，Enemy 上不再有对应的裸字段。
## 都必须在 _ready() 内、早于 state_machine.start() 调用 setup(self)。

## 转身 / 朝向表现（见 facing/enemy_facing.gd）。
var facing := EnemyFacing.new()
## 感知与仇恨：视线 / leash / 领地（见 aggro/enemy_aggro.gd）。
var aggro := EnemyAggro.new()
## 音效：子节点收集 + 衰减参数 + 镜头可见性（见 audio/enemy_audio.gd）。
var audio := EnemyAudio.new()
## 全向怪的局部避障与射击位重定位（见 navigation/enemy_flight_navigation.gd）。
## 贴地怪只创建不调用：nav_velocity() 的全向分支会短路掉它。
var flight_nav := EnemyFlightNavigation.new()

## 当前是否处于战斗（仇恨）状态。
## 代理到 aggro.combat_active：状态脚本读 enemy.combat_active 的调用面保持不变。
var combat_active: bool:
	get:
		return aggro.combat_active
	set(value):
		aggro.combat_active = value


var health: int
## 场景里配置的原始血量：开发设置填 0（跟随关卡）时据此还原。
var _scene_max_health: int
var _scene_initial_health: int
## health 初始化完成后，运行中改设置才需要顺带刷新当前血量与血条上限。
var _health_initialized := false
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
	# 一次性敌人（BOSS / 精英）已击败：读档时直接不生成，也不启动状态机。
	if not persistent_id.is_empty() and SaveManager.is_defeated(persistent_id):
		queue_free()
		return

	# 格数 -> 像素：导出的是格数（move_speed_units），这里按 UNIT_SIZE 换算成实际像素速度。
	# 必须早于 state_machine.start()，否则首个状态 enter 时 move_speed 还是 0。
	move_speed = move_speed_units * Globals.UNIT_SIZE

	# tuning 覆盖里的两项"运行期不变"值，开战前先解析一次，省去每帧字符串反射。
	# 必须在 state_machine.start()（会触发首个状态 enter / update）之前算好。
	tuning_move_speed = _resolve_tuning_float(&"move_speed", move_speed)
	tuning_face_deadzone = _resolve_tuning_float(&"face_deadzone", face_deadzone)

	# 收集 Audio 子节点 + 统一套用 2D 衰减参数。
	audio.setup(self)
	# 读素材基准朝向 + 接转身动画回调。必须早于任何翻面（state_machine.start() 会触发 enter()）。
	facing.setup(self)
	# 解析并绑定领地。同样早于 state_machine.start()。
	aggro.setup(self)
	# 全向怪的避障需要碰撞形状 / 碰撞掩码，@onready 此时已就绪；
	# 同样必须早于状态机首帧（patrol 会立刻调 nav_velocity）。
	flight_nav.setup(self)

	# 开发设置可整体覆盖 BOSS / 小怪的出生血量：先记下场景原值，
	# 再让 health、血条上限、BOSS 阶段比例都基于覆盖后的值计算。
	_scene_max_health = max_health
	_scene_initial_health = initial_health
	_apply_health_override()

	health = mini(initial_health, max_health)
	_health_initialized = true
	debug.setup_health(max_health, health)

	# 调试模式与角色调试面板同源：开启时把 NavigationAgent2D 的 Debug 也打开。
	# 运行中在设置菜单切换会即时同步到在场敌人；后生成的敌人在这里读当前值。
	_sync_navigation_debug(Globals.debug_enabled)
	Globals.debug_enabled_changed.connect(_sync_navigation_debug)
	# 血量设置变化同样即时同步到在场敌人；连接到节点实例，销毁时自动断开。
	Globals.enemy_health_override_changed.connect(_apply_health_override)

	spawn_position = global_position

	if contact_damage_cooldown != null:
		contact_damage_cooldown.wait_time = contact_cooldown

	_contact_query.collision_mask = Globals.LAYER_PLAYER
	_contact_query.collide_with_bodies = true
	_contact_query.collide_with_areas = false
	_contact_query.exclude = [self.get_rid()]

	if state_machine != null:
		state_machine.start()


## 开发设置的出生血量覆盖：0 = 沿用关卡原值；> 0 = 该类敌人满血出生。
## 直接改写导出的 max_health / initial_health：血条上限、BOSS 阶段比例、
## dormant 的整场复位都读这两个属性，无需逐个同步。运行中改设置会把在场
## 敌人重置为满血，方便反复调试；未初始化或已死亡的敌人只改属性。
func _apply_health_override() -> void:
	var value := _health_override()
	if value > 0:
		max_health = value
		initial_health = value
	else:
		max_health = _scene_max_health
		initial_health = _scene_initial_health
	if not _health_initialized or dead:
		return
	health = mini(initial_health, max_health)
	debug.setup_health(max_health, health)


## 该类敌人当前应使用的覆盖值；Boss 子类重写为 boss_health_override。
func _health_override() -> int:
	return Globals.mob_health_override


## 解析单项 tuning 覆盖（tuning > 本节点同名导出 > fallback），与 EnemyState._tuning 同规则。
## 只用于 _ready 里"运行期不变"的两项，避免每帧走字符串反射（StringName 比较 + Variant 拆装箱）。
func _resolve_tuning_float(property: StringName, fallback: float) -> float:
	if tuning != null:
		var t: Variant = tuning.get(property)
		if t is float and t >= 0.0:
			return t
	var v: Variant = get(property)
	return float(v) if v is float and v >= 0.0 else fallback


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
	var dt := get_physics_process_delta_time()
	velocity += knockback
	knockback *= exp(-knockback_decay_rate * dt)
	# 地面常由多块矩形拼成，相邻块顶面差几像素就形成一道垂直面（moss_hole_0 的
	# MossFloor_06/07 差 5px）。move_and_slide() 不会自动上台阶，怪追出去之后
	# 回程会被这道面顶死，表现为 return 永远走不回出生点。
	# 只在上一帧确实撞到墙面时尝试抬升：平地行走不做形状查询，也不影响飞行 / 水下怪。
	if is_planar_mover() and _wall_blocked_last_frame():
		try_step_up(velocity.x)
	move_and_slide()


## 上一帧的 move_and_slide() 是否被垂直面挡过。法线的 x 分量为主即墙面，
## (0, -1) 这类地面法线不算 —— 否则平地上每帧都会被误判成"撞墙"。
func _wall_blocked_last_frame() -> bool:
	for i in range(get_slide_collision_count()):
		var k: KinematicCollision2D = get_slide_collision(i)
		if absf(k.get_normal().x) > 0.5:
			return true
	return false


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

## 低矮台阶抬升援助：横移被地形垂直面顶住时把身体抬高一点，让这一步能跨过去。
## 贴地怪（EnemyGround）重写；飞行 / 水下怪与没有地面探测的角色恒 false。
## 返回 true 表示本帧已抬升，调用方随后照常 move_and_slide()。
func try_step_up(_move_x: float) -> bool:
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

## 是否免疫玩家伤害：死亡 / 受击无敌帧，子类可再叠加"剧情锁定"（如 BOSS 沉睡、过场）。
## take_damage() 的首行守卫与玩家侧"这次命中是否生效"的判定共用本方法，
## 避免两处判据漂移 —— 伤害被挡下了，玩家却照样回能量 / 被反冲。
func is_invulnerable() -> bool:
	return dead or invincible


## 是否处于"剧情/过场锁定"（BOSS 沉睡、入场演出等）。基类默认 false，
## Boss 在基类按 cutscene_states 状态名统一实现（见 _base/boss.gd）。
## 玩家侧据此把攻击整体穿透 —— 连受击特效、能量、recoil 都不触发。
func is_cutscene_invulnerable() -> bool:
	return false


func take_damage(amount: int, from: Node2D = null) -> void:
	if is_invulnerable():
		return
	# 受击命中特效：谁被砍谁生成（场景由本节点配置决定，可按来源种类细分）。
	HitEffect.spawn(self, global_position, GameSession.content_root(),
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
	# 一次性敌人永久记录；普通杂兵 persistent_id 为空，不走这里，重进关卡照常刷新。
	if not persistent_id.is_empty():
		SaveManager.mark_defeated(persistent_id)
	_drop_loot()
	enemy_death.emit()
	_start_corpse_fade()

## 死亡后尸体的淡出清理：先停留 corpse_lifetime 秒，再用 corpse_fade_time 秒淡出并移除节点。
## 淡出改的是根节点 modulate，会沿画布层级传递给所有子节点（精灵、血条等）一起消失。
## 注意碰撞形状由 death 状态在尸体落地时就已禁用，淡出期间尸体不再挡路；
## 想让尸体更早消失把 corpse_lifetime 调小，<= 0 则永不消失。
func _start_corpse_fade() -> void:
	if corpse_lifetime <= 0.0:
		return
	var tween := create_tween()
	tween.tween_interval(corpse_lifetime)
	if corpse_fade_time > 0.0:
		tween.tween_property(self, "modulate:a", 0.0, corpse_fade_time)
	tween.tween_callback(queue_free)

## 死亡掉落：位置取 DropMarker（已随朝向翻转），交给 DropSpawner 统一生成。
## 挂在 _dead() 上，血量归零或被 kill() 时立即结算；death 动画 0.5s 方法轨道里的
## 第二次 _dead() 会被 dead 守卫挡掉，不会重复掉落。
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

## 开火判据：全向怪要求"整个身宽都看得见玩家"（三条平行射线），避免从掩体角
## 擦着中心线通过时站定吐空弹；贴地怪 / 未开避障的怪沿用单线 has_line_of_sight()。
## 与 tick_combat() 的丢战判据刻意不同：丢战仍按单线算，这样中心线擦边可见时
## 怪不会立刻收兵，而是继续绕到真正打得到人的位置。
func has_clear_shot() -> bool:
	if not use_line_of_sight:
		return true
	if is_planar_mover() or not flight_avoidance_enabled:
		return has_line_of_sight()
	var p := get_player()
	if p == null:
		return false
	return flight_nav.has_clear_shot(p.global_position)

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

## 调试模式 → NavigationAgent2D 的 Debug 开关（Inspector 里 Debug 分组的 Enabled）。
## 与 CharacterDebug 的血条 / 状态名共用 Globals.debug_enabled 一个入口：设置菜单选「开启」
## 时在场的敌人立即显示寻路路径，选「关闭」时一起关掉；后生成的敌人在 _ready 里读当前值。
## use_navigation 关闭时没有路径可画，一并关掉；没挂 NavigationAgent2D 的 BOSS 场景直接跳过。
func _sync_navigation_debug(enabled: bool) -> void:
	if navigation_agent != null:
		navigation_agent.debug_enabled = enabled and use_navigation


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

## 计算朝 target_pos 的本帧期望速度，由各状态调用并写回 enemy.velocity。
## speed：期望移动速度（像素/秒）。
## use_navigation 打开且挂了 NavigationAgent2D 时取下一个路径点；关闭 / 没节点 /
## 导航网格未烘焙时都退化为直线趋近，保证仍可移动。
## 是否只取水平分量由 locomotion.nav_planar_only 决定（见 is_planar_mover）。
## 全向怪额外过一道局部避障：关卡的导航多边形通常没按平台挖洞，直线路径会径直撞上
## 掩体，而 move_and_slide() 只会静默吃掉位移（见 navigation/enemy_flight_navigation.gd）。
func nav_velocity(target_pos: Vector2, speed: float) -> Vector2:
	if global_position.distance_to(target_pos) <= nav_arrive_distance:
		return Vector2.ZERO
	var next_pos := target_pos
	# use_navigation 关闭 / 没有 NavigationAgent2D 子节点时 next_pos 保持为目标点，
	# 退化为直线趋近，而不是返回零向量把怪钉在原地。
	if use_navigation and navigation_agent != null:
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
	if flight_avoidance_enabled:
		return flight_nav.steer(next_pos, speed)
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
	# 挂到当前区域：换关时弹幕随区域一起释放，不会残留到下一关
	GameSession.content_root().add_child(p)
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
## 当前规则（即配置区总述第 5 条）：
##   projectile_scene 决定显 melee_attack_range 还是显四个远程数值项；
##   contact_damage_enabled 管 contact_damage / contact_cooldown；
##   drop_table 管 drop_scatter；sfx_only_on_screen 管 sfx_screen_margin；
##   enemy_zone 管 zone_exit_chase_time；locomotion 管飞行寻路三项。
## 子类若要追加规则，重写后先调用 super._validate_property(property)（目前无子类重写）。
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
		"flight_avoidance_enabled", "flight_lookahead_time", "flight_replan_interval":
			# 只对全向怪（飞行 / 水下）有意义：贴地怪走 nav_velocity 的水平分支。
			if locomotion == null or locomotion.nav_planar_only:
				property.usage = HIDDEN_BUT_SAVED

#endregion
