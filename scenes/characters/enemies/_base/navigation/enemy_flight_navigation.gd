class_name EnemyFlightNavigation
extends RefCounted


## 全向怪（飞行 / 水下）的"最后一段"寻路：局部避障 + 视线重定位。
##
## 为什么不改关卡的 NavigationRegion2D：moss_hole_0 等关卡的导航多边形是一整块覆盖
## 全图的矩形，没有按 Obstacles 挖洞，NavigationAgent2D 因此永远给出穿过平台的直线路径。
## 而这张图是贴地怪共用的，直接重烘焙挖洞会改变地面怪的行为，所以把绕障补在全向怪这一层：
##   · steer()             —— 用三条平行前视射线探测实体，挑一个"绕得过去"的方向，
##                            并锁定左右绕行侧一小段时间，避免贴着平台边缘来回抖；
##   · find_firing_spot()  —— 玩家被掩体挡住时，在玩家周围采样"打得到玩家"的落脚点，
##                            怪先飞到掩体侧面 / 下方再开火，而不是一直顶着掩体。
##
## 只由 Enemy.nav_velocity()（全向分支）与各 chase 状态调用；贴地怪完全不经过这里。
## 与 aggro 一样不标注宿主类型（`: Enemy`），否则会与 enemy.gd 形成 class_name 循环引用。

## 候选转向角（弧度）：0 = 直冲目标，正负成对，最大约 126°（允许短暂背向目标绕远）。
const STEER_ANGLES := [0.0, 0.4, -0.4, 0.8, -0.8, 1.25, -1.25, 1.75, -1.75, 2.2, -2.2]
## 侧向承诺时长（秒）：一旦决定从左边或右边绕，短时间内不改主意。
const SIDE_COMMIT_TIME := 0.7
## 脱困时长（秒）：被卡住后暂时只按"哪边最开阔"飞，先退出窄缝再重新找射击位。
const ESCAPE_TIME := 0.8
## 前视探测距离下限 / 上限（像素）：按当前速度换算后夹在两者之间。
const MIN_PROBE := 96.0
const MAX_PROBE := 240.0
## 射击位采样：12 个方向 × 两档半径（相对 preferred_distance）。
const SPOT_DIRECTIONS := 12
const SPOT_RADII := [1.0, 0.6]
## 自身到射击位之间不通时附加的代价（像素）：允许先绕过去，但优先直达可达的点。
## 判据按整个身宽算（三条平行射线），比"比身体窄几像素的缝"更保守。
const SPOT_BLOCKED_PENALTY := 420.0
## 卡住后暂时拉黑刚才够不到的射击位，避免重规划又选回同一个点。
const SPOT_BAN_RADIUS := 64.0
const SPOT_BAN_TIME := 3.0
## 玩家移动超过这个距离就立刻重算射击位（不必等缓存到期）。
const SPOT_PLAYER_DRIFT := 48.0

## 故意不打类型：见文件头关于循环引用的说明。
var _enemy

var _ray := PhysicsRayQueryParameters2D.new()
var _sight_ray := PhysicsRayQueryParameters2D.new()
var _shape_query := PhysicsShapeQueryParameters2D.new()
## 身体碰撞形状相对根节点的偏移（AspidHunter 是 (0, 10)）。
var _body_offset := Vector2.ZERO
## 平行射线的侧向偏移：取身体半径，让探测覆盖整个身宽而不只是一条中心线。
var _flank := 36.0

## 绕行侧（±1）与剩余承诺时长。
var _avoid_side := 0.0
var _avoid_time := 0.0
## 脱困剩余时长：> 0 时 steer() 忽略目标方向，只挑最开阔的方向飞。
var _escape_time := 0.0

## 射击位缓存：视线被挡时每帧都采样太贵，按 flight_replan_interval 重算一次即可。
var _spot_timer := 0.0
var _spot_player := Vector2.ZERO
var _has_spot := false
var _spot := Vector2.ZERO

## 上次 find_firing_spot() 是否找到了可用落脚点。返回零向量不代表"没有解"，
## 所以调用方要用这个判据，别拿返回值是否为零来判断。
var has_firing_spot: bool:
	get:
		return _has_spot
## 是否正处在"只按开阔方向飞"的脱困阶段：chase 据此把朝向改为跟着实际速度。
var is_escaping: bool:
	get:
		return _escape_time > 0.0

## 卡住时拉黑的落脚点与剩余拉黑时长。
var _banned_spot := Vector2.ZERO
var _ban_time := 0.0


## 绑定宿主。必须在 Enemy._ready() 内、早于 state_machine.start() 调用。
func setup(enemy) -> void:
	_enemy = enemy
	# 避障探测用"身体会撞到的层"，视线探测用 locomotion.sight_mask（默认与前者相同）。
	_ray.collide_with_bodies = true
	_ray.collide_with_areas = false
	_ray.collision_mask = enemy.collision_mask
	_ray.hit_from_inside = true
	_ray.exclude = [enemy.get_rid()]

	_sight_ray.collide_with_bodies = true
	_sight_ray.collide_with_areas = false
	_sight_ray.hit_from_inside = true
	_sight_ray.exclude = [enemy.get_rid()]
	var sight_mask: int = enemy.collision_mask
	if enemy.locomotion != null:
		sight_mask = enemy.locomotion.get_sight_mask(sight_mask)
	_sight_ray.collision_mask = sight_mask

	_shape_query.collide_with_bodies = true
	_shape_query.collide_with_areas = false
	_shape_query.collision_mask = enemy.collision_mask
	_shape_query.exclude = [enemy.get_rid()]
	if enemy.collision_shape != null:
		_body_offset = enemy.collision_shape.position
		var shape: Shape2D = enemy.collision_shape.shape
		if shape != null:
			_shape_query.shape = shape
			if shape is RectangleShape2D:
				# 半宽 + 2px 余量：平行射线必须覆盖整个身体，否则"比身体窄几像素的缝"
				# 会被判成可通行，怪钻进去后 move_and_slide() 把位移全吃掉。
				_flank = maxf(shape.size.x, shape.size.y) * 0.5 + 2.0
			elif shape is CircleShape2D:
				_flank = shape.radius + 2.0


## 目标 / 状态切换时清掉绕行承诺与射击位缓存，避免沿用上一个目标的绕行侧。
func reset() -> void:
	_avoid_side = 0.0
	_avoid_time = 0.0
	_has_spot = false
	_spot_timer = 0.0
	_escape_time = 0.0
	_ban_time = 0.0


## chase 检测到"还想着移动、却连续几帧没有实际位移"时调用：换一侧绕、丢弃当前
## 射击位、短暂只按"哪边最开阔"飞。前视射线挡不住所有情况（怪可能钻进与身体
## 等宽的缝里，射线判成可通过、move_and_slide() 却把位移全吃掉），必须有这层反馈。
func on_stuck() -> void:
	if _has_spot:
		_banned_spot = _spot
		_ban_time = SPOT_BAN_TIME
	_has_spot = false
	_spot_timer = 0.0
	_avoid_side = -_avoid_side if _avoid_side != 0.0 else 1.0
	_avoid_time = SIDE_COMMIT_TIME
	_escape_time = ESCAPE_TIME


## 本帧速度：朝 target_pos，但避开 collision_mask 上的实体。
## 由 Enemy.nav_velocity() 的全向分支调用；返回向量长度恒为 speed（抵达目标时为 0）。
func steer(target_pos: Vector2, speed: float) -> Vector2:
	var pos: Vector2 = _enemy.global_position
	var to_target := target_pos - pos
	if to_target.length() <= 0.001 or speed <= 0.0:
		return Vector2.ZERO
	var desired := to_target.normalized()
	var probe := clampf(speed * _enemy.flight_lookahead_time, MIN_PROBE, MAX_PROBE)
	# 目标已经很近时不必探那么远，否则会被目标身后的地形误判成"前方有墙"。
	probe = minf(probe, to_target.length() + _flank)
	var dt: float = _enemy.get_physics_process_delta_time()
	_avoid_time = maxf(_avoid_time - dt, 0.0)
	var escaping := _escape_time > 0.0
	if escaping:
		_escape_time = maxf(_escape_time - dt, 0.0)

	if not escaping and _clearance(pos, desired, probe) >= 0.95:
		if _avoid_time <= 0.0:
			_avoid_side = 0.0
		return desired * speed

	# 前方被挡：在所有候选方向里挑"探得最远 + 最朝向目标 + 与已锁定绕行侧一致"的一个。
	# 脱困期间把"朝向目标"这一项去掉，只认哪边最开阔，先退出窄缝再说。
	var preferred_side := _avoid_side
	if _avoid_time <= 0.0 or preferred_side == 0.0:
		preferred_side = _pick_side(to_target, desired)
	var best_dir := desired
	var best_score := -INF
	for angle in STEER_ANGLES:
		var dir: Vector2 = desired.rotated(angle)
		var side_bonus := 0.0
		if angle != 0.0:
			side_bonus = 0.55 if signf(angle) == preferred_side else -0.55
		var toward := 0.0 if escaping else desired.dot(dir)
		var score := _clearance(pos, dir, probe) * 3.0 + toward + side_bonus
		if score > best_score:
			best_score = score
			best_dir = dir
	_avoid_side = preferred_side
	_avoid_time = SIDE_COMMIT_TIME
	return best_dir * speed


## 找一个"站在这里能打到玩家"的落脚点；找不到时 has_firing_spot == false，返回值无意义。
## 只在视线被挡时由 chase 调用，内部按 flight_replan_interval 缓存结果。
## preferred_distance：期望与玩家保持的距离（chase 的 shoot_keep_distance）。
## search_limit：射程，用来限制采样半径与飞行代价。
func find_firing_spot(player_pos: Vector2, preferred_distance: float, search_limit: float) -> Vector2:
	var dt: float = _enemy.get_physics_process_delta_time()
	_spot_timer -= dt
	_ban_time = maxf(_ban_time - dt, 0.0)
	if _spot_timer > 0.0 and _spot_player.distance_to(player_pos) < SPOT_PLAYER_DRIFT:
		return _spot
	_spot_player = player_pos
	_spot_timer = _enemy.flight_replan_interval

	var pos: Vector2 = _enemy.global_position
	var radius := clampf(preferred_distance, 80.0, maxf(80.0, search_limit))
	var best := Vector2.ZERO
	var found := false
	var best_score := INF
	for i in range(SPOT_RADII.size()):
		var r := radius * float(SPOT_RADII[i])
		for j in range(SPOT_DIRECTIONS):
			var a := TAU * float(j) / float(SPOT_DIRECTIONS)
			var cand := player_pos + Vector2(cos(a), sin(a)) * r
			# ① 落脚点自身不能被身体撞到（否则怪会朝墙里飞）；刚卡住的点暂时拉黑。
			if not _position_free(cand):
				continue
			if _ban_time > 0.0 and cand.distance_to(_banned_spot) < SPOT_BAN_RADIUS:
				continue
			# ② 从这里到玩家的弹道必须畅通：这是"绕到掩体侧面"的核心判据。
			#    用三条平行射线而不是一条中心线，否则擦着掩体角通过也会被判成可见，
			#    怪会停在掩体上方吐空弹（弹丸从 Muzzle 出发，早被平台吃掉）。
			if not _clear_shot_from(cand, player_pos):
				continue
			var travel := pos.distance_to(cand)
			if travel > search_limit * 1.5:
				continue
			# ③ 优先"整个身宽都飞得过去"的点；被挡的点不是不能去，只是要交给 steer() 绕。
			var score := travel + r * 0.15
			if not _clear_shot_from(pos, cand):
				score += SPOT_BLOCKED_PENALTY
			if score < best_score:
				best_score = score
				best = cand
				found = true
	_has_spot = found
	if found:
		_spot = best
	return best


# ---------- 物理探测 ----------

func _space() -> PhysicsDirectSpaceState2D:
	return _enemy.get_world_2d().direct_space_state


## 三条平行射线（中心 + 左右各一条）在 probe 长度内的畅通比例，1 = 完全无阻挡。
## 取最小值：只要身体任意一侧会擦到平台，就不算安全。
func _clearance(from: Vector2, dir: Vector2, probe: float) -> float:
	var flank := Vector2(-dir.y, dir.x) * _flank
	var best := 1.0
	for offset in [Vector2.ZERO, flank, -flank]:
		best = minf(best, _ray_distance(from + offset, dir, probe) / probe)
	return best


## 射线到首次命中的距离，未命中返回 probe。
func _ray_distance(from: Vector2, dir: Vector2, probe: float) -> float:
	_ray.from = from
	_ray.to = from + dir * probe
	var hit := _space().intersect_ray(_ray)
	if hit.is_empty():
		return probe
	var at: Vector2 = hit.get("position", from)
	return clampf(from.distance_to(at), 0.0, probe)


## 两点之间是否被视线层挡住。
func _ray_clear(from: Vector2, to: Vector2) -> bool:
	if from.distance_to(to) < 1.0:
		return true
	_sight_ray.from = from
	_sight_ray.to = to
	return _space().intersect_ray(_sight_ray).is_empty()


## 从自身当前位置能否"真的打到"玩家：中心线 + 左右各一条平行射线都要畅通。
## aggro.has_line_of_sight() 只用一条中心线，从掩体角擦过去也算看见；飞行怪身体和
## 吐弹口都有宽度，这样会停在掩体上方吐空弹，所以开火判据要按整个身宽来算。
func has_clear_shot(player_pos: Vector2) -> bool:
	return _clear_shot_from(_enemy.global_position, player_pos)


## 与 has_clear_shot() 同一判据，但起点换成任意候选落脚点（供 find_firing_spot 采样用）。
func _clear_shot_from(from: Vector2, player_pos: Vector2) -> bool:
	var to_player := player_pos - from
	if to_player.length() < 1.0:
		return true
	var dir := to_player.normalized()
	var flank := Vector2(-dir.y, dir.x) * _flank
	for offset in [Vector2.ZERO, flank, -flank]:
		if not _ray_clear(from + offset, player_pos):
			return false
	return true


## 把身体碰撞形状放到 pos 处，看它是否与实体重叠。
func _position_free(pos: Vector2) -> bool:
	if _shape_query.shape == null:
		return true
	_shape_query.transform = Transform2D.IDENTITY.translated(pos + _body_offset)
	return _space().intersect_shape(_shape_query, 1).is_empty()


## 首次决定往哪边绕：优先取"目标相对前进方向的横向分量"，正上 / 正下方时退而用 x 差。
func _pick_side(to_target: Vector2, desired: Vector2) -> float:
	var right := Vector2(-desired.y, desired.x)
	var side := signf(to_target.dot(right))
	if side == 0.0:
		side = signf(to_target.x)
	return 1.0 if side == 0.0 else side
