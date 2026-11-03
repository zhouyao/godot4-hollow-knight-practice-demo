class_name BossSoulMaster
extends Boss

## 过场锁定集：候场与入场演出期间不可被玩家攻击。
const CUTSCENE_STATES: Array[StringName] = [
	BossStateNames.DORMANT,
	BossStateNames.ENTRANCE,
]

const BGM_NODE := "BGM"

## 场景里配置的接触伤害开关。候场 / 演出期间会被临时关掉，演出结束按这个值还原，
## 避免"dormant 关掉 → entrance 又把它当默认值恢复成 false"。
var base_contact_damage: bool = true


func _ready() -> void:
	# 必须在 super._ready() 之前取值：状态机会在 _ready 内进场并关掉 contact_damage_enabled。
	base_contact_damage = contact_damage_enabled
	super._ready()
	# 击败即停 BGM：SoulMaster 场景目前没有 death 状态节点，
	# 停音乐不能等状态机收尾，直接挂在自己的死亡信号上。
	if not enemy_death.is_connected(_on_enemy_death_stop_bgm):
		enemy_death.connect(_on_enemy_death_stop_bgm)


## 所有"开战"请求的统一收口：只要还在候场，就先转成入场演出。
## begin_fight / 领地仇恨 / 受击 三条路径都经过这里，浮现演出不可能被跳过。
func enter_combat_zone() -> void:
	if state_machine != null \
			and state_machine.get_state_name() == BossStateNames.DORMANT \
			and state_machine.states.has(BossStateNames.ENTRANCE):
		state_machine.set_state(BossStateNames.ENTRANCE)
		return
	super.enter_combat_zone()


## 入场演出无敌判据。状态机未启动 / 状态名未知时按"锁定"处理：宁可多无敌，不可误伤。
func is_cutscene_invulnerable() -> bool:
	if state_machine == null or state_machine.current_state_name == &"":
		return true
	return state_machine.current_state_name in CUTSCENE_STATES


## 覆盖基类：受击无敌帧 / 死亡之外，再叠一层过场锁定。
## 玩家侧命中判定走的就是本方法，不用改玩家代码。
func is_invulnerable() -> bool:
	return super.is_invulnerable() or is_cutscene_invulnerable()


func _on_enemy_death_stop_bgm() -> void:
	var bgm := get_node_or_null(BGM_NODE) as AudioStreamPlayer2D
	if bgm != null and bgm.playing:
		bgm.stop()
