extends BossState
class_name SoulMasterDashState

## 冲刺（dash）：快速俯冲落地 → 贴地蓄力 → 朝玩家水平方向高速突进 900 像素。
##
## 时间轴（秒，自 enter 起）：
##   0.0        起手：播 dash_start（clip 自带冲刺前的怒吼），朝正下方快速下坠
##   落地       吸附到地面线，把 dash_start 剩下的蓄力段播完（至少到 windup_time）
##   windup     切成 dash clip，重新锁定朝玩家的水平方向，贴地匀速突进
##   stop       累计位移 ≥ dash_distance / 前方有墙 / 前方是悬崖 → 立刻收招
##   收尾       浮回起手高度再回 idle（飞行 BOSS 停在泥里会很怪，与 quake 的升回同款）
##
## 三个必须落地的细节：
##   1. SoulMaster 是飞行 BOSS（idle 不会下落），冲刺前必须先自己砸到地面，
##      所以本状态第一段是下坠，而不是站着播前摇。
##   2. 身体是半径 142 的圆，基类 has_ground_ahead() 的探测器（19,3 / 15）太小，
##      墙 / 悬崖一律由本状态按自身半径外扩打射线判定。
##   3. 撞到玩家不打断冲刺（需求）：接触伤害交给 _tick_contact() 按冷却结算；
##      物理上 BOSS 的 collision_mask 只有地形层（4），本来也不会被玩家挡住。
##
## 相位全用计时器推进，不等 animation_finished（信号一断就卡死，与 quake / teleport 一致）。

const START_ANIM: StringName = &"dash_start"
const DASH_ANIM: StringName = &"dash"

enum _Phase { DROP, DASH, RISE }

@export_group("俯冲落地")
## 下坠速度（像素 / 秒）：SoulMaster 平时悬停，冲刺前先快速砸到地面。
@export var drop_speed: float = 2400.0
## 下坠兜底时长（秒）：脚下没有地面 / 落点异常时不至于一直往下飞。
@export var max_fall_time: float = 2.0
## 落地震屏强度（0 = 不震）。
@export var land_shake: float = 6.0

@export_group("蓄力")
## 起手到真正起冲的总时长（秒）。默认 0.8，对齐 dash_start clip 的怒吼方法轨道（0.7667s）：
## 玩家听到吼声的同时 BOSS 起冲。下坠耗时超出它时，落地即起冲。
@export var windup_time: float = 0.8

@export_group("冲刺")
## 冲刺速度（像素 / 秒）。
@export var dash_speed: float = 1500.0
## 单次冲刺距离（像素）。
@export var dash_distance: float = 900.0
## 冲刺兜底时长（秒）：位移没攒够（被地形卡住等）时也能收招。
@export var max_dash_time: float = 2.0
## 撞墙预判余量（像素）：在身体半宽之外再多探这么远。
@export var wall_probe_margin: float = 16.0
## 悬崖预判余量（像素）：从身体前缘再往外探这么远。
@export var ledge_probe_margin: float = 24.0
## 前方地面比脚下低多少算悬崖（像素）：小台阶直接贴地跟上，超过就收招。
@export var ledge_drop_tolerance: float = 80.0

@export_group("收招")
## 冲刺结束后是否浮回起手高度（飞行 BOSS 停在泥里会很怪）。
@export var float_back: bool = true
## 浮回速度（像素 / 秒）。
@export var rise_speed: float = 500.0
## 浮回兜底时长（秒）。
@export var max_rise_time: float = 2.0

var _phase := _Phase.DROP
var _timer := 0.0
var _dash_timer := 0.0
var _rise_timer := 0.0
var _travelled := 0.0
var _dir: int = 1
var _landed := false
## 落点（BOSS 原点目标高度）：地面顶部往上让出身体半高。
var _land_y := NAN
## 起手高度：收招阶段浮回这里。
var _hover_y := 0.0


func enter(_from: StringName) -> void:
	if boss == null:
		return
	boss.disable_melee_attack()
	boss.velocity = Vector2.ZERO
	_phase = _Phase.DROP
	_timer = 0.0
	_dash_timer = 0.0
	_rise_timer = 0.0
	_travelled = 0.0
	_landed = false
	_hover_y = boss.global_position.y
	_land_y = boss.ground_position_at(boss.global_position.x)
	_lock_direction()
	restart_action(START_ANIM)


func update(delta: float) -> void:
	if boss == null:
		return
	match _phase:
		_Phase.DROP:
			_drop_update(delta)
		_Phase.DASH:
			_dash_update(delta)
		_Phase.RISE:
			_rise_update(delta)


func exit(_to: StringName) -> void:
	if boss == null or not is_instance_valid(boss):
		return
	boss.velocity = Vector2.ZERO


# ---- 俯冲落地 ----

func _drop_update(delta: float) -> void:
	_timer += delta
	if not _landed:
		boss.velocity.x = 0.0
		boss.velocity.y = drop_speed
		boss._apply_movement()
		_tick_contact()
		# 落到目标高度 / 被地形提前接住 / 兜底超时 → 落地。
		if _reached_ground() or _timer >= max_fall_time:
			_land()
		return

	# 落地蓄力：站定，把 dash_start 的怒吼段播完再起冲。
	boss.velocity = Vector2.ZERO
	boss._apply_movement()
	_tick_contact()
	var p := boss.get_player()
	if p != null:
		boss.face_toward(p.global_position.x)
	if _timer >= windup_time:
		_begin_dash()


## 是否已经落到地面线：优先按算好的落点判，其次用物理接触兜底。
func _reached_ground() -> bool:
	if not is_nan(_land_y) and boss.global_position.y >= _land_y:
		return true
	return boss.is_on_floor()


func _land() -> void:
	if _landed:
		return
	_landed = true
	if not is_nan(_land_y):
		boss.global_position.y = _land_y
	boss.velocity = Vector2.ZERO
	if land_shake > 0.0:
		AuCameraDirector.shake(land_shake, 0.2)


# 落点高度统一由 Boss.ground_position_at(x) 提供（含领地底边兜底 / NAN 语义）。


# ---- 冲刺 ----

func _begin_dash() -> void:
	if _phase != _Phase.DROP:
		return
	_phase = _Phase.DASH
	_dash_timer = 0.0
	_travelled = 0.0
	# 起冲瞬间重新瞄准：蓄力期间玩家可能换了边。
	_lock_direction()
	boss.velocity.y = 0.0
	restart_action(DASH_ANIM)


func _dash_update(delta: float) -> void:
	_dash_timer += delta
	# 先判后走：前方是墙 / 悬崖就本帧收招，不迈出那一步。
	if _blocked_ahead():
		_finish()
		return

	boss.velocity.x = float(_dir) * dash_speed
	boss.velocity.y = 0.0
	var prev_x := boss.global_position.x
	boss._apply_movement()
	_travelled += absf(boss.global_position.x - prev_x)
	_stick_to_ground()
	# 身体突进：撞到玩家照常结算接触伤害，但**不**因此停下（需求明确要求穿过玩家）。
	_tick_contact()

	if boss.is_on_wall() or _travelled >= dash_distance or _dash_timer >= max_dash_time:
		_finish()


## 贴地滑行：每帧按脚下地面重新对齐 y。
## 大落差在往前一步之前就被 _ledge_ahead() 判成悬崖收招了，这里只处理小台阶 / 缓坡。
func _stick_to_ground() -> void:
	var ground := boss.ground_y_at(boss.global_position.x, NAN)
	if is_nan(ground):
		return
	boss.global_position.y = ground - boss.body_bottom()


## 锁定冲刺方向：朝玩家（±1）。起手时定一次用于面向，起冲瞬间再定一次用于真正瞄准。
func _lock_direction() -> void:
	var p := boss.get_player()
	var dx := 0.0
	if p != null:
		dx = p.global_position.x - boss.global_position.x
	if is_zero_approx(dx):
		_dir = boss.move_direction if boss.move_direction != 0 else 1
	else:
		_dir = 1 if dx > 0.0 else -1
	# 强制朝向冲刺方向：死区不该挡住这里（否则会出现背对玩家冲）。
	boss.face_step(_dir)


# ---- 前方阻挡（墙 / 悬崖） ----

## 前方墙 / 悬崖预判统一走 Boss.wall_in_direction() / Boss.ledge_ahead()，
## 判定实现只在基类留一份（身体半宽外扩 + 地形 mask + 大落差容差）。
func _blocked_ahead() -> bool:
	return boss.wall_in_direction(float(_dir), wall_probe_margin) \
			or boss.ledge_ahead(float(_dir), ledge_probe_margin, ledge_drop_tolerance)


# ---- 收招 ----

func _finish() -> void:
	if _phase == _Phase.RISE:
		return
	_phase = _Phase.RISE
	_rise_timer = 0.0
	boss.velocity = Vector2.ZERO
	# 冲上小台阶后已经比起手高度还高：不必再升，直接回决策。
	if not float_back or boss.global_position.y <= _hover_y:
		go_idle()


## 升回起手高度：飞行 BOSS 冲完停在泥里会很怪，浮回去再重新决策。
func _rise_update(delta: float) -> void:
	_rise_timer += delta
	boss.velocity.x = 0.0
	boss.velocity.y = -rise_speed
	boss._apply_movement()
	_tick_contact()
	if boss.global_position.y <= _hover_y:
		# 上升是逐帧步进的，最后一步必过冲几像素：吸回起手高度，位置与会话开始前一致。
		boss.global_position.y = _hover_y
		boss.velocity = Vector2.ZERO
		go_idle()
	elif _rise_timer >= max_rise_time:
		boss.velocity = Vector2.ZERO
		go_idle()


# 动作重播统一由 BossState.restart_action() 提供。
