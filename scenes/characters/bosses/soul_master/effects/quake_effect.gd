extends Area2D
class_name SoulMasterQuakeWave

## SoulMaster「quake」的落地冲击波：贴着地面水平外扫，撞到玩家结算伤害但**不销毁**，
## 一直飞到 lifetime（默认 6 秒）结束才消失。
##
## 命中规则（见 _try_hit）：
##   · hit_interval <= 0（默认）：同一玩家在整段生命周期里只打一次；
##   · hit_interval > 0：同一玩家每隔 hit_interval 秒可再一次受击。
## 玩家受击本身带 invincible_time 无敌帧，因此左右两道波同时压在身上也只扣一次血。
##
## 用法（必须 add_child 之后再摆位并调用，内部要写 global_position / reset_physics_interpolation）：
##     var wave := WAVE_SCENE.instantiate() as SoulMasterQuakeWave
##     wave.z_as_relative = boss.z_as_relative
##     wave.z_index = boss.z_index + 1
##     parent.add_child(wave)
##     wave.global_position = Vector2(x, ground_y - wave_ground_offset)
##     wave.launch(dir, damage, lifetime, speed, boss)

@export_group("运动")
## 水平速度（像素 / 秒）。左右由 launch() 的 dir 决定。
@export var speed: float = 520.0
## 从 0 加速到 speed 的时长（秒）：0 = 生成即全速。
@export var accel_time: float = 0.0

@export_group("生命周期")
## 存活时长（秒）：到点自毁。
@export var lifetime: float = 6.0

@export_group("命中")
## 单次命中伤害。
@export var damage: int = 1
## 同一玩家的再次受击间隔（秒）；<= 0 = 整段只打一次。
@export var hit_interval: float = 0.0
## 出生后的结算宽限（秒）：覆盖"生成瞬间已经压在玩家身上"的两帧。
@export var hit_grace: float = 0.05

## 波的行进方向（±1）。
var _dir: int = 1
var _speed_now: float = 0.0
var _elapsed: float = 0.0
## 伤害来源：优先记 BOSS（格挡方向 / 击退方向与下砸保持一致）。
var _source: Node2D = null
## 玩家 instance_id → 下次可受击的时刻（_elapsed 时间轴）。
var _next_hit: Dictionary = {}

@onready var _sprite: AnimatedSprite2D = get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
## 已经做过底部对齐的帧号（-1 = 还没对齐）。
var _aligned_frame := -1


func _ready() -> void:
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)
	if _sprite != null:
		_sprite.play()
	_align_to_ground()


## 起波（add_child 之后调用）。dir 取 ±1（<=0 一律视为向左走）；
## dmg / life / spd 传负数表示沿用导出属性里的默认值。
func launch(dir: int, dmg: int = -1, life: float = -1.0, spd: float = -1.0, source: Node2D = null) -> void:
	_dir = 1 if dir >= 0 else -1
	if dmg >= 0:
		damage = dmg
	if life > 0.0:
		lifetime = life
	if spd > 0.0:
		speed = spd
	_source = source
	_elapsed = 0.0
	_speed_now = 0.0 if accel_time > 0.0 else speed
	if _sprite != null:
		_sprite.flip_h = _dir < 0
		_sprite.play()
		_aligned_frame = -1
		_align_to_ground()
	# 生成瞬间就与玩家重叠时 body_entered 不会补发，宽限结束后自己补判一次。
	get_tree().create_timer(maxf(hit_grace, 0.001)).timeout.connect(_check_overlap)


func _physics_process(delta: float) -> void:
	_elapsed += delta
	_align_to_ground()
	if accel_time > 0.0:
		_speed_now = move_toward(_speed_now, speed, speed / accel_time * delta)
	else:
		_speed_now = speed
	global_position.x += float(_dir) * _speed_now * delta
	if _elapsed >= lifetime:
		queue_free()


## 逐帧把贴图底部对齐到节点原点：动画各帧高度差很大（87~192 px），
## 固定 offset 会让波底在地面线上下大幅浮动，这里按当前帧高度反推 offset，
## 让每一帧的"根部"始终踩在节点原点上（节点原点即地面）。
func _align_to_ground() -> void:
	if _sprite == null or _sprite.sprite_frames == null:
		return
	var frame := _sprite.frame
	if frame == _aligned_frame:
		return
	_aligned_frame = frame
	var tex := _sprite.sprite_frames.get_frame_texture(_sprite.animation, frame)
	if tex == null:
		return
	# centered=true 时绘制矩形以 offset 为中心，offset.y = -h/2 即让底边落在原点。
	_sprite.offset = Vector2(0.0, -tex.get_height() * 0.5)


func _on_body_entered(body: Node) -> void:
	_try_hit(body)


## 宽限结束后的补判（见 launch）。
## 这里必须把 _elapsed 顶到宽限值：计时器走的是 process 时间、_elapsed 走的是 physics 时间，
## 两者会差半帧，直接沿用 _try_hit 的宽限判断会让补判恰好在宽限内被丢掉（而 body_entered 已经漏过去了）。
func _check_overlap() -> void:
	if not is_inside_tree():
		return
	_elapsed = maxf(_elapsed, hit_grace)
	for body in get_overlapping_bodies():
		_try_hit(body)


## 命中结算：只打玩家组；**击中不销毁本节点**（这是冲击波与投射物的关键区别）。
## 返回是否真的造成了伤害。
func _try_hit(body: Node) -> bool:
	if _elapsed < hit_grace:
		return false
	if not body.is_in_group("player") or not body.has_method("take_damage"):
		return false
	var id := body.get_instance_id()
	if _next_hit.has(id):
		# hit_interval <= 0：整段只打一次，命中记录即"已打完"。
		if hit_interval <= 0.0 or _elapsed < float(_next_hit[id]):
			return false
	_next_hit[id] = _elapsed + maxf(hit_interval, 0.0)
	body.take_damage(damage, _damage_source())
	return true


## 伤害来源：BOSS 还在就记 BOSS，否则记自己（玩家格挡 / 击退只要求 Node2D）。
func _damage_source() -> Node2D:
	return _source if is_instance_valid(_source) else self
