extends Node2D
class_name SoulMasterTeleportTrail

## BOSS 闪现的位移轨迹粒子（纯表现，无碰撞、不结算伤害）。
##
## 瞬移是一帧完成的，所以这里不做"发射器跟着 BOSS 飞"，而是在瞬移那一刻一次性
## 把粒子铺满「起点 → 落点」这条线：
##   Trail        沿线按 trail_spacing 采样（EMISSION_SHAPE_POINTS），铺出轨迹主体；
##   OriginBurst  起点炸开一小团（"消失"的溅射）；
##   ArrivalBurst 落点炸开一小团（"出现"的溅射）。
## 三者都是 one_shot + explosiveness=1，同帧起爆，粒子向外飘一点后淡出，
## 播放 total_lifetime 秒后自毁。
##
## 用法（必须在 add_child 之后调用，内部要写 global_position）：
##     var fx := TRAIL_SCENE.instantiate() as SoulMasterTeleportTrail
##     parent.add_child(fx)
##     fx.play_trail(from_pos, to_pos)
##
## 贴图在 .tscn 里烘焙（spatter_white.png），本脚本只负责"摆点 + 起爆"；
## 换素材改 tscn 里的 texture 即可，不必动这里。

@export_group("轨迹")
## 沿线采样间距（像素）：越小轨迹越密。
@export var trail_spacing: float = 26.0
## 轨迹粒子数上限：防止长距离瞬移时一次性放出几百个粒子。
@export var trail_max_amount: int = 140
## 垂直于路径的随机偏移（像素）：让轨迹有宽度，而不是一条几何直线。
@export var trail_jitter: float = 12.0
## 轨迹粒子寿命（秒）：越短轨迹消散越快。
@export var trail_lifetime: float = 0.5
## 轨迹粒子向外飘的速度区间（像素/秒）。
@export var trail_speed_min: float = 10.0
@export var trail_speed_max: float = 70.0
@export var trail_scale_min: float = 0.35
@export var trail_scale_max: float = 0.85

@export_group("两端溅射")
## 起点 / 落点各炸开多少粒子。
@export var end_burst_amount: int = 14
@export var end_burst_speed_min: float = 90.0
@export var end_burst_speed_max: float = 240.0
@export var end_burst_lifetime: float = 0.45
@export var end_burst_scale_min: float = 0.4
@export var end_burst_scale_max: float = 1.0
## 两端溅射的发射半径（像素）：0 = 单点发射。
@export var end_burst_radius: float = 18.0

@export_group("物理")
## 重力（像素/秒²）：默认 0，让粒子原地飘散；想让它下坠就填正值。
@export var gravity: Vector2 = Vector2.ZERO
@export var damping_min: float = 40.0
@export var damping_max: float = 90.0

@export_group("生命周期")
## 起爆到自毁的总时长（秒），必须 >= 最长的粒子寿命。
@export var total_lifetime: float = 0.9

@onready var _trail: CPUParticles2D = get_node_or_null("Trail") as CPUParticles2D
@onready var _origin_burst: CPUParticles2D = get_node_or_null("OriginBurst") as CPUParticles2D
@onready var _arrival_burst: CPUParticles2D = get_node_or_null("ArrivalBurst") as CPUParticles2D


func _ready() -> void:
	# 等 play_trail() 摆好位置再起爆，避免特效还没落位就在本地原点闪一帧。
	for p in _emitters():
		p.emitting = false


## 起爆：from_pos / to_pos 都用世界坐标。
func play_trail(from_pos: Vector2, to_pos: Vector2) -> void:
	if not is_inside_tree():
		return
	global_position = from_pos
	var offset := to_pos - from_pos

	_setup_trail(offset)
	_setup_burst(_origin_burst, end_burst_amount, end_burst_speed_min,
			end_burst_speed_max, end_burst_lifetime, end_burst_scale_min, end_burst_scale_max)
	_setup_burst(_arrival_burst, end_burst_amount, end_burst_speed_min,
			end_burst_speed_max, end_burst_lifetime, end_burst_scale_min, end_burst_scale_max)
	if _origin_burst != null:
		_origin_burst.position = Vector2.ZERO
	if _arrival_burst != null:
		_arrival_burst.position = offset

	# 瞬移是位置突变：本节点与子发射器都要重置插值，否则首帧会从旧位置滑过来。
	reset_physics_interpolation()
	for p in _emitters():
		p.reset_physics_interpolation()

	_ignite.call_deferred()
	var timer := get_tree().create_timer(total_lifetime)
	timer.timeout.connect(queue_free)


# ---- 发射器配置 ----

## 轨迹主体：把「起点 → 落点」按间距采样成点集，交给 CPUParticles2D 的 POINTS 发射形状。
func _setup_trail(offset: Vector2) -> void:
	if _trail == null:
		return
	var length := offset.length()
	var dir := offset / length if length > 0.001 else Vector2.RIGHT
	var normal := Vector2(-dir.y, dir.x)
	# 采样点数 = 长度 / 间距 + 1（两端各一个），并夹到上限。
	var count := int(clampf(floorf(length / maxf(trail_spacing, 1.0)) + 1.0,
			1.0, float(maxi(trail_max_amount, 1))))
	var points := PackedVector2Array()
	points.resize(count)
	for i in count:
		var t := 0.0 if count <= 1 else float(i) / float(count - 1)
		points[i] = offset * t + normal * randf_range(-trail_jitter, trail_jitter)

	_trail.emission_shape = CPUParticles2D.EMISSION_SHAPE_POINTS
	_trail.emission_points = points
	_trail.amount = count
	_trail.lifetime = trail_lifetime
	_trail.direction = Vector2.UP
	_trail.spread = 180.0            # 全向：每个采样点都向四周轻微溅开
	_trail.gravity = gravity
	_trail.damping_min = damping_min
	_trail.damping_max = damping_max
	_trail.initial_velocity_min = minf(trail_speed_min, trail_speed_max)
	_trail.initial_velocity_max = maxf(trail_speed_min, trail_speed_max)
	_trail.scale_amount_min = trail_scale_min
	_trail.scale_amount_max = trail_scale_max


## 两端溅射：环形（或单点）炸开一团。
func _setup_burst(p: CPUParticles2D, amount: int, speed_min: float, speed_max: float,
		lifetime: float, scale_min: float, scale_max: float) -> void:
	if p == null:
		return
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RING if end_burst_radius > 0.0 \
			else CPUParticles2D.EMISSION_SHAPE_POINT
	if end_burst_radius > 0.0:
		p.emission_ring_inner_radius = 0.0
		p.emission_ring_radius = end_burst_radius
	p.amount = maxi(amount, 1)
	p.lifetime = lifetime
	p.direction = Vector2.UP
	p.spread = 180.0
	p.gravity = gravity
	p.damping_min = damping_min
	p.damping_max = damping_max
	p.initial_velocity_min = minf(speed_min, speed_max)
	p.initial_velocity_max = maxf(speed_min, speed_max)
	p.scale_amount_min = scale_min
	p.scale_amount_max = scale_max


func _emitters() -> Array[CPUParticles2D]:
	var out: Array[CPUParticles2D] = []
	for child in get_children():
		if child is CPUParticles2D:
			out.append(child as CPUParticles2D)
	return out


## 起爆统一放到本帧末：此时节点位置 / 物理插值都已就绪（与 feather_hit_effect 同一套路）。
func _ignite() -> void:
	if not is_inside_tree():
		return
	for p in _emitters():
		p.restart()
