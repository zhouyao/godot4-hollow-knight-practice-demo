class_name Boss
extends Enemy


## BOSS 基类：在 Enemy 之上补一层"战斗流程"，不碰小怪的巡逻 / 追击 / 仇恨那套。
##
## 为什么继承 Enemy 而不是另起炉灶：
##   · 血量 / 无敌帧 / 受击特效 / 动作动画播放器 / 音频 / 朝向 / 掉落 —— BOSS 全都要，语义一致；
##   · 小怪的形态差异已由 EnemyLocomotion 承担、朝向由 EnemySteering 承担、
##     仇恨由 EnemyAggro 承担，Enemy 本体剩下的就是"可被攻击的角色"这一层；
##   · player.gd 用 `is Enemy` 判定挥砍目标，继承即可零改动。
##
## BOSS 与小怪的差异全部落在本文件与场景里，都不需要改基类：
##   · 受击霸体：状态机里不建 hurt 节点，take_damage() 的 states.has(HURT) 落空，
##     直接走"扣血 → 无敌帧"，不会进硬直状态（见 enemy.gd 的 take_damage）。
##   · 击败演出：覆写 _start_corpse_fade() 为空，改由 defeat 状态接管。
##   · 仇恨惰性：不绑 enemy_zone、不建 chase / attack 状态，
##     EnemyAggro 的两个逐帧 tick 都不会生效，因此不需要替换成 BossAggro。
##   · 位移自检：招式直接写 velocity.x（不走 apply_step 的死区 / 踏空裁决），
##     故 facing.check_displacement 置 false。
##
## 场景：boss.tscn 自建节点树，**不继承 enemy.tscn** —— 复用代码而不复用节点树，
## 因为 BOSS 需要 SlashHitBox / BossArena / 招式计时器等一整套小怪没有的节点，
## 而继承能白拿的那几个（Timer / Animation / Audio / Debug）手工重建成本很低。

## 击败演出开始时发出（BOSS 专有）。
## 与 Enemy.enemy_death 的分工：enemy_death 负责"状态机转 defeat"，
## 本信号负责对外（存档标记 / 解锁 / 转场）。
signal boss_defeated
## 阶段切换时发出，参数为新阶段的索引（0 起）。
signal phase_changed(phase_index: int)
## 入场演出播完、招式调度即将开始时发出。关卡侧可据此切战斗 BGM。
signal intro_finished


@export_group("BOSS")
## 阶段血量阈值：血量 <= thresholds[i] 时进入第 i + 1 阶段（索引从 0 起）。
## 留空 = 单阶段。例：[100] 表示血量降到 100 时进二阶段。
## TODO: 后续换成 BossPhase 资源数组，把招式池 / 速度倍率 / 入场动画一起带进来。
@export var phase_health_thresholds: Array[int] = []


@onready var arena: BossArena = get_node_or_null("BossArena") as BossArena
## 特效层精灵：counter 闪光这类"贴在 BOSS 身上、需要等播完"的常驻特效。
## 一次性特效（粒子 / 刀光）请沿用项目的 spawn 范式（HitEffect / nail_hit_spark），
## 挂在场景根而不是 BOSS 身上，免得淡出时还跟着 BOSS 跑。
@onready var effect_animated_sprite := get_node_or_null("Effects/EffectAnimatedSprite") as AnimatedSprite2D

## 当前阶段索引，0 起。
var phase_index: int = 0


func _ready() -> void:
	# BOSS 的位移由招式直接给定 velocity.x，不走 apply_step() 那套"朝向与位移同源"的裁决
	# （后撤步 evade 就是面朝玩家、往反方向走）。关掉对应的 DEBUG 位移自检，避免刷误报。
	facing.check_displacement = false
	super._ready()


## 驻留状态：BOSS 不巡逻，沉睡 / 待机即 dormant。
## EnemyAggro.tick_zone_aggro() 会拿它比对当前状态；BOSS 没绑领地时那条路径本就不生效，
## 这里给出正确值是为了将来"用领地触发开战"时语义一致。
func resting_state() -> StringName:
	return BossStateNames.DORMANT


## 开战入口：由 BossArena 在玩家踏入时调用，或由入场动画的方法轨道在演出结束时调用。
## 走 Enemy 现成的仇恨广播（enter_combat_zone → _set_combat → enter_combat 信号），
## 关卡侧监听 enter_combat 即可切 BGM / 锁门 / 亮血条 —— 与领地开战是同一条路径。
func begin_fight() -> void:
	if dead or combat_active:
		return
	enter_combat_zone()


## 阶段推进：血量跨过阈值就进下一阶段。由 combat 状态每次决策前调用。
## 取"已满足的最高阶段"，所以玩家一口气打掉大量血也不会漏阶段。
func check_phase() -> void:
	if phase_health_thresholds.is_empty():
		return
	var next := phase_index
	for i in phase_health_thresholds.size():
		if health <= phase_health_thresholds[i]:
			next = maxi(next, i + 1)
	if next != phase_index:
		start_phase(next)


func start_phase(index: int) -> void:
	if index == phase_index:
		return
	phase_index = index
	phase_changed.emit(index)


## 击败：先走基类的死亡结算（掉奖励、发 enemy_death → 状态机转 defeat），
## 再广播 BOSS 专有的 boss_defeated 供存档 / 解锁 / 转场监听。
func _dead() -> void:
	super._dead()
	boss_defeated.emit()


## BOSS 不做尸体淡出。
## _dead() 里的 _start_corpse_fade() 会在 corpse_lifetime 秒后把节点 queue_free 掉，
## 那会打断击败演出（动画没播完、信号没发完）。演出与清理全部交给 defeat 状态。
func _start_corpse_fade() -> void:
	pass
