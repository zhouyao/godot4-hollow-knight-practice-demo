extends Node2D
class_name ParallaxBg

## 以世界坐标为锚点的背景视差。两种锚定模式：
##
## 1. 旧模式（默认，各层以自己的位置为锚）：
##      pos = camera_center - (camera_center - initial_pos) * pow(k, move_layer)
##    只有相机中心正好落在**该层自己的位置**时，这一层才回到编辑器里的位置；
##    因为每层锚点不同，所以在任何机位下都不可能同时和编辑器里的构图一致。
##
## 2. 关卡参考机位模式（关卡根节点开了 parallax_reference_enabled 时）：
##      pos = initial_pos + (camera_center - reference_camera) * (1 - pow(k, move_layer))
##    本关所有层共用同一个参考机位，相机走到参考机位时**整个背景与编辑器完全重合**，
##    之后随相机移动按 move_layer 正常视差。做关卡时看到什么，进场就是什么。
##
## 项目其它关卡用 Parallax2D；但 Parallax2D 的子节点坐标是相对相机的，
## 无法直接沿用源项目以世界坐标为锚点的层级数据。MossHole 的 95 个背景层
## 需要逐层保真，因此这里用等价公式实现。

@export var move_layer: int = 0
@export var k: float = 1.05

var _initial_pos := Vector2.ZERO
## 关卡参考机位（相机中心的世界坐标）；_use_reference 为 false 时走旧公式。
var _reference_cam := Vector2.ZERO
var _use_reference := false


func _ready() -> void:
	_initial_pos = global_position
	_resolve_reference()


func _process(_delta: float) -> void:
	if move_layer == 0:
		return
	var cam := get_viewport().get_camera_2d()
	if cam == null:
		return
	var cam_pos := cam.get_screen_center_position()
	var factor := pow(k, move_layer)
	if _use_reference:
		# 参考机位处 offset = 0：运行时位置 == 编辑器里摆的位置
		global_position = _initial_pos + (cam_pos - _reference_cam) * (1.0 - factor)
	else:
		global_position = cam_pos - (cam_pos - _initial_pos) * factor


## 向上找关卡根节点（WorldArea）要本关的参考机位；没开就用旧公式，行为与以前完全一致。
func _resolve_reference() -> void:
	var node := get_parent()
	while node != null:
		if node.has_method(&"has_parallax_reference") and node.call(&"has_parallax_reference"):
			_reference_cam = node.call(&"get_parallax_reference_camera")
			_use_reference = true
			return
		node = node.get_parent()
