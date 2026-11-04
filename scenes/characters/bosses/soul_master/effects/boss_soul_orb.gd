extends Area2D
class_name BossSoulOrb

## SoulMaster「召唤」的魂球：先绕着 BOSS 凝聚放大，到点脱离，之后整组保持一个环绕中心靠近玩家。
##
## 两段生命（r = 自生成起的秒数）：
##   环绕段 r < detach_time：绕 owner 中心公转（半径 = 传入 offset 的长度），
##                          同时视觉放大 + 自转。
##   自由段 r >= detach_time（或 owner 先失效）：环绕中心从 owner 上独立出来，
##                          **整组仍然只有一个中心和同一个角速度** —— 四颗球保持队形一起转，
##                          不会各自追着玩家跑散；此后一边按 orbit_expand_speed 扩大环绕半径，
##                          一边让这个原来的旋转中心按 homing_speed 靠近玩家（整组一起移动）。
##   r >= lifetime 自行销毁 —— 不依赖状态机，状态收招后魂球照样飞完。
##
## 命中：**任意阶段碰到玩家就结算 1 点伤害并立刻消失**（每颗球只有一条命）。
## 环绕段不禁伤：半径调大后球本来就会扫出 BOSS 身体，碰到玩家没反应会像 bug。
##
## 尺寸按「最终视觉直径」配置（见 set_visual_diameter）：判定圈按视觉半径 × hit_radius_ratio
## 同步换算，换美术 / 调大小都不用再碰判定。

@export_group("环绕段")
## 环绕角速度（度 / 秒）：0 = 上/下/左/右 四点固定不动。
@export var orbit_speed: float = 120.0
## 自转角速度（度 / 秒）：只影响精灵朝向，不影响公转。
@export var spin_speed: float = 180.0

@export_group("尺寸")
## 出生瞬间的缩放（"凝聚"状态），相对 max_scale。
@export var start_scale: float = 0.2
## 弹到基准尺寸的时长（秒）。
@export var pop_time: float = 0.05
## 基准尺寸（"1 倍"），相对 max_scale。
@export var mid_scale: float = 1.0
## 基准尺寸放大到最终尺寸的时长（秒）。
@export var grow_time: float = 0.5
## 最终视觉缩放（相对贴图原始尺寸）。状态会用 set_visual_diameter() 按像素直径覆写。
@export var max_scale: float = 5.0

@export_group("节奏")
## 脱离 owner 的时刻（秒，自生成起）。
@export var detach_time: float = 2.0
## 销毁时刻（秒，自生成起）。
@export var lifetime: float = 4.0

@export_group("脱离后")
## 旋转中心靠近玩家的速度（像素 / 秒）。
@export var homing_speed: float = 750.0
## 中心加速到 homing_speed 的加速度（像素 / 秒²）：越大越早开始移动。
@export var homing_turn_accel: float = 2200.0
## 脱离后环绕半径的扩张速度（像素 / 秒）：0 = 保持原半径。
## 「撒开」：仍是同一个旋转圆心 + 同一个角速度，只是半径慢慢变大，四颗球向外散开。
@export var orbit_expand_speed: float = 40.0

@export_group("命中")
## 判定圆半径 = 最终视觉半径 × 该比例。
@export_range(0.1, 1.0) var hit_radius_ratio: float = 0.7
## 出生 / 脱离后开始可命中的宽限（秒）：覆盖「生成瞬间就压在玩家身上」的两帧抖动。
@export var hit_grace: float = 0.06

## 每枚魂球的伤害，由 SoulMasterSummonState 写入。
var damage: int = 1

var _owner_node: Node2D = null
var _phase := 0.0
## 公转中心：环绕段跟随 owner，自由段独立移动（整组共用同一个演化）。
var _orbit_center := Vector2.ZERO
## 公转方向（单位向量，由传入 offset 归一化而来）。
var _orbit_dir := Vector2.UP
## 当前公转半径（像素）：自由段按 orbit_expand_speed 慢慢撒开。
var _orbit_radius := 0.0
var _orbit_angle := 0.0
var _center_velocity := Vector2.ZERO
var _detached := false
var _can_hit := false
var _grace := 0.0
var _hit_done := false

## 场景里配置的 (start, mid, max) 缩放，作为比例基准；
## set_visual_diameter() 按像素直径重算三个值，重复调用也不会累乘失真。
var _base_scales := Vector3(0.2, 1.0, 5.0)

@onready var _sprite: Sprite2D = get_node_or_null("Sprite2D") as Sprite2D


func _ready() -> void:
	_base_scales = Vector3(start_scale, mid_scale, max_scale)
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)
	_apply_hit_radius(max_scale * _texture_width() * 0.5)


## 按「最终视觉直径（像素）」配置大小：状态里调 orb_diameter 就走这里。
## 三个缩放按场景配置的比例等比换算，判定圈跟着视觉半径走，视觉与判定不会脱节。
func set_visual_diameter(diameter: float) -> void:
	var tex_w := _texture_width()
	if tex_w <= 0.0 or diameter <= 0.0:
		return
	var k := diameter / (tex_w * _base_scales.z)
	start_scale = _base_scales.x * k
	mid_scale = _base_scales.y * k
	max_scale = _base_scales.z * k
	_apply_hit_radius(max_scale * tex_w * 0.5)


## 由 SoulMasterSummonState 调用（必须在 add_child 之后）。
## owner_node：环绕段跟随的 BOSS；offset：相对 BOSS 原点的偏移（长度即公转半径）；
## dmg：命中伤害。
func summon(owner_node: Node2D, offset: Vector2, dmg: int) -> void:
	_owner_node = owner_node
	damage = dmg
	_phase = 0.0
	_orbit_angle = 0.0
	_orbit_radius = offset.length()
	_orbit_dir = offset / _orbit_radius if _orbit_radius > 0.001 else Vector2.UP
	_detached = false
	# 环绕段也吃命中：半径调大后球会扫出 BOSS 身体，碰到玩家就该结算并消失。
	_can_hit = true
	_hit_done = false
	_grace = hit_grace
	_center_velocity = Vector2.ZERO
	if is_instance_valid(_owner_node):
		_orbit_center = _owner_node.global_position
		global_position = _orbit_center + _orbit_dir.rotated(_orbit_angle) * _orbit_radius
		reset_physics_interpolation()
	_arm_overlap_check()
	_grow()


func _physics_process(delta: float) -> void:
	_phase += delta
	# 视觉自转：判定圈是圆形，转不转都不影响命中。
	rotation += deg_to_rad(spin_speed) * delta
	# 公转对所有魂球同相：四颗一起转，队形不会散。
	_orbit_angle += deg_to_rad(orbit_speed) * delta

	if _detached:
		# 半径只增不减：四颗球绕着同一个圆心慢慢向外散开，而不是聚拢。
		_orbit_radius += orbit_expand_speed * delta
		_steer_center(delta)
		_orbit_center += _center_velocity * delta
	else:
		# BOSS 先没了（被击败 / 场景销毁）：立刻转自由段，不留在原地。
		if not is_instance_valid(_owner_node):
			_detach()
		else:
			_orbit_center = _owner_node.global_position
			if _phase >= detach_time:
				_detach()

	global_position = _orbit_center + _orbit_dir.rotated(_orbit_angle) * _orbit_radius

	if _grace > 0.0:
		_grace = maxf(_grace - delta, 0.0)
	if _phase >= lifetime:
		queue_free()


## 出生放大：start →（pop_time）mid →（grow_time）max。
func _grow() -> void:
	if _sprite == null:
		return
	_sprite.scale = Vector2.ONE * start_scale
	var tween := create_tween()
	tween.tween_property(_sprite, "scale", Vector2.ONE * mid_scale, maxf(pop_time, 0.001))
	tween.tween_property(_sprite, "scale", Vector2.ONE * max_scale, maxf(grow_time, 0.001))


## 脱离：环绕中心停在 owner 最后一帧的位置，从静止开始加速靠近玩家。
## 半径不收拢：保留脱离瞬间的半径，之后按 orbit_expand_speed 慢慢撒开。
func _detach() -> void:
	if _detached:
		return
	_detached = true
	_center_velocity = Vector2.ZERO
	_grace = hit_grace
	_arm_overlap_check()


## 整组靠近玩家：以 homing_turn_accel 加速「中心速度」指向玩家，而不是让每颗球各追各的。
func _steer_center(delta: float) -> void:
	var p := _player()
	if p == null:
		return
	var desired := (p.global_position - _orbit_center).normalized() * homing_speed
	_center_velocity = _center_velocity.move_toward(desired, homing_turn_accel * delta)


func _on_body_entered(body: Node) -> void:
	_try_hit(body)


## 宽限结束的那一刻补判一次重叠：生成 / 脱离瞬间已经压在玩家身上时，
## body_entered 不会补发，只能自己查一次。
func _arm_overlap_check() -> void:
	if is_inside_tree():
		get_tree().create_timer(maxf(hit_grace, 0.001)).timeout.connect(_check_overlap)


## 宽限结束后的补判（见 _arm_overlap_check）。
func _check_overlap() -> void:
	if _hit_done or not _can_hit or _grace > 0.0:
		return
	for body in get_overlapping_bodies():
		if _try_hit(body):
			return


## 命中结算：只打玩家组，命中即消失（每枚球只有一次伤害）。
func _try_hit(body: Node) -> bool:
	if _hit_done or not _can_hit or _grace > 0.0:
		return false
	if not body.is_in_group("player") or not body.has_method("take_damage"):
		return false
	_hit_done = true
	body.take_damage(damage, _source())
	queue_free()
	return true


## 判定圈：按「当前最终视觉半径 × hit_radius_ratio」换算。
func _apply_hit_radius(visual_radius: float) -> void:
	var shape_node := get_node_or_null("CollisionShape2D") as CollisionShape2D
	if shape_node != null and shape_node.shape is CircleShape2D:
		(shape_node.shape as CircleShape2D).radius = visual_radius * hit_radius_ratio


func _texture_width() -> float:
	if _sprite == null or _sprite.texture == null:
		return 0.0
	return _sprite.texture.get_size().x


## 伤害来源：owner 还活着就记 BOSS，否则记自己（玩家格挡方向 / 受击特效只要求 Node2D）。
func _source() -> Node2D:
	return _owner_node if is_instance_valid(_owner_node) else self


func _player() -> Node2D:
	var players := get_tree().get_nodes_in_group("player")
	return players[0] as Node2D if not players.is_empty() else null
