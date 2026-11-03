extends BossState
class_name HollowKnightCounterState

## 招架反击：玩家进入近战范围时才被决策选出（由 idle 的硬门槛保证）。
## 单状态内部分四段相位（参考 dash.gd 的 _Phase 写法，不拆成多个状态节点）：
##   1) ANTIC   起手：播放 counter_anticipation，期间持续面向玩家（瞄准）；放完进 READY。
##   2) READY   招架窗口（COUNTER_WINDOW 秒）：锁定朝向（不再跟随玩家），开招架（boss.blocking=true），
##              循环播 counter_ready；期间受正面伤害 → boss 发 blocked → 转 BLOCK；
##              窗口结束仍无正面伤害 → 不播收尾 counter_end，直接回 idle 重新决策。
##   3) BLOCK   反击：关招架、播 counter_block、开近战命中盒 MELEE_OPEN 秒后关、播 counter_block 音；
##              动画放完转 END。
##   4) END     收尾：播 counter_end，放完回 idle 重新决策。
##
## “挡下伤害”由 Boss 的 blocking/blocked 完成，本状态只管听信号 + 接反击演出。


## 招架窗口时长（秒）= counter_ready 持续时长。
## 从 2.0 收到 0.8：2 秒窗口会让玩家只能"等 BOSS 站完"，节奏是断的；
## 0.8 秒仍保留"看招 → 格挡 → 反击"的辨识度，同时让"骗招 / 等收招"成为有效的玩家策略。
const COUNTER_WINDOW := 0.8
const MELEE_OPEN := 0.7        ## 反击命中盒开启时长（秒）

enum _Phase { ANTIC, READY, BLOCK, END }

var _phase := _Phase.ANTIC
var _window_timer: float = 0.0
var _melee_timer: float = 0.0
var _ap: AnimationPlayer = null


func enter(_from: StringName) -> void:
	if boss == null:
		return
	boss.disable_melee_attack()
	_phase = _Phase.ANTIC
	_window_timer = 0.0
	_melee_timer = 0.0
	_ap = boss.action_animation_player

	# 起手即面向玩家；后续 update 每帧持续面向玩家（招架全程跟随转向）。
	var p := boss.get_player()
	if p != null:
		boss.face_toward(p.global_position.x)

	if boss.blocked.is_connected(_on_blocked):
		boss.blocked.disconnect(_on_blocked)
	boss.blocked.connect(_on_blocked)
	if boss.guard_broken.is_connected(_on_guard_broken):
		boss.guard_broken.disconnect(_on_guard_broken)
	boss.guard_broken.connect(_on_guard_broken)

	if _ap != null and not _ap.animation_finished.is_connected(_on_anim_finished):
		_ap.animation_finished.connect(_on_anim_finished)
	play_action(&"counter_anticipation")


func update(delta: float) -> void:
	if boss == null:
		return
	# 招架全程站定（清水平速度），位移交给 _apply_movement。
	# 注意：通用行为放 match 之外，避免和下方相位专属分支重叠（match 只执行首个命中的分支）。
	boss.velocity.x = 0.0
	boss._apply_vertical_motion(delta)
	boss._apply_movement()
	match _phase:
		_Phase.ANTIC:
			# 前摇期间持续面向玩家（瞄准），便于起手对准。
			var p := boss.get_player()
			if p != null:
				boss.face_toward(p.global_position.x)
		_Phase.READY:
			# 招架窗口锁定朝向：不再跟随玩家，玩家绕到背后即破招（背击，_is_front_damage 为 false）。
			_window_timer += delta
			if _window_timer >= COUNTER_WINDOW:
				go_idle()
		_Phase.BLOCK:
			_melee_timer += delta
			if _melee_timer >= MELEE_OPEN:
				boss.disable_melee_attack()


func _on_anim_finished(anim_name: StringName) -> void:
	match anim_name:
		&"counter_anticipation":
			if _phase == _Phase.ANTIC:
				_enter_ready()
		&"counter_block":
			if _phase == _Phase.BLOCK:
				_enter_end()
		&"counter_end":
			if _phase == _Phase.END:
				go_idle()


func _enter_ready() -> void:
	_phase = _Phase.READY
	_window_timer = 0.0
	if boss != null:
		boss.blocking = true
	play_action(&"counter_ready")


func _on_blocked(_from: Node2D) -> void:
	if boss == null or _phase != _Phase.READY:
		return
	_enter_block()


func _on_guard_broken(_from: Node2D) -> void:
	if boss == null:
		return
	# 背刺破招：立刻解除招架，回 idle 重新决策（伤害已由 super.take_damage 结算）。
	go_idle()


func _enter_block() -> void:
	_phase = _Phase.BLOCK
	_melee_timer = 0.0
	if boss != null:
		boss.blocking = false         # 反击期间不再挡，正常结算
		boss.enable_melee_attack()     # 开命中盒，MELEE_OPEN 秒后由 update 关闭
		_play_audio(&"counter_block")  # Audio/counter_block 节点
	play_action(&"counter_block")


func _enter_end() -> void:
	if _phase == _Phase.END:
		return
	_phase = _Phase.END
	if boss != null:
		boss.blocking = false
		boss.disable_melee_attack()
	play_action(&"counter_end")


func exit(_to: StringName) -> void:
	if boss != null:
		boss.blocking = false
		boss.disable_melee_attack()
		if boss.blocked.is_connected(_on_blocked):
			boss.blocked.disconnect(_on_blocked)
		if boss.guard_broken.is_connected(_on_guard_broken):
			boss.guard_broken.disconnect(_on_guard_broken)
	if _ap != null and _ap.animation_finished.is_connected(_on_anim_finished):
		_ap.animation_finished.disconnect(_on_anim_finished)
