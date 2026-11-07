extends EnemyState
class_name EnemyChaseState


## 追击骨架：攻击距离判定、攻击冷却、保持距离、丢战转 return / 进距离转 attack，
## 各类怪完全一致，只有"这一步往哪走"不同。
##
## 本文件合并了原 CombatState：它只被地面 / 飞行两个 chase 继承，没有独立存在价值，
## 且其 _step_move() / _tick_combat() 两个占位函数全项目无调用方，已一并删除。
##
## 走法同样不再按怪物类型建子类，而是按 **贴地 / 全向** 两条分支收在本文件里，
## 由 locomotion.nav_planar_only 一处分派：
##   _planar_chase_move() —— 地面怪：沿地水平靠近，前方踏空时站定张望、到点放弃
##   _omni_chase_move()   —— 飞行怪 / 水下怪：全向靠近；视线被掩体挡住时先绕到
##                            有视线的射击位，看得见玩家且进入射程才站定吐弹
## 逐敌人可变状态（_blocked_time 等）留在本状态节点上，不进共享的 Locomotion 资源。

## 追击速度倍率：乘以 enemy.move_speed。
## 逐只覆盖请改敌人根节点的 Enemy.chase_speed_multiplier。
@export_range(0.05, 10.0, 0.05) var chase_speed_multiplier: float = 1.0
## 远程吐弹射程（像素）：配了 projectile_scene 时用这个距离判定进入 attack。
@export var shoot_range: float = 400.0
## 近战触发距离（像素）：纯近战怪（未配 projectile_scene）用这个距离判定进入 attack。
@export var melee_attack_range: float = 64.0
## 两次攻击之间的冷却（秒）：远程吐弹与近战扑击共用。
## 逐只覆盖请改敌人根节点的 attack_interval（Enemy 基类导出，< 0 沿用本默认值）。
## 近战取值建议 >= enemy.contact_cooldown，否则会出现"扑击有声、实际没打到"的空洞反馈。
@export var attack_interval: float = 1.5
## 远程追击时与目标保持的水平距离（像素）：追到该距离内就停下吐弹，不再贴脸。0 = 不保持距离。
@export var shoot_keep_distance: float = 140.0
## 前方踏空（悬崖 / 平台边缘）导致无法靠近目标时，坚持多久放弃战斗回巢（秒）。仅贴地怪。
## 站定张望比卡在边缘来回掉头体面得多，也让这场打不着的战斗能正常收场（chase → return）。
@export var blocked_give_up_time: float = 1.5
## 全向追击时连续这么久"想动却没产生位移"即判定卡住（秒）：换绕行侧 + 短暂脱困。
## 只靠前视射线挡不住所有几何：怪可能钻进与身体等宽的缝，射线说能过、身体过不去。
@export var chase_stuck_time: float = 0.6
## 注：以上默认值取地面怪的量级（速度 1.0 / 射程 400 / 近战 64 / 保持 140）。
## 飞行怪的量级（1.5 / 500 / 140 / 120）写在各自 .tscn 的 chase 节点上。

var _attack_timer := 0.0
## 连续无法靠近目标的累计时长（秒）：达到 blocked_give_up_time 即丢战。仅贴地怪。
var _blocked_time := 0.0
## 全向追击的卡住看门狗：位移锚点与"净位移一直很小"的累计时长。
## 用锚点而不是逐帧位移：卡在窄缝里时 move_and_slide() 会让身体小幅抖动，
## 逐帧比较会不停清零计时，明明没挪窝却永远判不出卡住。
var _stuck_anchor := Vector2.ZERO
var _chase_stuck_time := 0.0
## 连续脱困次数：一直够不到玩家就主动收兵，别无限期顶着掩体。
var _stuck_resets := 0

func enter(_from: StringName) -> void:
	# 声明循环动作（而不是只 _play_action）：转身动画播完要恢复到它，
	# 且一次性演出（appear / death …）不会被误当成恢复目标。
	enemy.set_locomotion_clip(EnemyStateNames.MOVE)
	# 每次进入追击重新计时（含吐弹后摇结束回追击）。
	# 旧版飞行侧这里按 _from 分了两支，但两支都是把计时器置 0，是死分支。
	_attack_timer = 0.0
	_blocked_time = 0.0
	_stuck_anchor = enemy.global_position
	_chase_stuck_time = 0.0
	_stuck_resets = 0

func update(delta: float) -> void:
	var player := enemy.get_player()
	if player == null:
		_stop()
		super.update(delta)
		return
	enemy.target = player
	_chase_move(player, delta)
	enemy.tick_combat(delta)
	_attack_timer += delta
	super.update(delta)

func get_transition(delta: float) -> StringName:
	return _check_combat_transition(delta)

## 统一转换：离开可活动介质→丢战回巢；战斗丢失→RETURN；
## 进入攻击距离、看得见玩家且冷却走完→ATTACK；否则空。
## 视线这一条是必须的：弹丸会被 Objects 层掩体直接吃掉（projectile_aspid.gd），
## 隔着掩体进 attack 只会站定吐空弹，看起来就是"怪卡在平台上发呆"。
func _check_combat_transition(delta: float) -> StringName:
	# 变量名不能用 machine —— 那是基类 State 的属性，同名局部变量会遮蔽它。
	var esm := enemy.state_machine
	if esm == null:
		return &""
	# 守卫 return 状态是否存在 —— 否则没有该状态的怪会每帧空转（与 patrol 对齐）。
	var has_return := esm.states.has(EnemyStateNames.RETURN)
	# 离开了可活动介质（如水下怪被诱出水面）：打不了，放弃战斗回巢。
	if not enemy.is_in_medium():
		enemy._set_combat(false)
		return EnemyStateNames.RETURN if has_return else &""
	if not enemy.combat_active:
		return EnemyStateNames.RETURN if has_return else &""
	if not esm.states.has(EnemyStateNames.ATTACK):
		return &""
	var player := enemy.get_player()
	if player != null \
			and enemy.global_position.distance_to(player.global_position) <= _attack_range() \
			and enemy.has_clear_shot() \
			and _can_attack(delta):
		return EnemyStateNames.ATTACK
	return &""

## 远程怪用吐弹射程，纯近战怪用贴身距离。
func _attack_range() -> float:
	if enemy == null:
		return 0.0
	if enemy.has_projectile():
		return _tuning(&"shoot_range", shoot_range)
	return _tuning(&"melee_attack_range", melee_attack_range)

func _can_attack(_delta: float) -> bool:
	# 近战同样要走冷却：attack 的近战分支到点就回 chase，若这里对近战无条件放行，
	# 会变成 attack → chase → attack 每帧互切，攻击音被刷成噪音。
	return _attack_timer >= _tuning(&"attack_interval", attack_interval)

## 保持距离只服务于"站定吐弹"的远程怪：近战怪要贴脸才碰得到人，故返回 0。
func _keep_distance() -> float:
	if not enemy.has_projectile():
		return 0.0
	return _tuning(&"shoot_keep_distance", shoot_keep_distance)

## 本帧的追击速度（像素 / 秒）：统一的倍率解析，各走法直接用。
func _chase_speed() -> float:
	return _move_speed() * _tuning(&"chase_speed_multiplier", chase_speed_multiplier)


# ---------- 走法：由 locomotion.nav_planar_only 分派 ----------

func _chase_move(player: Node2D, delta: float) -> void:
	if enemy.is_planar_mover():
		_planar_chase_move(player, delta)
	else:
		_omni_chase_move(player, delta)

## 贴地靠近：远程怪追到保持距离内就停下（仍面朝目标），且全程不踏空。
func _planar_chase_move(player: Node2D, delta: float) -> void:
	var target_x := player.global_position.x
	var keep := _keep_distance()
	if keep > 0.0 and absf(target_x - enemy.global_position.x) <= keep:
		_face_toward(target_x)  # 站定吐弹，朝向目标
		enemy.velocity.x = 0.0
		_blocked_time = 0.0
		return

	# 目标几乎在自己的正上 / 正下方（玩家从头顶跳过、或站在头顶的平台上）：
	# 横向根本没有"该走的方向"。这里必须站定，不能"按 sign(dx) 走一步" ——
	# 位移会不断把 |dx| 缩小，怪物永远出不了死区、朝向也就永远不更新，于是长期倒着走
	# （玩家从 idle 的 mosscreep 头顶跳过后就命中这个分支）。站定不算"够不到"，不累计放弃计时。
	if enemy.is_within_face_deadzone(target_x, _deadzone()):
		_face_toward(target_x)
		enemy.velocity.x = 0.0
		return

	# 前方踏空（悬崖 / 平台边缘）：站定并面朝玩家，绝不踏空。
	# 旧逻辑是"掉头往回走"，但悬崖探测器随朝向立刻换边 —— 下一帧它已经指向来路（有地），
	# 于是马上又掉头冲向悬崖，形成每物理帧一次的来回翻面。这里改成固定张望 + 到点丢战。
	# 朝向与位移同源于 _step_toward()，不存在"朝哪 / 走哪"两套判据。
	if _step_toward(target_x, _chase_speed()) == 0:
		_face_toward(target_x)
		enemy.velocity.x = 0.0
		_blocked_time += delta
		if _blocked_time >= _tuning(&"blocked_give_up_time", blocked_give_up_time):
			enemy._set_combat(false)
		return

	_blocked_time = 0.0

## 全向靠近（飞行 / 水下）：
##   看得见玩家 + 在射程内 → 站定吐弹（仅远程怪），不再直冲玩家；
##   视线被掩体挡住 → 先飞到"打得到玩家"的射击位，由 nav_velocity() 的避障绕开实体；
##   其余情况 → 朝玩家靠近。
## 旧实现在 |dx| <= shoot_keep_distance 时把 dir.x 清零：玩家躲在正下方的掩体下时，
## 速度会变成纯垂直分量，move_and_slide() 静默吃掉位移，怪就永远顶着平台。
func _omni_chase_move(player: Node2D, delta: float) -> void:
	var player_pos := player.global_position
	var pos := enemy.global_position
	var dist := pos.distance_to(player_pos)
	var keep := _keep_distance()
	var speed := _chase_speed()
	var sight := enemy.has_clear_shot()

	# 卡住看门狗：velocity 有值、move_and_slide() 却没推动身体（贴在掩体 / 卡在窄缝）。
	# 站定吐弹不算卡住；到点就换绕行侧、丢弃射击位并短暂朝最开阔的方向脱离。
	# 判据是"距锚点的净位移"：正常绕行每 0.6 秒能走 70px 以上，不会被误判。
	var wants_to_move := not sight or dist > _attack_range()
	if not wants_to_move:
		_stuck_anchor = pos
		_chase_stuck_time = 0.0
		_stuck_resets = 0
	else:
		_chase_stuck_time += delta
		if pos.distance_to(_stuck_anchor) >= 16.0:
			_stuck_anchor = pos
			_chase_stuck_time = 0.0
			_stuck_resets = 0
		elif _chase_stuck_time >= _tuning(&"chase_stuck_time", chase_stuck_time):
			if enemy.flight_avoidance_enabled:
				enemy.flight_nav.on_stuck()
				_stuck_resets += 1
				# 换侧、换射击位、脱困都试过还够不到人：收兵回巢，交给视线/领地
				# 决定何时重开战，比一直贴着掩体抖到 combat_lose_time 体面得多。
				if _stuck_resets >= 3:
					enemy._set_combat(false)
					return
			_stuck_anchor = pos
			_chase_stuck_time = 0.0

	if enemy.has_projectile() and sight and dist <= _attack_range():
		if keep > 0.0 and dist < keep * 0.75:
			# 贴太近：朝反方向拉开一点，同样走避障，避免倒着飞又撞上掩体。
			var back := pos + player_pos.direction_to(pos) * keep
			enemy.velocity = enemy.nav_velocity(back, speed * 0.6)
		else:
			_stop()
		_face_toward(player_pos.x)
		enemy.flight_nav.reset()
		return

	var target_pos := player_pos
	if not sight and enemy.flight_avoidance_enabled:
		var spot := enemy.flight_nav.find_firing_spot(
				player_pos, maxf(keep, 100.0), _attack_range())
		if enemy.flight_nav.has_firing_spot:
			target_pos = spot
	enemy.velocity = enemy.nav_velocity(target_pos, speed)
	# 朝向必须用带死区的 _face_toward，且跟着"这帧真正要去的地方"：
	# 绕行时头朝侧面，而不是一直盯着墙后的玩家原地翻面。脱困阶段尤其要跟速度，
	# 否则 facing 的 DEBUG 自检会持续报"朝向/位移不一致"。
	var face_x := target_pos.x
	if enemy.flight_nav.is_escaping:
		face_x = pos.x + enemy.velocity.x
	_face_toward(face_x)
