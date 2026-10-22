extends NavigationRegion2D
class_name AirspaceNavigation

## 飞行怪用的整块矩形空域导航区。
##
## 直接给 NavigationPolygon 喂 outline，再让 region 自己烘焙 ——
## NavigationPolygon.make_polygons_from_outlines() 在 4.7 已标记 deprecated，
## bake_navigation_polygon() 是它的官方替代（实测同样产出可用网格）。
##
## 关卡里只需要挪本节点的 position 与 airspace_size 就能圈出可飞范围。
## 不要用缩放来改范围：2D 导航多边形不做各向异性处理，比例尺会失真。
## 想让路径真正绕开墙体，需要把 NavigationObstacle2D 挂到墙体上后重新烘焙，
## 或改成带洞的多边形 —— 目前关卡还没有竖墙，先用整块空域。

## 空域尺寸（本地坐标，原点在左上角）
@export var airspace_size: Vector2 = Vector2(4800, 900)
## 导航层：与敌人 NavigationAgent2D 的 navigation_layers 保持一致（默认都是 1）
@export_flags_2d_navigation var airspace_layers: int = 1

func _ready() -> void:
	navigation_layers = airspace_layers
	navigation_polygon = _build_outline_polygon()
	# 延到第一帧之后烘焙：在 _ready() 里同步调用 bake_navigation_polygon() 时，
	# 实测该次烘焙不会落到已经进树的 region 上（navigation_polygon 事后被置空）
	bake_navigation_polygon.call_deferred()

## 左上角为原点，顺时针四角
func _build_outline_polygon() -> NavigationPolygon:
	var poly := NavigationPolygon.new()
	poly.add_outline(PackedVector2Array([
		Vector2.ZERO,
		Vector2(airspace_size.x, 0.0),
		airspace_size,
		Vector2(0.0, airspace_size.y),
	]))
	return poly
