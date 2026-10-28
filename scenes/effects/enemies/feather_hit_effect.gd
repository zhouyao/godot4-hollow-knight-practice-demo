extends Node2D
class_name feather_hit_effect

@export var total_lifetime: float = 2.0

## 沿攻击方向的偏移：让羽毛从怪物身体附近迸发（不要跑到身后老远）。
## 怪物身体碰撞约 109×98（半宽 ~54、半高 ~49），取 20 仍在躯体上。
@export var rear_distance: float = 20.0
## 向上偏移：让羽毛略高于身体中心。rear + top 合起来就是"身体附近偏攻击方向"。
@export var top_distance: float = 20.0

## 【羽毛数量的主旋钮】本次迸发的羽毛总数，运行时均分给各粒子层。
## 调大 = 羽毛更多，调小 = 更少；0 = 不出羽毛。
## 它会覆盖 .tscn 里各 CPUParticles2D 的 amount，因此只改这里即可，
## 不必再去逐个改 4 个节点的 amount。
@export_range(0, 64, 1, "or_greater") var total_feathers: int = 18

## ===== 以下为"喷射感"旋钮：共同决定羽毛是"喷出去"还是"原地飘落" =====

## 初速度范围（像素/秒）。越大羽毛被"喷"得越远。
@export var burst_speed_min: float = 200.0
@export var burst_speed_max: float = 340.0
## 扩散角（度）：沿攻击方向张开的角度。越大越"散开"，越小越像一道集中喷射。
@export_range(0.0, 180.0) var burst_spread: float = 60.0
## 迸发原点半径（像素）：羽毛起始点散布范围。
## 调大 = 从身体一片区域同时冒出（更散）；调小 = 从一个点喷出（更集中）。
@export var origin_radius: float = 28.0
## 下坠重力：越小飞得越直越远；调大则快速下坠（更像飘落）。
@export var burst_gravity: float = 110.0
## 单只羽毛存活时间（秒）：配合速度决定能飞多远；越短越干脆利落。
@export var feather_lifetime: float = 1.1

## 由 HitEffect.spawn 在生成时按"伤害来源→被击者"方向填入（即玩家击退怪物的方向）。
## 为 ZERO 时回落到默认向上喷，兼容无来源（陷阱等）的情况。
var _hit_direction: Vector2 = Vector2.ZERO

func set_hit_direction(dir: Vector2) -> void:
	_hit_direction = dir

## 方向已由 HitEffect.spawn 在 add_child 之前写入，故 _ready 里可直接按方向定位。
func _ready() -> void:
	var directional := _hit_direction != Vector2.ZERO
	# 有方向时用击退方向；否则默认向上。
	var dir := _hit_direction if directional else Vector2(0, -1)
	# 发射原点：击退方向（身后）偏移 + 向上偏移 = 怪物后上方。
	var offset := dir * (rear_distance if directional else 0.0) + Vector2(0.0, -top_distance)
	var layers := _distribute_amounts()
	for child in layers:
		child.direction = dir
		child.position = offset
		_apply_burst(child)
		# 延后一帧再喷：等 spawner 把 global_position 落到命中点，避免在原点闪一帧。
		# 方向与偏移已在本函数内设好，延后不影响正确性。
		child.restart.call_deferred()
	var t := get_tree().create_timer(total_lifetime)
	t.timeout.connect(queue_free)

## 把 total_feathers 均匀分给各粒子层（余数补给前几层），并返回这些层。
## 这样"羽毛总数"只需改一个导出项，不必逐个改 4 个节点的 amount。
func _distribute_amounts() -> Array[CPUParticles2D]:
	var layers: Array[CPUParticles2D] = []
	for child in get_children():
		if child is CPUParticles2D:
			layers.append(child as CPUParticles2D)
	if layers.is_empty():
		return layers
	var n := maxi(total_feathers, 0)
	# 这里就是要整数除法：羽毛必须按整只分给各层，余数再补给前几层。
	@warning_ignore("integer_division")
	var base := n / layers.size()
	var extra := n % layers.size()
	for i in layers.size():
		layers[i].amount = base + (1 if i < extra else 0)
	return layers

## 应用"喷射感"参数：速度 / 扩散角 / 原点半径 / 重力 / 存活时间。
## 会覆盖 .tscn 里各节点的静态值，因此统一在这里调即可。
func _apply_burst(p: CPUParticles2D) -> void:
	p.initial_velocity_min = burst_speed_min
	p.initial_velocity_max = burst_speed_max
	p.spread = burst_spread
	p.emission_ring_radius = origin_radius
	p.emission_ring_inner_radius = 0.0
	p.gravity = Vector2(0.0, burst_gravity)
	p.lifetime = feather_lifetime
