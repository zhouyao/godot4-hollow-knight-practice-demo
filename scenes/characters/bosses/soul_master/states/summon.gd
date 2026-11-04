extends BossState
class_name SoulMasterSummonState

## 召唤：四魂球环绕齐射。
##
## 时间轴（秒，自 enter 起）：
##   0.0   play summon_start，先瞬移到随机悬浮高度，再在 BOSS 上/下/左/右 60px 生成 4 枚魂球（0.2 倍凝聚）
##   0.5   起手结束 → play summon（循环），BOSS 以 drift_speed 朝「起手时的朝向」漂移
##   2.0   魂球脱离 BOSS，同帧收招回 idle
##   4.0   魂球自行销毁（状态早就不在了）
##
## 悬浮高度：飞行介质（flying.tres，hover_damping=0）存活期完全不管纵向，
## 所以每次施放都在 enter() 里以「地面顶部」为基准随机挑一个高度（height_min ~ height_max），
## 不在本状态里写 velocity.y —— 那是匀速一直飞，收招后还会带着走。
##
## 脱离后四颗球是**整组**行动：共用一个环绕中心与角速度，
## 一边扩大环绕半径（撒开），一边让这个原来的旋转中心向玩家靠近；
## 不是四颗各追各的（各自追踪会把队形打散成散弹）。
##
## 相位只用计时器推进，不等 animation_finished（信号一断就卡死，与 teleport / entrance 一致）。
## 位移直接写 velocity.x 交给 Enemy._apply_movement()，不走 _step_toward / apply_step
## （那套是给小怪追击用的朝向死区 + 踏空裁决）。

const START_ANIM: StringName = &"summon_start"
const DRIFT_ANIM: StringName = &"summon"

## 魂球场景：挂在 BOSS 的父节点上，状态收招后仍能独立飞完。
const ORB_SCENE: PackedScene = preload(
		"res://scenes/characters/bosses/soul_master/effects/boss_soul_orb.tscn")

@export_group("节奏")
## 没有 summon_start clip 时的起手兜底时长（秒）。
@export var start_fallback: float = 0.5
## 漂移时长（秒，从 summon 起播算起）。默认 1.5 → 收招与齐射同帧。
@export var drift_duration: float = 1.5

@export_group("漂移")
## 水平漂移速度（像素 / 秒）：设计值 moveSpeed=(0.75, 0) × 750 px/格 ≈ 562.5。
@export var drift_speed: float = 562.5

@export_group("悬浮高度")
## 每次施放随机挑选的悬浮高度区间（像素）：BOSS 原点到「该处地面顶部」的距离。
## min / max 写反会自动交换；两者相等 = 固定高度（不随机）。
@export var height_min: float = 300.0
@export var height_max: float = 650.0
## 高度再留的安全边距（像素）：结果会裁进 BossArena，避免顶到天顶或插进地里。
@export var height_margin: float = 40.0

@export_group("魂球")
## 四枚魂球的生成偏移（上 / 下 / 左 / 右，相对 BOSS 原点，像素）。
## 偏移长度即环绕半径；四颗一起公转，队形始终是十字环。
@export var orb_offsets: Array[Vector2] = [
	Vector2(0.0, -60.0), Vector2(0.0, 60.0), Vector2(-60.0, 0.0), Vector2(60.0, 0.0)]
## 魂球的最终视觉直径（像素）：100 ≈ 玩家身高（UNIT_SIZE=96）。
## 贴图 50px，按该值换算缩放（100 → 2 倍），判定圈同步换算。
@export var orb_diameter: float = 100.0
## 脱离后旋转中心靠近玩家的速度（像素 / 秒）。
@export var orb_speed: float = 750.0
## 每枚魂球的命中伤害。
@export var orb_damage: int = 1
## 脱离时刻（秒，自魂球生成起）。
@export var orb_detach_time: float = 2.0
## 销毁时刻（秒，自魂球生成起）。
@export var orb_lifetime: float = 4.0

var _timer := 0.0
var _start_length := 0.5
var _drift_dir := 1
var _drifting := false


func enter(_from: StringName) -> void:
	if boss == null:
		return
	boss.disable_melee_attack()
	boss.velocity = Vector2.ZERO
	_timer = 0.0
	_drifting = false
	_start_length = maxf(anim_length(START_ANIM, start_fallback), 0.01)

	# 高度先定：魂球按 BOSS 当前位置生成，晚于本句就会按旧高度摆出来。
	_randomize_height()

	# 先看玩家再锁定漂移方向：整段不翻面，避免「朝左漂移同时朝右看」。
	var p := boss.get_player()
	if p != null:
		boss.face_toward(p.global_position.x)
	_drift_dir = boss.move_direction if boss.move_direction != 0 else 1

	play_action(START_ANIM)
	_spawn_orbs()


func update(delta: float) -> void:
	if boss == null:
		return
	_timer += delta

	# 起手演完才进移动段：summon_start 是「生成魂球」，summon 才是「移动」。
	if not _drifting and _timer >= _start_length:
		_drifting = true
		play_action(DRIFT_ANIM)

	boss.velocity.x = float(_drift_dir) * drift_speed if _drifting else 0.0
	# 本状态重写了 update()，走不到 EnemyState.update()：垂直运动 / 位移 / 接触伤害都要自己来。
	boss._apply_vertical_motion(delta)
	boss._apply_movement()
	_tick_contact()

	if _timer >= _start_length + drift_duration:
		go_idle()


func exit(_to: StringName) -> void:
	# 收招 / 被打断都清水平速度，避免把漂移惯性带给 idle。
	if boss != null:
		boss.velocity = Vector2.ZERO


## 随机悬浮高度：基准是「脚下地面顶部的世界 y」（与 quake 的落点判定同一套射线），
## 抬升 height_min ~ height_max 后瞬移过去；没地面就退回领地底边，两者都没有则不动。
## 位置瞬变，必须重置插值，否则首帧会从旧高度滑过来。
func _randomize_height() -> void:
	if boss == null:
		return
	var lo := minf(height_min, height_max)
	var hi := maxf(height_min, height_max)
	var ground_y := boss.ground_y_at(boss.global_position.x, NAN)
	var arena := boss.arena_rect()
	if is_nan(ground_y):
		if arena.size.y <= 0.0:
			return
		ground_y = arena.end.y          # 没有地面：拿领地底边当基准
	var target_y := ground_y - randf_range(lo, hi)
	if arena.size.y > 0.0:
		var top := arena.position.y + height_margin
		var bottom := arena.end.y - height_margin
		if bottom > top:
			target_y = clampf(target_y, top, bottom)
	# 位置瞬变 + 所有子节点插值重置，统一走 Boss.teleport_to()。
	boss.teleport_to(Vector2(boss.global_position.x, target_y))


## 生成四枚魂球：挂在 BOSS 的父节点上（与 teleport_trail 同一套路）——
## 挂 BOSS 身上会继承位移 / 翻面 / modulate，齐射轨迹会被一路拖着走。
func _spawn_orbs() -> void:
	for i in orb_offsets.size():
		# 与 BOSS 同层：同 z 下后加入的兄弟节点画在 BOSS 之上，四球始终看得见。
		var orb := boss.spawn_attached_fx(ORB_SCENE, boss.global_position) as BossSoulOrb
		if orb == null:
			continue
		# 尺寸按像素直径配置（重复设置不累乘）：内部会同步重算判定圈，
		# 因此放在入树之后也不会与 _ready() 的首次换算冲突。
		orb.set_visual_diameter(orb_diameter)
		orb.detach_time = orb_detach_time
		orb.lifetime = orb_lifetime
		orb.homing_speed = orb_speed
		orb.summon(boss, orb_offsets[i], orb_damage)
