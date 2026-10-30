extends Node2D

## 雨区组件根节点。
##
## zone_size 一处配置同时驱动"检测区域(AuZone)"与"雨幕视觉(Rain)"的大小；
## 位置由本节点在关卡中的摆放决定（Zone 与 Rain 都以本节点原点为中心对齐）。
##
## 注意：检测框会比可见雨幕大一圈（含雨的边缘淡化 region_fade），
## 这样玩家站在"看得见但已淡化的雨"里也能正确触发，避免"看得到雨却没音没动画"。


@export var zone_size: Vector2 = Vector2(256, 128):
	set(value):
		zone_size = value
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
		r.size = zone_size
	if z != null:
		# 检测框 = 雨幕核心尺寸 + 两侧淡化宽度，使整片可见雨都在触发范围内。
		var fade := 0.0
		if r != null:
			fade = r.region_fade
		z.size = zone_size + Vector2.ONE * 2.0 * maxf(fade, 0.0)
