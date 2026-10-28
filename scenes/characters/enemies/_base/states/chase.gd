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
##   _omni_chase_move()   —— 飞行怪 / 水下怪：全向靠近，进入保持距离后只留纵向分量
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
## 注：以上默认值取地面怪的量级（速度 1.0 / 射程 400 / 近战 64 / 保持 140）。
## 飞行怪的量级（1.5 / 500 / 140 / 120）写在各自 .tscn 的 chase 节点上。

var _attack_timer := 0.0
## 连续无法靠近目标的累计时长（秒）：达到 blocked_give_up_time 即丢战。仅贴地怪。
var _blocked_time := 0.0

func enter(_from: StringName) -> void:
	_play_action(EnemyStateNames.MOVE)
	# 每次进入追击重新计时（含吐弹后摇结束回追击）。
	# 旧版飞行侧这里按 _from 分了两支，但两支都是把计时器置 0，是死分支。
	_attack_timer = 0.0
	_blocked_time = 0.0

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
## 进入攻击距离且冷却走完→ATTACK；否则空。
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
		_omni_chase_move(player)

## 贴地靠近：远程怪追到保持距离内就停下（仍面朝目标），且全程不踏空。
func _planar_chase_move(player: Node2D, delta: float) -> void:
	var keep := _keep_distance()
	if keep > 0.0 and absf(player.global_position.x - enemy.global_position.x) <= keep:
		_face_target_x(player.global_position.x)  # 站定吐弹，朝向目标
		enemy.velocity.x = 0.0
		_blocked_time = 0.0
		return

	var dir := enemy.nav_velocity(player.global_position, _chase_speed())
	if dir.x == 0.0:
		enemy.velocity.x = 0.0
		_blocked_time = 0.0
		return

	# 前方踏空（悬崖 / 平台边缘）：站定并面朝玩家，绝不踏空。
	# 旧逻辑是"掉头往回走"，但悬崖探测器随朝向立刻换边 —— 下一帧它已经指向来路（有地），
	# 于是马上又掉头冲向悬崖，形成每物理帧一次的来回翻面。这里改成固定张望 + 到点丢战。
	if not enemy.has_ground_ahead(signf(dir.x)):
		_face_target_x(player.global_position.x)
		enemy.velocity.x = 0.0
		_blocked_time += delta
		if _blocked_time >= _tuning(&"blocked_give_up_time", blocked_give_up_time):
			enemy._set_combat(false)
		return

	_blocked_time = 0.0
	# 朝向取"目标方位"而不是导航方向的符号：目标在正上/正下方、或距离在临界点附近时，
	# nav 方向的 sign() 会随导航重算噪声逐帧变号，同样会造成疯狂翻面（见 _face_target_x）。
	# 代价是绕障碍时可能出现"面朝玩家倒着走"，若以后加入真正需要绕行的地形，再回来加迟滞处理。
	_face_target_x(player.global_position.x)
	enemy.velocity.x = dir.x

## 全向靠近（飞行 / 水下）：朝目标飞，进入保持距离后只保留纵向分量（站定吐弹的水平间距）。
func _omni_chase_move(player: Node2D) -> void:
	var target_pos := player.global_position
	var dir := enemy.nav_velocity(target_pos, _chase_speed())
	# 与目标保持水平间距，避免贴脸冲撞。
	if absf(target_pos.x - enemy.global_position.x) <= _keep_distance():
		dir.x = 0.0
	enemy.velocity = dir
	# 朝向必须用带死区的 _face_target_x，不能用 signf(dir.x)：
	# 玩家几乎在正上 / 正下方时 x 差会在 0 附近抖动，取符号会导致原地疯狂翻面。
	_face_target_x(target_pos.x)
