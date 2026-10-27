extends CombatState
class_name EnemyGroundChaseState


## 追击速度倍率：乘以 enemy.move_speed，大于 1 表示冲锋型敌人。
@export var speed_multiplier: float = 1.0

## 远程吐弹射程（像素）：配了 projectile_scene 时用这个距离判定进入 attack（否则用 enemy.attack_range）。
@export var shoot_range: float = 400.0
## 两次吐弹之间的冷却（秒）：仅远程模式生效，近战不受冷却限制。
@export var attack_interval: float = 1.5
## 远程追击时与目标保持的水平距离（像素）：追到该距离内就停下吐弹，不再贴脸。0 = 不保持距离。
## 逐只覆盖请改敌人根节点的 shoot_keep_distance（Enemy 基类导出，< 0 沿用本默认值）。
@export var shoot_keep_distance: float = 140.0

## 前方踏空（悬崖 / 平台边缘）导致无法靠近目标时，坚持多久就放弃战斗回巢（秒）。
## 站定张望比卡在边缘来回掉头体面得多，也让这场打不着的战斗能正常收场（chase → return）。
@export var blocked_give_up_time: float = 1.5

var _attack_timer := 0.0
## 连续无法靠近目标的累计时长（秒）：达到 blocked_give_up_time 即丢战。
var _blocked_time := 0.0

func enter(_from: StringName) -> void:
	_play_action(&"idle")
	_attack_timer = 0.0  # 每次进入追击重新计时（含吐弹后摇结束回追击）
	_blocked_time = 0.0

func update(delta: float) -> void:
	var player := enemy.get_player()
	if player == null:
		enemy.velocity.x = 0.0
		super.update(delta)
		return
	enemy.target = player
	var dir := enemy.nav_velocity(player.global_position, enemy.move_speed * speed_multiplier, true)
	_step_chase(dir, player, delta)
	enemy.tick_combat(delta)
	_attack_timer += delta
	super.update(delta)

func get_transition(delta: float) -> StringName:
	return _check_combat_transition(delta)

## 远程怪用吐弹射程，纯近战怪沿用基类的贴身距离。
func _attack_range() -> float:
	if enemy == null:
		return 0.0
	if enemy.has_projectile():
		return _tuning(&"shoot_range", shoot_range)
	return enemy.attack_range

func _can_attack(_delta: float) -> bool:
	if not enemy.has_projectile():
		return true
	return _attack_timer >= _tuning(&"attack_interval", attack_interval)

## 水平追击：远程怪追到保持距离内就停下（仍面朝目标），且全程不踏空。
func _step_chase(dir: Vector2, player: Node2D, delta: float) -> void:
	var keep := _keep_distance()
	if keep > 0.0:
		var dx := player.global_position.x - enemy.global_position.x
		if absf(dx) <= keep:
			_face_target_x(player.global_position.x)  # 站定吐弹，朝向目标
			enemy.velocity.x = 0.0
			_blocked_time = 0.0
			return

	if dir.x == 0.0:
		enemy.velocity.x = 0.0
		_blocked_time = 0.0
		return

	# 前方踏空（悬崖 / 平台边缘）：站定并面朝玩家，绝不踏空。
	# 旧逻辑是"掉头往回走"，但悬崖探测器随朝向立刻换边 —— 下一帧它已经指向来路（有地），
	# 于是马上又掉头冲向悬崖，形成每物理帧一次的来回翻面。这里改成固定张望 + 到点丢战。
	if not (enemy as EnemyGround).has_ground_ahead(signf(dir.x)):
		_face_target_x(player.global_position.x)
		enemy.velocity.x = 0.0
		_blocked_time += delta
		if _blocked_time >= blocked_give_up_time:
			enemy._set_combat(false)
		return

	_blocked_time = 0.0
	# 朝向取"目标方位"而不是导航方向的符号：目标在正上/正下方、或距离在临界点附近时，
	# nav 方向的 sign() 会随导航重算噪声逐帧变号，同样会造成疯狂翻面（见 _face_target_x）。
	# 代价是绕障碍时可能出现"面朝玩家倒着走"，若以后加入真正需要绕行的地形，再回来加迟滞处理。
	_face_target_x(player.global_position.x)
	enemy.velocity.x = dir.x

func _keep_distance() -> float:
	if not enemy.has_projectile():
		return 0.0  # 近战怪照旧贴脸
	return _tuning(&"shoot_keep_distance", shoot_keep_distance)
