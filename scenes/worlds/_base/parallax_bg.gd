extends Node2D
class_name ParallaxBg

## 精确还原源项目的背景视差公式：
##   pos = camera_center - (camera_center - initial_pos) * pow(k, move_layer)
##
## 项目其它关卡用 Parallax2D；但 Parallax2D 的子节点坐标是相对相机的，
## 无法直接沿用源项目以世界坐标为锚点的层级数据。MossHole 的 95 个背景层
## 需要逐层保真，因此这里用等价公式实现。

@export var move_layer: int = 0
@export var k: float = 1.05

var _initial_pos := Vector2.ZERO


func _ready() -> void:
	_initial_pos = global_position


func _process(_delta: float) -> void:
	if move_layer == 0:
		return
	var cam := get_viewport().get_camera_2d()
	if cam == null:
		return
	var cam_pos := cam.get_screen_center_position()
	global_position = cam_pos - (cam_pos - _initial_pos) * pow(k, move_layer)
