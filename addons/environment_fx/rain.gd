@tool
extends Node2D
class_name RainParallax2D

## 玩家进入区域时发出（仅在 activate_with_player 打开时才会检测）。
signal player_entered(zone: Node, player: Node2D)
## 玩家离开区域时发出（仅在 activate_with_player 打开时才会检测）。
signal player_exited(zone: Node, player: Node2D)

@export_group("区域 Region")
## 雨生效的区域尺寸（像素）。centered = true 时节点原点为区域中心，否则为左上角。
@export var size: Vector2 = Vector2(1920, 1080):
	set(value):
		size = value
		_apply_region()

## 区域是否以节点原点为中心。
@export var centered: bool = true:
	set(value):
		centered = value
		_apply_region()

## 区域开关。false = 全屏显示（改造前的默认行为）。
@export var region_enabled: bool = true:
	set(value):
		region_enabled = value
		_apply_region()

## 包络衰减半宽（像素）：雨在区域外"逐渐变稀消失"的距离。很宽很柔，不构成可见轮廓。
@export var region_fade: float = 400.0:
	set(value):
		region_fade = value
		_apply_region()

@export_subgroup("包络形状 Envelope")
## 阵势尺度：越小云团越大（默认 0.0016 ≈ 625px 一团）。决定雨势起伏的破碎程度。
@export var cloud_noise_scale: float = 0.0016:
	set(value):
		cloud_noise_scale = value
		_apply_region()

## true = 椭圆包络（没有直边和直角），false = 矩形包络。
@export var elliptical: bool = true:
	set(value):
		elliptical = value
		_apply_region()

## 内部浓淡起伏：让雨不是均匀一片，更像真实阵雨。
@export var density_variation: float = 0.3:
	set(value):
		density_variation = value
		_apply_region()

## 区域包络的噪声扭曲幅度（像素）：让"区域边界"本身也不是直线/直角，而是有机形状。
@export var edge_noise: float = 320.0:
	set(value):
		edge_noise = value
		_apply_region()

## 几何边缘渐隐（UV 比例 0~0.5）：把 ColorRect / Parallax 平铺接缝的硬边抹掉，避免"层边缘的直线"。
@export var edge_margin: float = 0.04:
	set(value):
		edge_margin = value
		_apply_region()

## 淡出曲线指数（默认 1.0 = 不额外处理）。>1 时外侧拖更长的尾巴。
@export var edge_gamma: float = 1.0:
	set(value):
		edge_gamma = value
		_apply_region()

@export_group("密度 Density")
## 覆盖率：落雨的列占比。0 = 无雨，1 = 全部列落雨。
@export var coverage: float = 0.32:
	set(value):
		coverage = value
		_apply_density()

## 雨丝柔和度：越大雨丝边缘越朦胧。
@export var softness: float = 1.0:
	set(value):
		softness = value
		_apply_density()

## 雨的整体强度（0~1）。所有层共用，统一控制。
@export var density: float = 0.5:
	set(value):
		density = value
		_apply_density()

## 雨丝的"实度 / 粗细"（0~1）：越大雨丝越粗越实，越小越纤细通透。
@export var thickness: float = 1.0:
	set(value):
		thickness = value
		_apply_density()

@export_group("运动 Motion")
## 拖影长度倍率（运动模糊）：1.0 = 默认，>1 雨丝拖得更长更柔（慢快门感），<1 更短更利落。
@export var trail_scale: float = 0.27:
	set(value):
		trail_scale = value
		_apply_density()

## 雨的下落角度（度）。0 = 竖直下落；正值向右倾（受右侧来风影响），负值向左倾。
## 角度只改变雨丝的倾斜表现，下落速度保持不变。
@export_range(-75.0, 75.0, 0.5)
var angle_deg: float = -7.0:
	set(value):
		angle_deg = value
		_apply_angle()

## 雨丝紊乱度（0~1）：让每条雨丝各自有不同的斜度 / 粗细 / 轻微弯曲，
## 打破"整齐平行"的观感，越接近 1 越像真实风雨中的杂乱雨丝；0 = 整齐平行。
@export_range(0.0, 1.0, 0.01)
var chaos: float = 1.0:
	set(value):
		chaos = value
		_apply_chaos()

## 下落速度倍率：1.0 = 默认速度，>1 更快，<1 更慢，0 = 静止（雨丝停住但强度不变）。
## 仅缩放下落的时间推进速率，不改变雨势起伏、倾斜角与紊乱度。
@export_range(0.0, 4.0, 0.01)
var rain_speed: float = 1.2:
	set(value):
		rain_speed = value
		_apply_speed()

@export_group("水珠 Droplets")
## 水珠头淡入系数（0~1）：0 = 纯雨丝（改造前行为），1 = 水珠头完全显现。
## >0 时雨丝依旧存在，只是每条雨丝前端多出一个发亮的水珠头，补足“雨滴”观感。
@export_range(0.0, 1.0, 0.01)
var droplet: float = 1.0:
	set(value):
		droplet = value
		_apply_droplets()

## 水珠头大小（0~1）：越大珠头越粗。
@export_range(0.0, 1.0, 0.01)
var drop_size: float = 1.0:
	set(value):
		drop_size = value
		_apply_droplets()

## 水珠头纵向拉伸（0.1~1）：越小越接近正圆；约 0.22 可抵消“列宽/周期”在屏幕上的长宽比成正圆。
@export_range(0.1, 1.0, 0.01)
var drop_stretch: float = 1.0:
	set(value):
		drop_stretch = value
		_apply_droplets()

## 水珠头亮度（0.5~3）：>1 时比雨丝更亮，读起来像迎光的水珠。
@export_range(0.5, 3.0, 0.01)
var drop_brightness: float = 3.0:
	set(value):
		drop_brightness = value
		_apply_droplets()

@export_group("外观 Appearance")
## 雨的颜色。默认淡蓝（略带冷色，接近真实雨幕）。
@export var rain_color: Color = Color(0.72, 0.82, 1.0):
	set(value):
		rain_color = value
		_apply_color()

@export_group("玩家触发 Player Zone")
## 玩家进入区域才淡入、离开则淡出。false = 常驻显示（仅受区域遮罩限制）。
@export var activate_with_player: bool = false:
	set(value):
		activate_with_player = value
		_apply_player_zone()

## 淡入 / 淡出时长（秒）。
@export var fade_duration: float = 1.0

@export_group("视差 Parallax")
## 叠加层数与各层的视差倍率：数组长度 = 启用的层数（上限 = 场景里的层节点数）。
## 默认 1 层，改造前关卡里多个雨节点叠加的效果完全不受影响；
## 想让单个雨节点自带景深就填多个值，例如关卡里原来那 4 层：
## [Vector2(0.85, 0.85), Vector2(1, 1), Vector2(1.15, 1.15), Vector2(1.3, 1.3)]
@export var layer_scales: Array[Vector2] = [Vector2(1, 1)]:
	set(value):
		layer_scales = value
		_apply_layers()

## 整体视差倍率，乘在每层 layer_scales 之上（关卡里的 scroll_scale 覆写继续生效）。
@export var scroll_scale: Vector2 = Vector2.ONE:
	set(value):
		scroll_scale = value
		_apply_layers()

@export_group("渲染 Render")
## 绘制层级（写入 z_index）。两种用法：
##  · 前景遮罩：盖住玩家/敌人/掉落物 → 设成 > Pickup.draw_z 的值（建议 100）。
##  · 纯背景：沉到所有物体最后面        → 设成负数（建议 -10）。
## 默认 0：仅靠场景树顺序压住 z=0 实体。
@export var draw_z: int = 0:
	set(value):
		draw_z = value
		if is_inside_tree():
			z_index = value

@onready var _layers_root: Node2D = $Layers
@onready var _player_zone: Area2D = $PlayerZone
@onready var _player_shape: CollisionShape2D = $PlayerZone/CollisionShape2D

var _layers: Array[Parallax2D] = []
var _fade_tween: Tween = null
var _per_layer_material := false


func _ready() -> void:
	set_notify_transform(true)
	z_index = draw_z
	_collect_layers()
	# 每个实例必须持有独立的材质，否则多份雨会共用同一套区域参数。
	_ensure_unique_material()
	if _player_zone != null and not _player_zone.body_entered.is_connected(_on_body_entered):
		_player_zone.body_entered.connect(_on_body_entered)
		_player_zone.body_exited.connect(_on_body_exited)
	_apply_layers()
	_apply_region()
	_apply_density()
	_apply_color()
	_apply_angle()
	_apply_chaos()
	_apply_droplets()
	_apply_speed()
	_apply_player_zone()
	if activate_with_player and not Engine.is_editor_hint():
		# 玩家开局就在区域内时 body_entered 的时序不可靠，延迟一帧对齐初值。
		_sync_with_overlaps.call_deferred()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED:
		_apply_region()


func _draw() -> void:
	if not Engine.is_editor_hint():
		return
	var r := _local_region_rect()
	draw_rect(r, Color(0.45, 0.8, 1.0, 0.08))
	draw_rect(r, Color(0.45, 0.85, 1.0, 0.6), false, 2.0)
	if region_fade > 0.0:
		var inner := r.grow(-region_fade)
		if inner.size.x > 0.0 and inner.size.y > 0.0:
			draw_rect(inner, Color(0.45, 0.85, 1.0, 0.35), false, 1.0)


func _local_region_rect() -> Rect2:
	return Rect2(-size / 2.0, size) if centered else Rect2(Vector2.ZERO, size)


func _collect_layers() -> void:
	_layers.clear()
	if _layers_root == null:
		return
	for child in _layers_root.get_children():
		if child is Parallax2D:
			_layers.append(child)


func _color_rects() -> Array[ColorRect]:
	var rects: Array[ColorRect] = []
	for layer in _layers:
		var rect := layer.get_node_or_null("ColorRect") as ColorRect
		if rect != null:
			rects.append(rect)
	return rects


## 兜底：实例之间不能共用材质（正常由 .tscn 里的 resource_local_to_scene 保证）。
func _ensure_unique_material() -> void:
	if Engine.is_editor_hint():
		return
	var shared: Material = null
	for rect in _color_rects():
		if rect.material != null:
			shared = rect.material
			break
	if shared == null or shared.resource_local_to_scene:
		return
	var copy := shared.duplicate()
	for rect in _color_rects():
		if rect.material == shared:
			rect.material = copy
	_apply_color()


## 多层时给每层拆一份材质，这样每层的边界扰动可以各自错开（单层时没必要，保持共享）。
## count = 实际启用的层数，只有 >= 2 层才拆分。拆开后不再合并回去（无损，只是多几份副本）。
func _split_layer_materials(count: int) -> void:
	if _per_layer_material or count < 2:
		return
	var base: Material = null
	for rect in _color_rects():
		if rect.material != null:
			base = rect.material
			break
	if base == null:
		return
	for rect in _color_rects():
		if rect.material == base:
			rect.material = base.duplicate()
	_per_layer_material = true
	_apply_color()


func _apply_layers() -> void:
	if _layers.is_empty():
		return
	var count := mini(maxi(layer_scales.size(), 1), _layers.size())
	_split_layer_materials(count)
	for i in _layers.size():
		var layer_scale := Vector2.ONE
		if not layer_scales.is_empty():
			layer_scale = layer_scales[mini(i, layer_scales.size() - 1)]
		_layers[i].visible = i < count
		_layers[i].scroll_scale = layer_scale * scroll_scale
		if i >= count:
			continue
		# 每层边界错开：否则多层会在同一位置叠出一条硬边。
		# 材质共享时（单层）只写第一层，否则后面几层的写入会覆盖同一份材质。
		if not _per_layer_material and i > 0:
			continue
		var rect := _layers[i].get_node_or_null("ColorRect") as ColorRect
		if rect != null:
			var mat := rect.material as ShaderMaterial
			if mat != null:
				mat.set_shader_parameter(&"edge_seed", float(i) * 0.41)


func _apply_density() -> void:
	for rect in _color_rects():
		var mat := rect.material as ShaderMaterial
		if mat == null:
			continue
		mat.set_shader_parameter(&"density", clampf(density, 0.0, 1.0))
		mat.set_shader_parameter(&"thickness", clampf(thickness, 0.0, 1.0))
		mat.set_shader_parameter(&"coverage", clampf(coverage, 0.0, 1.0))
		mat.set_shader_parameter(&"softness", clampf(softness, 0.01, 1.0))
		mat.set_shader_parameter(&"trail_scale", maxf(trail_scale, 0.0))


func _apply_color() -> void:
	for rect in _color_rects():
		var mat := rect.material as ShaderMaterial
		if mat == null:
			continue
		mat.set_shader_parameter(&"rain_color", rain_color)


func _apply_angle() -> void:
	var rad := deg_to_rad(angle_deg)
	# 方向向量：竖直向下为 (0,1)，按角度旋转。x 取负号使正角度向右倾。
	# 归一化保证长度恒为 1，下落速度（着色器里的 length(speed)）不受影响。
	var dir := Vector2(-sin(rad), cos(rad)).normalized()
	for rect in _color_rects():
		var mat := rect.material as ShaderMaterial
		if mat == null:
			continue
		mat.set_shader_parameter(&"speed", dir)


func _apply_chaos() -> void:
	for rect in _color_rects():
		var mat := rect.material as ShaderMaterial
		if mat == null:
			continue
		mat.set_shader_parameter(&"chaos", clampf(chaos, 0.0, 1.0))


func _apply_droplets() -> void:
	for rect in _color_rects():
		var mat := rect.material as ShaderMaterial
		if mat == null:
			continue
		mat.set_shader_parameter(&"droplet", clampf(droplet, 0.0, 1.0))
		mat.set_shader_parameter(&"drop_size", clampf(drop_size, 0.0, 1.0))
		mat.set_shader_parameter(&"drop_stretch", clampf(drop_stretch, 0.1, 1.0))
		mat.set_shader_parameter(&"drop_brightness", maxf(drop_brightness, 0.5))


func _apply_speed() -> void:
	for rect in _color_rects():
		var mat := rect.material as ShaderMaterial
		if mat == null:
			continue
		mat.set_shader_parameter(&"fall_speed", maxf(rain_speed, 0.0))


func _apply_region() -> void:
	var local := _local_region_rect()
	var origin := global_position + local.position
	var maximum := origin + local.size
	for rect in _color_rects():
		var mat := rect.material as ShaderMaterial
		if mat == null:
			continue
		mat.set_shader_parameter(&"region_enabled", region_enabled)
		mat.set_shader_parameter(&"region_min", origin)
		mat.set_shader_parameter(&"region_max", maximum)
		mat.set_shader_parameter(&"region_fade", maxf(region_fade, 0.0))
		mat.set_shader_parameter(&"cloud_noise_scale", maxf(cloud_noise_scale, 0.0001))
		mat.set_shader_parameter(&"edge_noise", maxf(edge_noise, 0.0))
		mat.set_shader_parameter(&"density_variation", clampf(density_variation, 0.0, 1.0))
		mat.set_shader_parameter(&"elliptical", elliptical)
		mat.set_shader_parameter(&"edge_margin", clampf(edge_margin, 0.0, 0.5))
		mat.set_shader_parameter(&"edge_gamma", maxf(edge_gamma, 0.1))
	_apply_geometry()
	if _player_shape != null and _player_shape.shape is RectangleShape2D:
		_player_shape.shape.size = size
		_player_shape.position = local.get_center()
	queue_redraw()


## 让 ColorRect 比区域大一圈并居中于节点原点，使 ColorRect / Parallax 平铺的接缝
## 永远落在区域之外。之前"层边缘的直线"根因：区域中心正好压在平铺块的角上，
## 于是画布的硬边直接横穿雨区域。
func _apply_geometry() -> void:
	if _layers.is_empty():
		return
	var quad := size * 2.5
	if quad.x < 64.0:
		quad.x = 64.0
	if quad.y < 64.0:
		quad.y = 64.0
	for layer in _layers:
		layer.repeat_size = quad
		var rect := layer.get_node_or_null("ColorRect") as ColorRect
		if rect != null:
			rect.offset_left = -quad.x * 0.5
			rect.offset_top = -quad.y * 0.5
			rect.offset_right = quad.x * 0.5
			rect.offset_bottom = quad.y * 0.5


func _apply_player_zone() -> void:
	if _player_zone == null:
		return
	_player_zone.monitoring = activate_with_player and not Engine.is_editor_hint()
	_player_zone.monitorable = false
	_player_zone.visible = activate_with_player
	if not Engine.is_editor_hint():
		_set_rain_alpha(0.0 if activate_with_player else 1.0)
		# 运行中途切换 activate_with_player 时（尤其从关到开），body_entered
		# 不会因玩家已在区域内而重新触发，需立即按当前重叠状态对齐初始透明度，
		# 否则雨会卡在透明、直到玩家先出区再入区才出现。
		if is_inside_tree():
			_sync_with_overlaps.call_deferred()


func _on_body_entered(body: Node) -> void:
	if not activate_with_player:
		return
	if body != null and body.is_in_group("player"):
		player_entered.emit(self, body)
		_fade_to(1.0)


func _on_body_exited(body: Node) -> void:
	if not activate_with_player:
		return
	if body != null and body.is_in_group("player"):
		player_exited.emit(self, body)
		_fade_to(0.0)


func _fade_to(target: float) -> void:
	if _layers_root == null:
		return
	if _fade_tween != null and _fade_tween.is_running():
		_fade_tween.kill()
	if fade_duration <= 0.0:
		_set_rain_alpha(target)
		return
	_fade_tween = create_tween()
	_fade_tween.tween_property(_layers_root, "modulate:a", target, fade_duration)


func _set_rain_alpha(value: float) -> void:
	if _layers_root != null:
		_layers_root.modulate.a = value


func _sync_with_overlaps() -> void:
	if not activate_with_player or _player_zone == null:
		return
	var inside := false
	for body in _player_zone.get_overlapping_bodies():
		if body.is_in_group("player"):
			inside = true
			break
	_set_rain_alpha(1.0 if inside else 0.0)
