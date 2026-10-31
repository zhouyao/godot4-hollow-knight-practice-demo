class_name Boss
extends Enemy


## 击败演出开始时发出（BOSS 专有）。
## 与 Enemy.enemy_death 的分工：enemy_death 负责"状态机转 defeat"，
## 本信号负责对外（存档标记 / 解锁 / 转场）。
signal boss_defeated
## 阶段切换时发出，参数为新阶段的索引（0 起）。
signal phase_changed(phase_index: int)

## 当前阶段索引，0 起。
var phase_index: int = 0


func _ready() -> void:
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
