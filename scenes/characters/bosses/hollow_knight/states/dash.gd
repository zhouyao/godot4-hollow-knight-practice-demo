extends BossState
class_name HollowKnightDashState

## 冲刺技能（Hollow Knight 的突进位移）。
## 单状态内部分三段，靠 _phase 推进，不拆成多个状态节点：
##   1) ANTIC   前摇：播放 dash_anticipation，锁定冲刺方向（朝玩家），原地蓄力；
##   2) DASH    冲刺中：播放 dash，朝锁定方向匀速位移，累计位移；目标距离按"发动时到玩家的距离"
##                    自适应（冲到刚好越过玩家一点即收），途中前方有墙或探测到悬崖（前方无地）则提前停下。
##   3) RECOVER 后摇：播放 dash_recover，站定硬直，时间到回 idle（给玩家反击窗口）。
##
## 相位推进用「动画时长计时器」而非 animation_finished 信号：信号链路一旦因任何原因
## 没触发（连接/命名/并发重播），就会卡死在前摇；计时器与动画播放解耦，必定能完整跑完三段。
##
## 伤害走 BOSS 既有的“身体接触伤害”（boss.try_hit_player，带冷却），更贴合“冲过去撞人”的手感，
## 不启用 slash 用的近战命中盒。位移直接写 velocity.x 交给 Enemy._apply_movement，
## 符合 BossState 基类“招式不用 _step_toward/apply_step”的约定。

# ---- 可调参数 ----
@export var dash_speed: float = 1200.0          ## 冲刺速度（像素 / 秒）
@export var max_dash_distance: float = 1000.0    ## 单次冲刺最大距离（像素）
@export var deals_contact_damage: bool = true   ## 冲刺中是否用身体接触结算伤害
@export var antic_fallback_time: float = 1.4    ## 无 dash_anticipation 动画时的前摇兜底时长（秒）
@export var recover_fallback_time: float = 0.8  ## 无 dash_recover 动画时的后摇兜底时长（秒）

enum _Phase { ANTIC, DASH, RECOVER }

var _phase := _Phase.ANTIC
var _dir: int = 1
var _distance_travelled: float = 0.0
var _target_distance: float = 0.0
var _antic_timer: float = 0.0
var _recover_timer: float = 0.0
var _antic_length: float = 1.4
var _recover_length: float = 0.8


func enter(_from: StringName) -> void:
	if boss == null:
		return
	boss.disable_melee_attack()

	_phase = _Phase.ANTIC
	_distance_travelled = 0.0
	_antic_timer = 0.0
	_recover_timer = 0.0

	var ap := boss.action_animation_player
	_antic_length = _anim_length(ap, &"dash_anticipation", antic_fallback_time)
	_recover_length = _anim_length(ap, &"dash_recover", recover_fallback_time)

	# 锁定冲刺方向：朝玩家（cast 时定死，玩家中途闪避不改向）。
	var p := boss.get_player()
	var target_x := boss.global_position.x
	var dx := 0.0
	if p != null:
		target_x = p.global_position.x
		dx = target_x - boss.global_position.x
	_dir = 1 if dx >= 0.0 else -1
	if is_zero_approx(dx):
		_dir = boss.move_direction
	# 强制朝向冲刺方向（commit 时不应被死区挡住翻面，否则会出现"背对玩家冲"的朝向错位）。
	boss.face_step(_dir)

	_target_distance = max_dash_distance

	if ap != null and ap.has_animation(&"dash_anticipation"):
		ap.play(&"dash_anticipation")


func update(delta: float) -> void:
	if boss == null:
		return
	match _phase:
		_Phase.ANTIC:
			boss.velocity.x = 0.0
			boss._apply_vertical_motion(delta)
			boss._apply_movement()
			# 前摇按动画时长计时；放完即进冲刺，不依赖 animation_finished 信号。
			_antic_timer += delta
			if _antic_timer >= _antic_length:
				_begin_dash()
		_Phase.DASH:
			_dash_update(delta)
		_Phase.RECOVER:
			boss.velocity.x = 0.0
			boss._apply_vertical_motion(delta)
			boss._apply_movement()
			# 后摇按动画时长计时；时间到回 idle。
			_recover_timer += delta
			if _recover_timer >= _recover_length and machine != null:
				machine.set_state(BossStateNames.IDLE)


func exit(_to: StringName) -> void:
	if boss != null:
		boss.velocity.x = 0.0


## 冲刺本体一帧：先预判悬崖（前方无地就停，别冲下坑），再给速度、位移、累计距离，
## 撞墙或冲满 900 则停。即提前停止只有两种：前方有墙、前方是悬崖。
func _dash_update(delta: float) -> void:
	# 前方是悬崖：本帧就收，不迈出那一步。
	boss.ledge_detector.force_raycast_update()
	if !boss.ledge_detector.is_colliding():
		_begin_recover()
		return

	boss.velocity.x = float(_dir) * dash_speed
	boss._apply_vertical_motion(delta)
	var prev_x := boss.global_position.x
	boss._apply_movement()
	_distance_travelled += absf(boss.global_position.x - prev_x)

	# 身体突进：撞到玩家即结算接触伤害（带冷却，不会逐帧掉血）。
	if deals_contact_damage:
		_tick_contact()

	# 停止条件：1) 前方有墙（撞墙）即停；2) 冲满本次目标距离即停。
	# 注意：悬崖已在每帧开头由 ledge_detector 单独判定（见上方），此处不再重复。
	if boss.is_on_wall():
		_begin_recover()
	elif _distance_travelled >= _target_distance:
		_begin_recover()


func _begin_dash() -> void:
	if _phase != _Phase.ANTIC:
		return
	_phase = _Phase.DASH
	_distance_travelled = 0.0
	var ap := boss.action_animation_player if boss != null else null
	if ap != null and ap.has_animation(&"dash"):
		ap.play(&"dash")


func _begin_recover() -> void:
	if _phase != _Phase.DASH:
		return
	_phase = _Phase.RECOVER
	_recover_timer = 0.0
	if boss != null:
		boss.velocity.x = 0.0
	var ap := boss.action_animation_player if boss != null else null
	if ap != null and ap.has_animation(&"dash_recover"):
		ap.play(&"dash_recover")


## 取动画时长，取不到就用兜底值（保证相位推进不被缺动画卡住）。
func _anim_length(ap: AnimationPlayer, anim_name: StringName, fallback: float) -> float:
	if ap != null and ap.has_animation(anim_name):
		return ap.get_animation(anim_name).length
	return fallback
