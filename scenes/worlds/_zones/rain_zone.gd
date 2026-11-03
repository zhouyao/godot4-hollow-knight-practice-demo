@tool
extends Node2D

## 雨区组件根节点。
##
## zone_size 决定"这一片雨区有多大"；雨幕视觉(Rain)再按 visual_scale 放大一圈，
## 位置由本节点在关卡中的摆放决定（Zone 与 Rain 都以本节点原点为中心对齐）。
##
## 为什么要放大视觉：Rain 的区域掩膜是按世界坐标裁出来的，size 正好等于视口
## (1920x1080) 时，相机只要偏一点，屏幕边缘就会露出"雨区边界"（看起来只有半屏在下雨）。
## 放大到 1.5 屏后，边界抖动都落在画面之外，画面里始终是"整片在下雨"。
##
## 注意：检测框仍然只围绕 zone_size 展开（比 zone_size 大一圈 region_fade），
## 保证玩家站在"看得见但已淡化的雨"里也能正确触发；视觉多出来的那圈是纯装饰，
## 只负责不露出边界，不参与水花/环境音判定。需要更大的判定范围请调 zone_size。


## 雨区的玩法尺寸（像素）。视觉雨幕 = 该尺寸 × visual_scale。
@export var zone_size: Vector2 = Vector2(256, 128):
	set(value):
		zone_size = value
		_apply_size()

## 视觉雨幕相对 zone_size 的放大倍率。1.0 = 视觉与玩法尺寸相同（正好一屏，
## 相机一偏就会缺角）；默认 1.5 让雨幕大于一屏，画面里看不到雨区边界。
@export_range(1.0, 4.0, 0.05) var visual_scale: float = 1.5:
	set(value):
		visual_scale = value
		_apply_size()


func _ready() -> void:
	_apply_size()
	# 等整条 _ready 链（含 AuZone 自身默认碰撞框的创建/覆盖）全部落定后，
	# 再校准一次：保证检测框最终等于 zone_size + 2*region_fade，
	# 而不是被插件默认的碰撞框尺寸覆盖（否则玩家在地面行走时会落在检测框之外）。
	call_deferred("_apply_size")


func _apply_size() -> void:
	var z := get_node_or_null("Zone") as AuZone
	var r := get_node_or_null("Rain") as RainParallax2D
	if r != null:
		r.size = zone_size * maxf(visual_scale, 1.0)
	if z != null:
		# 检测框 = 玩法尺寸 + 两侧淡化宽度，使整片可见雨都在触发范围内。
		var fade := 0.0
		if r != null:
			fade = r.region_fade
		z.size = zone_size + Vector2.ONE * 2.0 * maxf(fade, 0.0)
