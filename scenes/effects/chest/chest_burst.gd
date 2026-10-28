extends Node2D
class_name ChestBurst


## 木箱炸裂的碎石迸发特效。
##
## 用法与 res://scenes/effects/plants/leaf_burst.tscn 完全一致：
##   instantiate → 写参数 → add_child → 赋 global_position → 播完自动 queue_free。
##
## 本版本 CPUParticles2D 不支持逐粒子随机帧（同 leaf_burst.gd 的说明），
## 所以用 6 个发射器各取 particles.png（竖排 6 块碎石）中的一块来制造形状差异；
## 6 个发射器的 amount 之和 = 一次性迸出的碎石总数（chest_burst.tscn 里 3+3+3+2+2+2 = 15）。
##
## 贴图在 chest_burst.tscn 里以 AtlasTexture 直接烘焙（particles.png 为 54×468，
## 竖排 6 块 → 每块 54×78），本脚本不碰贴图：换素材时改场景里那 6 个 region 即可。
##
## 注意：CPUParticles2D 没有碰撞，碎石只会走抛物线并在寿命末端淡出，不会真的停在地上。
## 落回出发高度之后会继续下沉，因此淡出起点（color_ramp 的第一个中间点）调得比较靠前，
## 让下沉段基本发生在低透明度区间，视觉上就是"落地即散"。

@export_group("运动")
## 迸发方向固定为正上方，spread 是以它为轴的总张开角度（需求：约 120 度）。
@export var spread_degrees: float = 120.0
@export var speed_min: float = 300.0
@export var speed_max: float = 500.0
## 重力：越小弧线越高越飘，落点越分散。
@export var gravity_y: float = 800.0
## 径向 / 切向加速度：让碎石越飞越散，而不是走成一排整齐的扇形线。
@export var radial_accel_min: float = 60.0
@export var radial_accel_max: float = 140.0
@export var tangential_accel_min: float = -40.0
@export var tangential_accel_max: float = 40.0
@export var lifetime: float = 1.5

@export_group("外观")
@export var scale_min: float = 0.45
@export var scale_max: float = 1.35
## 翻滚角速度：引擎没有"初始朝向随机"参数，靠随机角速度在起爆后极短时间内把朝向错开。
@export var angular_velocity_min: float = -720.0
@export var angular_velocity_max: float = 720.0

@export_group("发射点")
## 相对本节点（= 箱子原点，箱底触地线）的迸发中心，由 Chest 写入。
@export var origin_offset: Vector2 = Vector2.ZERO
## 各发射器在中心周围的随机散布：让碎石从箱体各处起飞，而不是同一个点。
@export var origin_spread: Vector2 = Vector2(36.0, 24.0)

@export_group("生命周期")
## 起爆到销毁的总时长，需 >= lifetime，给淡出留出时间。
@export var total_lifetime: float = 1.9


func _ready() -> void:
	for child in get_children():
		if child is CPUParticles2D:
			_setup(child as CPUParticles2D)
	var timer := get_tree().create_timer(total_lifetime)
	timer.timeout.connect(queue_free)
	# 配置完成后，推迟到本帧末再统一起爆（见 _setup / _ignite 的说明）。
	call_deferred("_ignite")


## 把一个发射器按当前导出参数配好。这里只配置、不起爆：
## 起爆统一推迟到本帧末（见 _ignite），等调用方把本节点摆到正确位置之后再发射，
## 否则开启物理插值时第一帧会从旧位置（世界原点）把整批碎石打出去。
func _setup(p: CPUParticles2D) -> void:
	p.position = origin_offset + Vector2(
			randf_range(-origin_spread.x, origin_spread.x),
			randf_range(-origin_spread.y, origin_spread.y))
	p.direction = Vector2(0.0, -1.0)
	p.spread = spread_degrees
	p.lifetime = lifetime
	p.gravity = Vector2(0.0, gravity_y)
	p.initial_velocity_min = minf(speed_min, speed_max)
	p.initial_velocity_max = maxf(speed_min, speed_max)
	p.radial_accel_min = radial_accel_min
	p.radial_accel_max = radial_accel_max
	p.tangential_accel_min = tangential_accel_min
	p.tangential_accel_max = tangential_accel_max
	p.scale_amount_min = scale_min
	p.scale_amount_max = scale_max
	p.angular_velocity_min = angular_velocity_min
	p.angular_velocity_max = angular_velocity_max
	p.emitting = false


## 本帧末统一起爆：此时 global_position / 物理插值状态都已就绪。
func _ignite() -> void:
	if not is_inside_tree():
		return
	for child in get_children():
		if child is CPUParticles2D:
			child.emitting = true
