@tool
extends Area2D
class_name CameraBoundsRect

## 可拖拽的相机边界组件：预置在 world_template.tscn 的 `CameraBounds` 节点上，
## 所有关卡继承后自动带一份。
##
## **矩形 = 相机「中心」允许活动的范围**（不是屏幕边的硬边界）。
## 在 2D 编辑器里选中子节点 `CollisionShape2D`，直接拖黄色 handles 改大小；
## 拖动本节点则整体平移。运行时由 GameSession 换算成 Camera2D 的 limit_*：
##
##   half = 视口尺寸 / (2 * zoom)
##   limit_left   = rect.position.x − half.x
##   limit_right  = rect.end.x      + half.x
##   limit_top    = rect.position.y − half.y
##   limit_bottom = rect.end.y      + half.y
##
## 这样就不必理解「limit 钳的是屏幕四条边」：把框的下边缘拖到玩家站立高度
## 附近即可，剩下的换算由组件负责。
##
## Area2D 只当形状容器用：collision_layer / mask 全 0，monitoring 关闭。
## 编辑器里画两层：绿框 = 拖出来的框（中心范围），红框 = 外扩 half 后的
## 实际可见范围。两个框内部默认完全透明，不遮挡关卡内容；绿框四角画实心圆，
## 颜色与半径可在「编辑器预览 Editor Preview」组里配。
## 内部子节点 `CollisionShape2D` 的调试背景色同样由 `fill_alpha` 控制，默认全透明。
## 运行时 _process 立即关闭、_draw 直接返回，零开销。

const REDRAW_INTERVAL := 0.5

@export_group("编辑器预览 Editor Preview")
## 编辑器 2D 视图里画出两层框（运行时无效）。
@export var debug_draw := true:
	set(value):
		debug_draw = value
		queue_redraw()

## 编辑器里画红色外框时假定的 zoom（编辑器拿不到运行时的 AuCameraRig）。
## 若关卡默认 zoom 不是 1，把它填成同一个值，预览的红框才与实际一致。
## 运行时不读它 —— 真正的换算用 GameSession 传入的 rig.zoom。
@export var preview_zoom: Vector2 = Vector2.ONE:
	set(value):
		preview_zoom = value
		queue_redraw()

## 矩形内部填充的不透明度：`0` = **完全透明**（默认），只留描边与四角实心圆，
## 不遮挡底下的关卡内容；调大才铺淡绿色块。
## 同时作用于两处：脚本画的绿框填充，以及 Godot 自带的 `CollisionShape2D`
## 调试形状填充（`debug_color` 的 alpha，编辑器绘制专用）。
@export_range(0.0, 1.0, 0.01) var fill_alpha: float = 0.0:
	set(value):
		fill_alpha = clampf(value, 0.0, 1.0)
		_sync_debug_color()
		queue_redraw()

## 内部绿框四个角上实心圆的颜色，与绿框描边色相互独立，可逐关单独配。
@export var corner_color: Color = Color(0.0, 0.0, 0.0):
	set(value):
		corner_color = value
		queue_redraw()

## 四角实心圆的半径（世界单位）。编辑器缩得很小时会自动放大，
## 保证至少有 6 个屏幕像素。最小值为 1。
@export var corner_size: float = 60.0:
	set(value):
		corner_size = maxf(value, 1.0)
		queue_redraw()

var _redraw_accum := 0.0


func _ready() -> void:
	# 形状子资源在继承场景间默认共享：改一个关卡的 size 会连带改掉别的关卡。
	_own_shape()
	if Engine.is_editor_hint():
		_sync_debug_color()
		set_process(true)
		queue_redraw()
	else:
		set_process(false)


func _notification(what: int) -> void:
	if Engine.is_editor_hint() and (what == NOTIFICATION_ENTER_TREE or what == NOTIFICATION_VISIBILITY_CHANGED):
		queue_redraw()


func _process(delta: float) -> void:
	if not Engine.is_editor_hint():
		set_process(false)
		return
	_redraw_accum += delta
	if _redraw_accum >= REDRAW_INTERVAL:
		_redraw_accum = 0.0
		queue_redraw()


func _own_shape() -> void:
	# 编辑器里 duplicate() 会往继承场景写一条 shape override，保存时把关卡里
	# 拖好的 size / position 改写掉。resource_local_to_scene 已保证不共享，
	# 编辑器环境直接交给它兜底（与 AuZone._own_shape() 同一处理）。
	if Engine.is_editor_hint():
		return
	var cs := get_node_or_null(^"CollisionShape2D") as CollisionShape2D
	if cs == null or cs.shape == null:
		return
	if not (cs.shape is RectangleShape2D):
		return
	if cs.shape.resource_local_to_scene:
		return
	cs.shape = cs.shape.duplicate()


## Godot 编辑器用 `CollisionShape2D.debug_color` 画碰撞形状的填充。
## 把它的 alpha 与 `fill_alpha` 对齐：默认 0 = 内部节点背景全透明，
## 只剩脚本画的描边与四角实心圆。
## 仅在编辑器里改（运行时不碰节点属性）；值相同时不写，避免反复把场景标脏。
func _sync_debug_color() -> void:
	if not Engine.is_editor_hint():
		return
	var cs := get_node_or_null(^"CollisionShape2D") as CollisionShape2D
	if cs == null:
		return
	var dc := cs.debug_color
	if is_equal_approx(dc.a, fill_alpha):
		return
	dc.a = fill_alpha
	cs.debug_color = dc


# ---------------------------------------------------------------- 数据

## 返回相机中心允许活动的世界矩形；形状无效时返回空 Rect2。
func get_center_rect() -> Rect2:
	var cs := get_node_or_null(^"CollisionShape2D") as CollisionShape2D
	if cs == null or not (cs.shape is RectangleShape2D):
		return Rect2()
	var shape := cs.shape as RectangleShape2D
	var s := cs.global_transform.get_scale()
	var size := Vector2(absf(shape.size.x * s.x), absf(shape.size.y * s.y))
	if size.x <= 0.0 or size.y <= 0.0:
		return Rect2()
	return Rect2(cs.global_position - size * 0.5, size)


## 换算成 Camera2D 的四条 limit（Rect2 的 position = left/top，end = right/bottom）。
## 供 GameSession._apply_camera_bounds() 调用。
func get_camera_limits(zoom: Vector2, viewport_size: Vector2) -> Rect2:
	var r := get_center_rect()
	if r.size == Vector2.ZERO:
		return Rect2()
	var z := Vector2(maxf(absf(zoom.x), 0.001), maxf(absf(zoom.y), 0.001))
	var half := viewport_size / (z * 2.0)
	return Rect2(r.position - half, r.size + half * 2.0)


# ---------------------------------------------------------------- 编辑器绘制

func _preview_half() -> Vector2:
	var vp := Vector2(
		float(ProjectSettings.get_setting("display/window/size/viewport_width", 1920)),
		float(ProjectSettings.get_setting("display/window/size/viewport_height", 1080))
	)
	var z := Vector2(maxf(absf(preview_zoom.x), 0.001), maxf(absf(preview_zoom.y), 0.001))
	return vp / (z * 2.0)


func _draw() -> void:
	if not Engine.is_editor_hint() or not debug_draw:
		return
	var rect := get_center_rect()
	if rect.size == Vector2.ZERO:
		return

	# 用世界坐标绘制（本节点若有 transform 也能对齐）
	draw_set_transform_matrix(get_global_transform().affine_inverse())

	var canvas_scale := 1.0
	var vp := get_viewport()
	if vp != null:
		canvas_scale = maxf(vp.get_global_canvas_transform().get_scale().x, 0.001)
	var lw := clampf(3.0 / canvas_scale, 2.0, 240.0)
	var dot_r := maxf(corner_size, 6.0 / canvas_scale)

	# 红：外扩 half 后的实际可见范围（屏幕四条边能到的地方），只描边
	var half := _preview_half()
	var outer := Rect2(rect.position - half, rect.size + half * 2.0)
	draw_rect(outer, Color(1.0, 0.35, 0.25, 0.95), false, lw)

	# 绿：拖出来的框 = 相机中心活动范围。默认内部完全透明，只留描边 + 四角实心圆
	if fill_alpha > 0.0:
		draw_rect(rect, Color(0.30, 1.0, 0.45, fill_alpha), true)
	draw_rect(rect, Color(0.30, 1.0, 0.45, 0.95), false, lw)
	var corners := [
		rect.position,
		Vector2(rect.end.x, rect.position.y),
		rect.end,
		Vector2(rect.position.x, rect.end.y),
	]
	for p in corners:
		draw_circle(p, dot_r, corner_color)
