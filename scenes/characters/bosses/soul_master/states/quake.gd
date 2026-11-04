extends BossState
class_name SoulMasterQuakeState

## 下砸冲击波（quake）：瞬移到玩家头顶 → 悬停起手 → 高速下坠 → 落地 AoE + 左右各 waves_per_side 道贴地冲击波。
##
## 时间轴（秒，自 enter 起）：
##   0.0           起手：锁定玩家此刻的 x，把 BOSS 挪到其头顶 air_height（默认 500）像素处，播 quake_air
##   hover_time    悬停结束（默认 1.0，与 quake_air clip 里施法音的方法轨道对齐）：
##                 切成 quake_down 俯冲姿态，给向下初速，之后纯重力加速
##   落地          重播 quake_down clip（clip 自带的落地特效 + 地面音效正好从 t=0 起效），
##                 对落点下方 slam_radius 内的玩家结算 slam_damage，
##                 并从落点同帧向左右各发 waves_per_side 道贴地冲击波（effects/quake_effect.tscn）：
##                 速度按 wave_speed_falloff 逐道递减，靠速度差在飞行中自行拉开成梯队
##   recover_time  落地硬直（够落地特效播完、玩家看清冲击波）
##   升回          以 rise_speed 浮回起手前的悬停高度，然后回 idle
##
## 相位全部用计时器 + 落点高度推进，不等 animation_finished（信号链一断就卡死，与 teleport / summon 一致）。
## 落点在起手瞬间锁定、悬停期间不再跟随玩家：那 1 秒悬停就是玩家的躲避窗口。
## 整招关闭接触伤害，伤害只在「下砸」与「冲击波」两处结算 —— 下坠时穿过玩家不会多算一次。

const AIR_ANIM: StringName = &"quake_air"
const DOWN_ANIM: StringName = &"quake_down"

## 冲击波场景：挂在 BOSS 的父节点上，收招后仍能自己飞完 6 秒。
const WAVE_SCENE: PackedScene = preload(
		"res://scenes/characters/bosses/soul_master/effects/quake_effect.tscn")

enum _Phase { HOVER, FALL, RECOVER, RISE }

@export_group("起手")
## 悬停高度（像素）：BOSS 原点位于玩家原点之上多少像素。500 ≈ 5 个玩家身高（UNIT_SIZE=96）。
@export var air_height: float = 500.0
## 悬停时长（秒）：到点开始下坠。默认 1.0，与 quake_air clip 的施法音轨道对齐。
@export var hover_time: float = 1.0

@export_group("下落")
## 下坠重力（像素 / 秒²）。
@export var gravity: float = 3600.0
## 下坠初速（像素 / 秒）：给一点初速让「快速下落」更跟手。
@export var fall_initial_speed: float = 700.0
## 无地面 / 落点异常时的下坠兜底时长（秒）。
@export var max_fall_time: float = 3.0

@export_group("落点伤害")
## 落点下方的水平判定半径（像素）。
@export var slam_radius: float = 260.0
## 对玩家造成的伤害。
@export var slam_damage: int = 1

@export_group("冲击波")
## 每边发放的冲击波道数：1 = 左右各一道（旧行为），3 = 每边三道。
@export_range(1, 4, 1) var waves_per_side: int = 1
## 同边相邻两道的速度倍率：第 i 道速度 = wave_speed * wave_speed_falloff^i。
## 所有波落地同帧、同点生成，靠这个速度差在飞行中自行拉开成梯队；<1 = 越靠后越慢。
## 建议 0.6~0.75：太接近 1 会长时间叠在一起，太小则慢波在 wave_lifetime 内飞不出场地。
@export var wave_speed_falloff: float = 0.7
## 每道冲击波的伤害。
@export var wave_damage: int = 1
## 冲击波水平速度（像素 / 秒）。
@export var wave_speed: float = 520.0
## 冲击波存活时长（秒）：到点消失。
@export var wave_lifetime: float = 6.0
## 冲击波原点距地面线的高度（像素）。默认 0 = 原点正好落在地面上
## （特效内部会把每一帧贴图的底部对齐到原点，所以波底就是贴地的）。
@export var wave_ground_offset: float = 0.0

@export_group("收招")
## 落地后硬直（秒）。
@export var recover_time: float = 0.9
## 收招后浮回悬停高度的上升速度（像素 / 秒）。
@export var rise_speed: float = 400.0
## 升回阶段的兜底时长（秒）：悬停高度异常（被击退 / 场景改动）时不至于一直往上飞。
@export var max_rise_time: float = 2.5
## 落地震屏强度（0 = 不震）。
@export var shake_strength: float = 14.0

var _phase := _Phase.HOVER
var _timer := 0.0
var _fall_timer := 0.0
var _recover_timer := 0.0
var _rise_timer := 0.0
## 落点（世界坐标）：起手锁定 x，下坠开始时同步成实际下坠的 x；_landing_y 是 BOSS 原点目标高度。
var _landing_x := 0.0
var _landing_y := NAN
## 起手前的悬停高度：升回阶段用它复位，避免每放一次下砸就永久矮一截。
var _hover_y := 0.0


func enter(_from: StringName) -> void:
	if boss == null:
		return
	boss.disable_melee_attack()
	boss.velocity = Vector2.ZERO
	# 整招关闭接触伤害：伤害只由下砸 + 冲击波结算，下坠时穿过玩家不会再多扣一次。
	boss.contact_damage_enabled = false
	_phase = _Phase.HOVER
	_timer = 0.0
	_fall_timer = 0.0
	_recover_timer = 0.0
	_hover_y = boss.global_position.y
	_landing_x = boss.global_position.x
	_landing_y = NAN
	_teleport_above_player()
	play_action(AIR_ANIM)


func update(delta: float) -> void:
	if boss == null:
		return
	match _phase:
		_Phase.HOVER:
			_hover_update(delta)
		_Phase.FALL:
			_fall_update(delta)
		_Phase.RECOVER:
			_recover_update(delta)
		_Phase.RISE:
			_rise_update(delta)


func exit(_to: StringName) -> void:
	if boss == null or not is_instance_valid(boss):
		return
	boss.velocity = Vector2.ZERO
	# 按 Boss 上记录的"设计值"还原：dormant / entrance 也会改它，不能直接还原成 true。
	boss.restore_contact_damage()


# ---- 起手 ----

## 挪到玩家头顶：落点 x 锁死在玩家此刻的位置（悬停期间不跟随），y 抬高 air_height。
## 位置是瞬变的，所以要把 BOSS 与所有 Node2D 子节点的物理插值一起重置，否则首帧会从旧位置滑过来。
func _teleport_above_player() -> void:
	var p := boss.get_player()
	var x := boss.global_position.x
	var top_y := boss.global_position.y - air_height
	if p != null:
		x = _clamp_to_arena(p.global_position.x)
		top_y = p.global_position.y - air_height
		boss.face_toward(p.global_position.x)
	else:
		push_warning("SoulMaster quake: 找不到玩家，改为原地起手")
	_landing_x = x
	# 位置瞬变 + 全部子节点插值重置，统一走 Boss.teleport_to()。
	boss.teleport_to(Vector2(x, top_y))


## 把落点 x 收进领地：玩家贴着场地边缘时，BOSS 不会悬在墙外砸下去。
func _clamp_to_arena(x: float) -> float:
	var arena := boss.arena_rect()
	if arena.size.x <= 0.0:
		return x
	var half := boss.body_bottom()
	if arena.size.x <= half * 2.0:
		return arena.get_center().x
	return clampf(x, arena.position.x + half, arena.end.x - half)


# ---- 悬停 ----

func _hover_update(delta: float) -> void:
	# 悬停：站定，不给纵向速度（飞行介质本来就不会施加重力）。
	boss.velocity.x = 0.0
	boss.velocity.y = 0.0
	boss._apply_movement()
	_timer += delta
	if _timer >= hover_time:
		_begin_fall()


# ---- 下落 ----

func _begin_fall() -> void:
	_phase = _Phase.FALL
	_fall_timer = 0.0
	# 用"真正开始下坠时的 x"做落点：悬停期间被击退 / 被挤开也不会砸在空处。
	_landing_x = boss.global_position.x
	_landing_y = boss.ground_position_at(_landing_x)
	boss.velocity = Vector2(0.0, fall_initial_speed)
	_use_fall_pose()


## 下坠姿态：只切精灵的逐帧动画，**不**播 quake_down clip。
## 那个 clip 在 t=0 就打开落地特效、地面音效（本来就是给"落地瞬间"用的），
## 起手就播会让冲击波提前在脚下炸开；落地时再 restart_action(DOWN_ANIM) 重新起播。
func _use_fall_pose() -> void:
	var ap := boss.action_animation_player
	if ap != null:
		ap.stop()
	if boss.animated_sprite != null:
		boss.animated_sprite.animation = DOWN_ANIM
		boss.animated_sprite.play()


func _fall_update(delta: float) -> void:
	boss.velocity.x = 0.0
	boss.velocity.y += gravity * delta
	boss._apply_movement()
	_fall_timer += delta
	# 落到目标高度即判落地；is_on_floor 兜住"提前被地形接住"，max_fall_time 兜住"脚下没有地"。
	if not is_nan(_landing_y) and boss.global_position.y >= _landing_y:
		boss.global_position.y = _landing_y
		_land()
	elif boss.is_on_floor() or _fall_timer >= max_fall_time:
		_land()


# 落点 y 统一由 Boss.ground_position_at(x) 提供（含领地底边兜底 / NAN 语义）。


# ---- 落地 ----

func _land() -> void:
	if _phase == _Phase.RECOVER:
		return
	_phase = _Phase.RECOVER
	_recover_timer = 0.0
	boss.velocity = Vector2.ZERO
	_landing_x = boss.global_position.x
	# 落地这一帧重播 quake_down：clip 里的落地特效与地面音效都从 t=0 起效，正好对上撞击。
	restart_action(DOWN_ANIM)
	# 水平 AoE 统一走 Boss.damage_in_radius（只判水平距离，来源传 boss）。
	boss.damage_in_radius(_landing_x, slam_radius, slam_damage)
	_spawn_waves()
	if shake_strength > 0.0:
		AuCameraDirector.shake(shake_strength, 0.3)


## 以落点为中心，贴着地面向左右各发 waves_per_side 道冲击波。挂在 BOSS 的父节点上：
## 挂 BOSS 身上会继承它的位移 / 翻面 / modulate，收招后也留不住。
func _spawn_waves() -> void:
	var x := _landing_x
	var ground_y := boss.global_position.y + boss.body_bottom()
	for dir in [-1, 1]:
		var speed_scale := 1.0
		for _i in range(waves_per_side):
			# 全部同帧、同点生成，不引入延迟计时器：速度逐道递减，飞行中自行拉开。
			_spawn_wave(dir, x, ground_y, speed_scale)
			speed_scale *= wave_speed_falloff


func _spawn_wave(dir: int, x: float, ground_y: float, speed_scale: float) -> void:
	# 与 BOSS 同层：同 z 下后加入的兄弟节点画在 BOSS 之上，冲击波不会被身体盖住。
	var wave := boss.spawn_attached_fx(
			WAVE_SCENE, Vector2(x, ground_y - wave_ground_offset)) as SoulMasterQuakeWave
	if wave == null:
		return
	wave.launch(dir, wave_damage, wave_lifetime, wave_speed * speed_scale, boss)


# ---- 收招 ----

func _recover_update(delta: float) -> void:
	boss.velocity.x = 0.0
	boss.velocity.y = 0.0
	boss._apply_movement()
	_recover_timer += delta
	if _recover_timer >= recover_time:
		_phase = _Phase.RISE
		_rise_timer = 0.0
		boss.velocity = Vector2(0.0, -rise_speed)


## 升回起手前的悬停高度：飞行 BOSS 砸完停在泥里会很怪，浮回去再重新决策。
func _rise_update(delta: float) -> void:
	_rise_timer += delta
	boss.velocity.x = 0.0
	boss.velocity.y = -rise_speed
	boss._apply_movement()
	if boss.global_position.y <= _hover_y:
		# 上升是逐帧步进的，最后一步必过冲几像素：直接吸回悬停高度，位置与会话开始前一致。
		boss.global_position.y = _hover_y
		boss.velocity.y = 0.0
		go_idle()
	elif _rise_timer >= max_rise_time:
		boss.velocity.y = 0.0
		go_idle()
