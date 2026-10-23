@tool
extends Node2D
class_name AuLockAreaPreview


## 编辑器专用预览层：只画相机锁定区域的范围。
##
## 由 AuCameraLockArea 在编辑器中动态创建（不设置 owner，因此不会写入 .tscn）。
## 运行游戏时该节点根本不会被创建，所以画面上绝对不会出现。


## ── 项目级默认预览样式 ──────────────────────────────
## 改这三个常量 = 改所有「没有在检查器里单独覆盖」的锁定区域。
## 单个区域想用别的颜色，就在场景里选中那个 Area2D，改检查器的 Preview Fill / Border。
const DEFAULT_FILL := Color(0.249, 1.046, 0.0, 0.30)
const DEFAULT_BORDER := Color(0.249, 1.046, 0.0, 0.90)
const DEFAULT_BORDER_WIDTH := 0.0


## 填充色（建议保持低 alpha）。由 AuCameraLockArea 写入。
var fill_color: Color = DEFAULT_FILL
## 边框色。由 AuCameraLockArea 写入。
var border_color: Color = DEFAULT_BORDER
## 边框宽度（本地像素）。为 0 时只画填充。由 AuCameraLockArea 写入。
var border_width: float = DEFAULT_BORDER_WIDTH
## 预览矩形尺寸，与 AuCameraLockArea.area_size 保持一致。
var rect_size: Vector2 = Vector2(600, 600)
## 是否以节点原点为中心，与 AuCameraLockArea.centered 保持一致。
var centered: bool = true


func _enter_tree() -> void:
	# 抬高绘制层级，避免被 Background 等后绘制的节点盖住。
	z_as_relative = false
	z_index = 1000


func _draw() -> void:
	var top_left := -rect_size / 2.0 if centered else Vector2.ZERO
	var rect := Rect2(top_left, rect_size)
	draw_rect(rect, fill_color)
	if border_width > 0.0:
		draw_rect(rect, border_color, false, border_width)
