@tool
extends Node2D
class_name CameraZoomZone

## `CameraBounds`（CameraBoundsRect）的子节点：一块「镜头放大 / 缩小」区域。
##
## 用法：在关卡的 `CameraBounds` 下新建子节点并挂本脚本，拖节点本身平移、
## 在 Inspector 里改 `size` / `zone_zoom`。玩家（"player" 组）走进矩形时，
## 相机 zoom 按 `CameraBounds.zoom_blend` 秒渐变到 `zone_zoom`；走出去回落到
## `CameraBounds.area_zoom`。`> 1` 放大（拉近）、`< 1` 缩小（拉远）。
##
## 重叠时 `priority` 大者生效，相同则靠前的子节点生效；`enabled = false` 可直接停用。
## 本节点只提供数据与编辑器预览，运行时零 _process 开销 —— 判定由 CameraBoundsRect 统一做。

const REDRAW_INTERVAL := 0.5

@export_group("缩放区域 Zoom Zone")
## 停用后该区域不参与判定（编辑器里仍可看见，方便留作备选）。
@export var enabled: bool = true:
	set(value):
		enabled = value
		queue_redraw()

## 矩形大小（世界单位）。缩放父节点也能改变实际覆盖范围，但不推荐。
@export var size: Vector2 = Vector2(960.0, 540.0):
	set(value):
		size = Vector2(maxf(value.x, 1.0), maxf(value.y, 1.0))
		queue_redraw()

## true = 节点位置是矩形中心（默认），false = 节点位置是左上角。
@export var centered: bool = true:
	set(value):
		centered = value
		queue_redraw()

## 进入本区域时的相机 zoom；0 / 负数会被 CameraBoundsRect 钳到 0.05。
@export var zone_zoom: Vector2 = Vector2(1.25, 1.25):
	set(value):
		zone_zoom = value
		queue_redraw()

## 多个区域重叠时的优先级，数值大者生效。
@export var priority: int = 0

@export_group("编辑器预览 Editor Preview")
## 2D 编辑器里画出矩形与 zoom 标签（运行时不画）。
@export var show_in_editor: bool = true:
	set(value):
		show_in_editor = value
		queue_redraw()

## 矩形内部填充的不透明度：0 = 完全透明，只留描边与标签。
@export_range(0.0, 1.0, 0.01) var fill_alpha: float = 0.08:
	set(value):
		fill_alpha = clampf(value, 0.0, 1.0)
		queue_redraw()

## 矩形描边 / 标签颜色。
@export var zone_color: Color = Color(0.35, 0.80, 1.0, 0.95):
	set(value):
		zone_color = value
		queue_redraw()

var _redraw_accum := 0.0


func _ready() -> void:
	if Engine.is_editor_hint():
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


# ---------------------------------------------------------------- 数据

## 世界坐标下的矩形（含父节点缩放），供 CameraBoundsRect 做命中判定。
func get_world_rect() -> Rect2:
	var s := get_global_transform().get_scale()
	var world_size := Vector2(absf(size.x * s.x), absf(size.y * s.y))
	var origin := global_position
	if centered:
		origin -= world_size * 0.5
	return Rect2(origin, world_size)


## margin > 0 时把矩形外扩，用于边缘迟滞。
func contains_point(pos: Vector2, margin := 0.0) -> bool:
	return get_world_rect().grow(margin).has_point(pos)


# ---------------------------------------------------------------- 编辑器绘制

func _draw() -> void:
	if not Engine.is_editor_hint() or not show_in_editor:
		return
	var rect := Rect2(-size * 0.5, size) if centered else Rect2(Vector2.ZERO, size)

	var canvas_scale := 1.0
	var vp := get_viewport()
	if vp != null:
		canvas_scale = maxf(vp.get_global_canvas_transform().get_scale().x, 0.001)
	var lw := clampf(2.0 / canvas_scale, 1.0, 120.0)

	if fill_alpha > 0.0:
		var fill := zone_color
		fill.a = fill_alpha
		draw_rect(rect, fill, true)
	draw_rect(rect, zone_color, false, lw)

	var font := ThemeDB.fallback_font
	if font == null:
		return
	var fs := int(clampf(16.0 / canvas_scale, 12.0, 160.0))
	var label := "zoom (%.2f, %.2f)" % [zone_zoom.x, zone_zoom.y]
	if is_equal_approx(zone_zoom.x, zone_zoom.y):
		label = "zoom x%.2f" % zone_zoom.x
	draw_string(font, rect.position + Vector2(lw * 2.0, fs * 1.2), label,
			HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs, zone_color)
