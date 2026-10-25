extends ColorRect
class_name CooldownMask

## 技能冷却遮罩：从 12 点方向顺时针覆盖的半透明扇形，随剩余冷却收缩，归零自动隐藏。
## 只画一个扇形而不是整体灰化，是为了让"还剩多久"一眼可读（配合 CooldownLabel 的秒数）。
## 遮罩节点本身与 Icon 同矩形、同圆角：扇形在 shader 里被圆角矩形 SDF 裁剪，
## 不会像旧版"对角线大扇形"那样溢出到图标外的槽位底板上。

const MASK_SHADER := preload("res://shaders/cooldown_mask.gdshader")
const MASK_COLOR := Color(0.0, 0.0, 0.0, 0.65)

## 圆角半径，与槽位 StyleBoxFlat 的 corner_radius 保持一致。
@export var corner_radius: float = 6.0

## 当前遮罩比例：1 = 刚进入冷却（整圈盖满），0 = 可用。
var ratio: float = 0.0


func _ready() -> void:
	var shader_material := ShaderMaterial.new()
	shader_material.shader = MASK_SHADER
	material = shader_material
	resized.connect(_update_material)
	_update_material()


func set_ratio(value: float) -> void:
	var next := clampf(value, 0.0, 1.0)
	if is_equal_approx(next, ratio):
		return
	ratio = next
	visible = ratio > 0.0
	_update_material()


func _update_material() -> void:
	if material == null:
		return
	material.set_shader_parameter("ratio", ratio)
	material.set_shader_parameter("corner_radius", corner_radius)
	material.set_shader_parameter("mask_color", MASK_COLOR)
	material.set_shader_parameter("rect_size", size)
