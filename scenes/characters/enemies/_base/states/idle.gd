extends EnemyState
class_name EnemyIdleState


## 待机状态：patrol_enabled = false 时怪物出生后直接进入本状态，原地站岗 / 悬停。
##
## 进场 / 离场演出（可选，逐只怪在检查器配）：
##   arrive_animation：从 return 回流抵达后先播（如 mosscreep 的 bury 缩回地面），播完自动回到 idle 循环。
##   emerge_animation ：从本状态开战（发现玩家）先播（如 mosscreep 的 appear 钻出），播完再切 chase。
## 两者都留空即为最朴素的"原地播 idle"，对所有巡逻关闭的怪通用。
##
## 介质（水下怪出水）判断只在"未开战"时生效——与 patrol 的优先级一致：开战时由
## chase 状态自行处理离介质回巢，idle 不必抢这个优先级。
##
## 演出收尾统一用 AnimationPlayer 的 animation_finished 信号，不再另起一个按 delta 的倒计时：
## 两套时钟（物理帧倒计时 vs 动画时钟）会赛跑，偶尔把演出截断一帧（"起身最急"的观感），
## 而且状态越多、这类并行计时器越多，竞态越难查。

@export var arrive_animation: StringName = &""
@export var emerge_animation: StringName = &""

## 正在播的一次性演出（arrive / emerge）：播完之前不放行 chase。
var _performing: StringName = &""
var _is_arrive: bool = false
var _emerge_played: bool = false
## 兜底计时：演出被 hurt / death 抢占导致收不到 animation_finished 时，
## 用它放行，避免状态机被永久卡死（信号丢失不该等于状态机停摆）。
var _perform_watchdog: float = 0.0

func enter(from: StringName) -> void:
	_emerge_played = false
	_performing = &""
	_perform_watchdog = 0.0
	_connect_anim(true)
	if from == EnemyStateNames.RETURN and arrive_animation != &"":
		_is_arrive = true
		_play_intro(arrive_animation)
	else:
		_is_arrive = false
		# 声明循环动作：转身动画播完要恢复到它（见 Enemy.set_locomotion_clip）。
		enemy.set_locomotion_clip(EnemyStateNames.IDLE)

func exit(_to: StringName) -> void:
	_connect_anim(false)

func update(delta: float) -> void:
	_stop()
	if _performing != &"":
		_perform_watchdog -= delta
		if _perform_watchdog <= 0.0:
			_on_perform_finished(_performing)  # 信号丢失时的兜底

func get_transition(_delta: float) -> StringName:
	if not enemy.combat_active:
		_emerge_played = false
		# 离介质（水下怪被诱出水面）：未开战时先回巢；开战时交给战斗逻辑，不再单独判。
		if not enemy.is_in_medium() \
				and enemy.state_machine != null \
				and enemy.state_machine.states.has(EnemyStateNames.RETURN):
			return EnemyStateNames.RETURN
		return &""
	# 已开战：配了 emerge 就先播 appear（期间原地不动），播完才切 chase。
	if emerge_animation != &"" and not _emerge_played:
		if _performing != &"":
			return &""
		_emerge_played = true
		_is_arrive = false
		_play_intro(emerge_animation)
		return &""
	if _performing != &"":
		return &""  # 演出播放中，继续等
	return EnemyStateNames.CHASE

## 播一次性演出。收尾靠 animation_finished，不再按 delta 倒计（见文件头说明）。
func _play_intro(anim: StringName) -> void:
	var ap := enemy.action_animation_player
	if ap == null or not ap.has_animation(anim):
		return
	_performing = anim
	_perform_watchdog = ap.get_animation(anim).length + 0.5
	_play_action(anim)

func _on_perform_finished(anim_name: StringName) -> void:
	if anim_name != _performing:
		return
	_performing = &""
	_perform_watchdog = 0.0
	# 进场（bury）放完 → 回到 idle 循环；离场（appear）放完由 get_transition 放行 chase。
	if _is_arrive:
		_is_arrive = false
		enemy.set_locomotion_clip(EnemyStateNames.IDLE)

func _on_action_animation_finished(anim_name: StringName) -> void:
	_on_perform_finished(anim_name)

## 只在 idle 期间监听：退出即断连，避免别的动作播完误触发本状态的收尾逻辑。
func _connect_anim(on: bool) -> void:
	var ap := enemy.action_animation_player if enemy != null else null
	if ap == null:
		return
	if on:
		if not ap.animation_finished.is_connected(_on_action_animation_finished):
			ap.animation_finished.connect(_on_action_animation_finished)
	elif ap.animation_finished.is_connected(_on_action_animation_finished):
		ap.animation_finished.disconnect(_on_action_animation_finished)
