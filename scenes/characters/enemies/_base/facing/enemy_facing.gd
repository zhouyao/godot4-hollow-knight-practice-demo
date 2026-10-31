class_name EnemyFacing
extends RefCounted


## 敌人转身与画面朝向的全部状态与实现。
##
## 原先整块堆在 Enemy 里（约 220 行），现在作为"表现层"整体搬到这里；
## Enemy 只保留一行转发（见 Enemy.apply_step / face_step / set_locomotion_clip …），
## 因此 8 个状态脚本（chase / patrol / return …）的调用面完全不变。
##
## 为什么是 RefCounted 对象而不是子节点：
##   · 转身超时兜底与领地计时之间存在**顺序依赖**（见 Enemy._physics_process 的注释）。
##     拆成多个节点后，执行顺序由树序隐式决定，极易踩坑；保留对象后，顺序由
##     Enemy._physics_process() 显式写出来，读代码的人一眼就能看到。
##   · 不往 .tscn 里塞节点，检查器里也不会多出一堆和美术无关的东西。
##   · 反向持有 Enemy 不会造成引用环：Enemy 是 Node，不参与引用计数。
##
## 横向裁决本身仍在 EnemySteering.step_x()（纯函数，有单测覆盖），
## 这里只负责"采集输入 + 施加结果"。

## 转身表现状态：正在播放 / 上次播放时刻（毫秒，负值 = 从未播放过）。
## 不再有"攒下的翻面次数"：画面朝向一律由 move_direction 派生（见 _sync_facing），
## 转身期间翻几次都不影响最终结果，所以不需要记账；少一个计数器就少一处会算错的地方。
var turning: bool = false
var last_ms: int = -1000000
## DEBUG 自检：画面朝向 / 逻辑朝向 / 实际位移 三者不一致的持续时长（秒）。负值 = 当前一致。
var mismatch_t: float = -1.0
## 自检是否校验"位移方向 == 朝向"。
## 默认 true：小怪的位移与朝向同源（都由 EnemySteering.step_x 裁决），两者相反一定是 bug。
## 需要"面朝一边、往另一边走"的角色置 false —— BOSS 的后撤步（evade）正是面朝玩家、
## 朝反方向位移，那是刻意的手感，不是 bug（见 Boss._ready）。
var check_displacement: bool = true
## 素材基准朝向：+1 = 原画朝右，-1 = 原画朝左（如 crawlid）。
## setup() 时从精灵在场景里预置的 scale.x 符号读一次，之后画面朝向一律由
## 「base_sign × move_direction」派生，不再做 scale.x *= -1 的累乘。
var base_sign: float = 1.0
## 当前"应当持续播放"的循环动作（move / idle），由状态通过 set_locomotion_clip() 声明。
## 转身动画结束后恢复到它 —— 不再从 AnimationPlayer.current_animation 反推：
## 那会把 appear（钻出地面）/ bury（缩回）这类一次性演出记成恢复目标，转身播完再演一遍。
var locomotion_clip: StringName = &"idle"

## 宿主敌人。Enemy 是 Node、不参与引用计数，所以
## 「Enemy 持有 facing、facing 持有 Enemy」不构成引用环（已实测通过解析与运行）。
var _enemy: Enemy


## 绑定宿主：读一次素材基准朝向，并接上转身动画需要的两个回调。
## 必须在**任何翻面发生之前**调用（Enemy._ready() 里早于 state_machine.start()）。
func setup(enemy: Enemy) -> void:
	_enemy = enemy
	# 素材基准朝向 = 场景里预置的 scale.x 符号（crawlid 这类原画朝左的怪是 -1）。
	base_sign = signf(enemy.animated_sprite.scale.x)
	var player := enemy.action_animation_player
	if player == null:
		return
	if not player.animation_finished.is_connected(_on_action_animation_finished):
		player.animation_finished.connect(_on_action_animation_finished)
	if not player.animation_changed.is_connected(_on_action_animation_changed):
		player.animation_changed.connect(_on_action_animation_changed)


## ---- 横向裁决与施加：朝向 + 位移的唯一出口 ----
## 所有状态（chase / return / patrol …）都只提供"目标 x"，下面几个函数负责把目标 x
## 变成"朝哪 + 走哪"。判据只有一份（EnemySteering.step_x），所以朝向与位移不可能打架；
## 新增状态只要给出目标点即可，不必再复制一遍死区 / 踏空 / 翻面逻辑。

## 目标 x → 本帧横向步向（±1，0 = 站定）。deadzone <= 0 时沿用敌人的 face_deadzone，
## 状态可用 _tuning() 解析出的值覆盖（EnemyState._deadzone()）。
## 本函数只做"采集输入"，裁决规则本身在 EnemySteering.step_x()（纯函数，有单测覆盖）。
func decide_step_x(target_x: float, deadzone: float = -1.0) -> int:
	var limit := _deadzone(deadzone)
	var dx := target_x - _enemy.global_position.x
	var planar := _enemy.is_planar_mover()
	var ground_ahead := true
	# 探测只对"已经过了死区的候选方向"做：死区内反正要站定，不必查询。
	if planar and absf(dx) > limit:
		ground_ahead = _enemy.has_ground_ahead(float(1 if dx > 0.0 else -1))
	return EnemySteering.step_x(_enemy.global_position.x, target_x, limit, planar, ground_ahead)


## 目标是否在朝向死区内：chase 用它区分"目标就在头顶"和"前方踏空"两种站定原因
## （前者不该累计放弃战斗的计时，后者才该）。阈值与 decide_step_x() 同源。
func is_within_face_deadzone(target_x: float, deadzone: float = -1.0) -> bool:
	return absf(target_x - _enemy.global_position.x) <= _deadzone(deadzone)


## 施加一步：翻面（含吐弹口 / 探测器 / 掉落点）+ 横移。step == 0 时站定且不翻面。
## 这里是"朝向"与"位移"唯一的共同出口 —— 两者同源，不可能出现倒着走。
func apply_step(step: int, speed: float) -> void:
	if step != 0 and step != _enemy.move_direction:
		_flip_direction()
	# 转身动画期间画面仍停在旧朝向（turn 素材自己画 180° 旋转，必须等播完再翻）。
	# 此时若继续按新方向全速位移，看到的就是"朝着旧方向倒着走" ——
	# 玩家从 mosscreep 头顶跳过（强制一次转身）时最明显；来回横跳时更是长时间保持反向。
	# 所以转身时站定：动画一结束即恢复移动，绝不出现位移与画面朝向相反的画面。
	if turning:
		_enemy.velocity.x = 0.0
		return
	_enemy.velocity.x = float(step) * speed


## 只改朝向、不移动（站定吐弹 / 够不到目标的张望）。带死区，避免目标在正上方时原地抖动翻面。
func face_toward(target_x: float, deadzone: float = -1.0) -> void:
	var limit := _deadzone(deadzone)
	var dx := target_x - _enemy.global_position.x
	if absf(dx) <= limit:
		return
	face_step(1 if dx > 0.0 else -1)


## 按方向（±1）设置朝向，不移动。0 = 保持当前朝向。
func face_step(step: int) -> void:
	if step != 0 and step != _enemy.move_direction:
		_flip_direction()


## 播放 ActionAnimationPlayer 里的动作：动画不存在（如某只怪没建 attack clip）时静默跳过，不刷错误。
## 各状态通过 EnemyState._play_action() 转发到这里 —— 实现只有一份，免得两处各自演化。
func play_action(anim_name: StringName) -> void:
	var player := _enemy.action_animation_player
	if player == null or not player.has_animation(anim_name):
		return
	player.play(anim_name)


## 声明本状态"应当持续播放"的循环动作（move / idle），并立刻播放。
## 一次性演出（attack / hurt / death / appear / bury）请继续用 play_action()，
## 它们不该成为转身动画的恢复目标。
func set_locomotion_clip(clip: StringName) -> void:
	locomotion_clip = clip
	play_action(clip)


## ---- 翻面：逻辑朝向与画面朝向 ----

## 左右换向：逻辑朝向（move_direction，+1 = 向右）立刻翻转，
## 掉落点、以及子类挂在 _flip_extra() 上的探测器 / 吐弹口也跟着立刻翻（它们只影响逻辑）；
## 接触判定用的是身体碰撞形状（居中对称），不需要跟着翻。
## 精灵画面朝向则可能被转身动画接管，见 _flip_sprite()。
## 注意素材本身朝左的怪（如 crawlid）必须在场景里把 EnemyAnimatedSprite.scale.x 预置成 -1，
## 让它与 move_direction = +1 对齐；那不是多余的镜像，删掉就会出现"头朝反方向走路"。
## 预置值由 base_sign 记录，画面朝向按它派生（见 _sync_facing）。
func _flip_direction() -> void:
	_enemy.move_direction *= -1
	var marker := _enemy.drop_marker
	if marker != null:
		marker.position.x *= -1
		marker.reset_physics_interpolation()
	_enemy._flip_extra()  # 子类（EnemyGround）在此翻转探测器，务必走虚调用
	_flip_sprite()


## 精灵的左右翻面：能播转身动画时把翻转延后到动画收尾，否则立刻对齐。
## 关键点：turn 素材本身画了 180° 转向（旧朝向 → 新朝向），所以动画期间必须保持旧的 scale，
## 等播完再对齐一次。若像最早那样"先翻 scale 再播动画"，画面会变成
## 新朝向 → 退回旧朝向 → 又到新朝向，看起来就是"多扭一次 / 多回一次头"。
func _flip_sprite() -> void:
	if turning:
		# 转身动画期间不再动画面：move_direction 已经跟着翻了，收尾时按最新值一次性对齐。
		# 兜底：万一动画被顶掉却漏了 animation_changed（理论上不会），别把朝向卡住。
		var player := _enemy.action_animation_player
		if player == null or player.current_animation != _enemy.turn_animation:
			_finish_turn()
		return
	if _try_start_turn():
		return  # 画面交给转身动画，播完由 _on_action_animation_finished 对齐
	_sync_facing()  # 没配转身动画 / 冷却中 / 正在播一次性演出：立刻对齐


## 画面朝向对齐：把精灵 scale.x 按 move_direction 重算一遍。
## 用"赋值"而不是 scale.x *= -1 —— 累乘是有状态开关，调用次数一旦被异步回调
## （动画结束 / 状态抢占 / 受击打断）打乱，朝向就会与 move_direction 永久错位，
## 表现为"倒着走"且极难复现。改成派生式后，调 0 次 / 1 次 / 3 次结果完全一致。
func _sync_facing() -> void:
	var sprite := _enemy.animated_sprite
	var want := EnemySteering.facing_scale_x(base_sign, sprite.scale.x, _enemy.move_direction)
	
	sprite.scale.x = want
	sprite.reset_physics_interpolation()


## 画面朝向是否与 move_direction 一致（转身动画播放那 0.15s 按设计为 false）。
func is_facing_consistent() -> bool:
	var want := signf(EnemySteering.facing_scale_x(base_sign, 1.0, _enemy.move_direction))
	return is_equal_approx(signf(_enemy.animated_sprite.scale.x), want)


## 死区取值：deadzone > 0 用传入值，否则沿用敌人的 face_deadzone。
## decide_step_x() / is_within_face_deadzone() / face_toward() 三处同源，改一处即可。
func _deadzone(deadzone: float) -> float:
	return _enemy.face_deadzone if deadzone <= 0.0 else deadzone


## ---- 转身动画 ----

## 尝试起一次转身动画。守卫让"不是每只怪都配了转身动画"成为默认值：
##   1. turn_animation 为空 / 没有同名 clip → false（调用方立刻对齐，行为与以前一致）；
##   2. 当前播放的不是循环动作（正在播 appear 钻出 / bury 缩回 / death / attack 这类
##      一次性演出）→ false，否则转身播完会把演出重放一遍；
##      这里用"集合判断"而不是比对 locomotion_clip，免得某些怪没建 idle clip 就永久关掉转身；
##   3. 距上次转身不足 turn_min_interval → false（防目标在死区边缘抖动把动画打卡顿）。
func _try_start_turn() -> bool:
	var player := _enemy.action_animation_player
	if player == null or _enemy.turn_animation == &"" \
			or not player.has_animation(_enemy.turn_animation):
		return false
	if player.current_animation != EnemyStateNames.MOVE \
			and player.current_animation != EnemyStateNames.IDLE:
		return false
	var now := Time.get_ticks_msec()
	if now - last_ms < int(_enemy.turn_min_interval * 1000.0):
		return false
	last_ms = now
	turning = true
	player.play(_enemy.turn_animation)
	return true


## 转身收尾：按当前 move_direction 重新对齐画面朝向。
## 幂等，所以"转身期间又翻了几次"不需要记账 —— 中途翻几次都不影响最终结果。
func _finish_turn() -> void:
	turning = false
	_sync_facing()


## 转身动画播完：把动作还给状态声明的循环动作（move / idle），并对齐朝向。
## 顺序很重要：先 play + seek 把精灵切到恢复动画的第 0 帧，再翻 scale。
## 反过来的话会有一帧出现"scale 已翻、精灵还停在 turn 最后一帧"的组合，
## 那一帧的朝向会弹回旧方向（轻微版"多回一次头"）。两者在同一回调内完成，渲染前不会露出来。
func _on_action_animation_finished(anim_name: StringName) -> void:
	if anim_name != _enemy.turn_animation:
		return
	var player := _enemy.action_animation_player
	turning = false  # 先落旗，避免下面的 play() 触发 animation_changed 时重复结算
	var resume := _resume_clip()
	if player != null and resume != &"":
		player.play(resume)
		player.seek(0.0, true)
	_finish_turn()


## 转身结束后要恢复到的循环动作：优先状态声明的那个，没建就退回 move → idle。
## 兜底是必要的 —— 某些怪只建了 move，没有兜底的话转身播完会停在 turn 的最后一帧。
func _resume_clip() -> StringName:
	var player := _enemy.action_animation_player
	if player == null:
		return &""
	if player.has_animation(locomotion_clip):
		return locomotion_clip
	for fallback in [EnemyStateNames.MOVE, EnemyStateNames.IDLE]:
		if player.has_animation(fallback):
			return fallback
	return &""


## 转身动画被别的动作顶掉（受击硬直、切状态抢播 idle、死亡等）：
## 立刻对齐画面朝向，别让它停在旧朝向。
## 注：本回调在 play(locomotion_clip) 时也会触发，但那时 turning 已为 false，不会重复结算。
func _on_action_animation_changed(_old_name: StringName, new_name: StringName) -> void:
	if turning and new_name != _enemy.turn_animation:
		_finish_turn()


## ---- 逐帧兜底与 DEBUG 自检 ----

## 兜底：turn 动画若因任何原因没收尾（信号丢失 / 被静默顶掉），turning 会一直为 true，
## 之后每次翻面都会被 _flip_sprite() 的 turning 分支直接吞掉 —— 精灵从此再也不翻，
## 表现就是"起身后 walk 动画永久朝向反了"。这里按"动画时长 + 250ms"强制结算。
func tick(delta: float) -> void:
	if turning:
		var p := _enemy.action_animation_player
		var overdue := p == null or p.current_animation != _enemy.turn_animation
		if not overdue and p.has_animation(_enemy.turn_animation):
			var len_ms := int(p.get_animation(_enemy.turn_animation).length * 1000.0)
			overdue = Time.get_ticks_msec() - last_ms > len_ms + 250
		if overdue:
			push_warning("%s: turn 动画超时未收尾，强制结算画面朝向" % _enemy.name)
			_finish_turn()
	if OS.is_debug_build():
		_check_facing(delta)


## DEBUG 自检：朝向与位移不一致且持续超过 0.5s 就告警（转身动画那 0.15s 不算）。
## 一次输出给出三者取值与当前 clip，用来一眼分辨是"没翻面""位移被覆盖"还是"clip 卡住"。
func _check_facing(delta: float) -> void:
	var moving := absf(_enemy.velocity.x) > 1.0
	var bad := (not is_facing_consistent()) \
			or (check_displacement and moving and signf(_enemy.velocity.x) != float(_enemy.move_direction))
	if bad:
		mismatch_t = 0.0 if mismatch_t < 0.0 else mismatch_t + delta
		if mismatch_t > 0.5:
			push_warning("%s[%s]: 朝向/位移不一致 %.2fs — move_direction=%d, scale.x=%.2f, velocity.x=%.1f, clip=%s"
					% [_enemy.name,
					_enemy.state_machine.get_state_name() if _enemy.state_machine != null else &"?",
					_enemy.move_direction, _enemy.animated_sprite.scale.x, _enemy.velocity.x,
					_enemy.action_animation_player.current_animation
							if _enemy.action_animation_player != null else &"?"])
	else:
		mismatch_t = -1.0
