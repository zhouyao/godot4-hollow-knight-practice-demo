class_name BossSoulMaster
extends Boss

## 过场锁定集（候场 / 入场演出）在 _ready() 里填给 Boss.cutscene_states，
## 判定由 Boss 基类统一实现。

const BGM_NODE := "BGM"

## 施法音效：Audio/cast0-3 四个播放器，分别对应 cast_0-3.ogg。
const CAST_SFX_NODES: Array[String] = [
	"Audio/cast0",
	"Audio/cast1",
	"Audio/cast2",
	"Audio/cast3",
]

## 愤怒音效：Audio/angry0-6 七个播放器，分别对应 angry_0-6.ogg。
const ANGRY_SFX_NODES: Array[String] = [
	"Audio/angry0",
	"Audio/angry1",
	"Audio/angry2",
	"Audio/angry3",
	"Audio/angry4",
	"Audio/angry5",
	"Audio/angry6",
]

@export_group("闪现")
## 闪现落点区域（世界坐标 Rect2，x/y 是左上角，w/h 是宽高）。
## 留空（宽或高为 0）= 由 teleport 状态按 BossArena 自动取领地的 2/3 并居中。
## 这是 BOSS 根节点的导出属性，关卡里选中 SoulMaster 实例即可直接覆写，
## 改位置不必打开 boss 场景；状态机还会把它裁进领地，保证落点始终在领域内。
@export var teleport_area: Rect2 = Rect2()

## 接触伤害的设计值已上提到 Boss.base_contact_damage（在 Boss._ready() 里记录），
## 演出结束统一调 boss.restore_contact_damage() 还原。


func _ready() -> void:
	# 必须在 super._ready() 之前填：Enemy._ready() 会启动状态机并立刻进 dormant。
	cutscene_states = [BossStateNames.DORMANT, BossStateNames.ENTRANCE]
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
		# 本分支不调 super，激活信号要在这里补发：雾门靠它在演出第一帧就关门。
		notify_boss_activated()
		state_machine.set_state(BossStateNames.ENTRANCE)
		return
	super.enter_combat_zone()


## is_cutscene_invulnerable() / is_invulnerable() 由 Boss 基类统一实现，
## 玩家侧 player.gd 的挥砍命中与 take_damage() 共用同一份判据。


## 随机播放一段施法音效：从 Audio/cast0-3 里抽一个播放器（cast_0-3.ogg 各一份）。
## 节点缺失或 stream 为空时静默跳过，不打断状态机；场景没配 stream 时按路径兜底。
func play_random_cast_sound() -> void:
	var index := randi_range(0, CAST_SFX_NODES.size() - 1)
	var sfx := get_node_or_null(CAST_SFX_NODES[index]) as AudioStreamPlayer2D
	if sfx != null and sfx.stream != null:
		sfx.play()


## 随机播放一段愤怒音效：从 Audio/angry0-6 里抽一个播放器（angry_0-6.ogg 各一份）。
## 节点缺失或 stream 为空时静默跳过，不打断状态机。
func play_random_angry_sound() -> void:
	var index := randi_range(0, ANGRY_SFX_NODES.size() - 1)
	var sfx := get_node_or_null(ANGRY_SFX_NODES[index]) as AudioStreamPlayer2D
	if sfx == null or sfx.stream == null:
		return
	# 抽到同一个播放器时 play() 不会从头重播，先 stop 再播。
	sfx.stop()
	sfx.play()


func _on_enemy_death_stop_bgm() -> void:
	var bgm := get_node_or_null(BGM_NODE) as AudioStreamPlayer2D
	if bgm != null and bgm.playing:
		bgm.stop()
