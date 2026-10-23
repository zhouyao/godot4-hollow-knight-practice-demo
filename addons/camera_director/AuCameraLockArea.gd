@tool
extends Area2D
class_name AuCameraLockArea


## 编辑器预览子节点的名字（不设 owner，不会被保存进 .tscn）。
const PREVIEW_NODE_NAME := "EditorPreview"
const PREVIEW_SCRIPT: GDScript = preload("res://addons/camera_director/AuLockAreaPreview.gd")


## 水平锁定参考点：角色停留在本区域内时，相机 X 轴吸附到该 Marker2D。
@export var horizontal_lock_marker: Marker2D
## 垂直锁定参考点：相机 Y 轴吸附到该 Marker2D。不指定则只锁水平。
@export var vertical_lock_marker: Marker2D

## 在本区域内是否允许抬头（影响 AuCameraDirector.look_up() 是否生效）。
@export var can_look_up: bool = false
## 在本区域内是否允许低头（影响 AuCameraDirector.look_down() 是否生效）。
@export var can_look_down: bool = false

## 区域尺寸（像素）：决定碰撞矩形的大小，也就决定了相机锁定的触发范围。
@export var area_size: Vector2 = Vector2(600, 600):
	set(value):
		area_size = value
		_apply_size()
		_update_preview()

## 碰撞矩形是否以节点原点为中心。false 时矩形从原点向右下方向展开。
@export var centered: bool = true:
	set(value):
		centered = value
		_apply_size()
		_update_preview()

## 检测用物理层：只有该层的 body 进出区域才会注册 / 注销相机锁定，默认第 5 层（值 16）。
@export_flags_2d_physics var detect_layer: int = 16:
	set(value):
		detect_layer = value
		collision_layer = value

## 编辑器预览填充色：只在编辑器视口绘制，运行游戏时不会出现。
@export var preview_fill: Color = Color(0.249, 1.046, 0.0, 0.596):
	set(value):
		preview_fill = value
		_update_preview()

## 编辑器预览边框色。
@export var preview_border: Color = Color(0.249, 1.046, 0.0, 0.596):
	set(value):
		preview_border = value
		_update_preview()

## 编辑器预览边框宽度（本地像素）。设为 0 则只画填充。
@export var preview_border_width: float = 0.0:
	set(value):
		preview_border_width = value
		_update_preview()


func _ready() -> void:
	_get_or_create_collision()
	collision_layer = detect_layer
	_apply_size()
	_update_preview()

	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)
	if not body_exited.is_connected(_on_body_exited):
		body_exited.connect(_on_body_exited)


func _get_or_create_collision() -> CollisionShape2D:
	var collision := get_node_or_null("CollisionShape2D") as CollisionShape2D
	if collision != null:
		return collision
	collision = CollisionShape2D.new()
	collision.name = "CollisionShape2D"
	collision.shape = RectangleShape2D.new()
	add_child(collision)
	return collision


func _apply_size() -> void:
	var collision := get_node_or_null("CollisionShape2D") as CollisionShape2D
	if collision == null or not (collision.shape is RectangleShape2D):
		return
	collision.shape.size = area_size
	collision.position = Vector2.ZERO if centered else area_size / 2.0


## 同步编辑器预览层。运行游戏时直接跳过，预览节点不会被创建。
func _update_preview() -> void:
	if not Engine.is_editor_hint():
		return

	var preview := get_node_or_null(PREVIEW_NODE_NAME) as Node2D
	if preview == null:
		preview = PREVIEW_SCRIPT.new() as Node2D
		preview.name = PREVIEW_NODE_NAME
		add_child(preview)

	preview.set("fill_color", preview_fill)
	preview.set("border_color", preview_border)
	preview.set("border_width", preview_border_width)
	preview.set("rect_size", area_size)
	preview.set("centered", centered)
	preview.queue_redraw()


func _on_body_entered(_body: Node2D) -> void:
	AuCameraDirector.register_area(self)


func _on_body_exited(_body: Node2D) -> void:
	AuCameraDirector.unregister_area(self)
