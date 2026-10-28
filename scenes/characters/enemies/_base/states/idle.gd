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

@export var arrive_animation: StringName = &""
@export var emerge_animation: StringName = &""

var _intro_t: float = 0.0
var _intro_is_arrive: bool = false
var _emerge_played: bool = false

func enter(from: StringName) -> void:
	_intro_t = 0.0
	_emerge_played = false
	if from == EnemyStateNames.RETURN and arrive_animation != &"":
		_intro_is_arrive = true
		_play_intro(arrive_animation)
	else:
		_intro_is_arrive = false
		_play_action(EnemyStateNames.IDLE)

func update(delta: float) -> void:
	_stop()
	if _intro_t > 0.0:
		_intro_t -= delta
		# 进场（bury）放完 → 回到 idle 循环；离场（appear）放完由 get_transition 放行 chase。
		if _intro_t <= 0.0 and _intro_is_arrive:
			_play_action(EnemyStateNames.IDLE)

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
		if _intro_t > 0.0:
			return &""  # appear 播放中，继续等
		_emerge_played = true
		_intro_is_arrive = false
		_play_intro(emerge_animation)
		return &""
	if _intro_t > 0.0:
		return &""  # appear 播放中，继续等
	return EnemyStateNames.CHASE

## 播一次性演出动画，并把它的实际时长记进 _intro_t 用于计时（不依赖信号）。
func _play_intro(anim: StringName) -> void:
	var ap := enemy.action_animation_player
	if ap != null and ap.has_animation(anim):
		_intro_t = ap.get_animation(anim).length
	else:
		_intro_t = 0.0
	_play_action(anim)
