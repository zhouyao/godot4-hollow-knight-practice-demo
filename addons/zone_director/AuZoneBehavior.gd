extends Node
class_name AuZoneBehavior


## 区域效果挂件基类。
##
## 挂在 AuZone 下面作为子节点即可生效：由宿主 AuZone 在"目标进出"与"互斥通道得失"时回调。
## 与 AuCameraBehavior 同思路 —— 新增一种区域效果 = 新增一个 AuZoneBehavior 子类，
## AuZone 与 AuZoneDirector 都不用改。
##
## 惰性取宿主（与 State.machine 的惰性 getter 同范式），
## 这样挂件在 _ready 之前被回调也不会拿到 null。
##
## 注意：子类若重写 _ready()，务必调用 super._ready()，否则不会被登记。
## （宿主 AuZone 会在自己的 _ready 里扫描一遍子节点作为兜底。）


var _zone: AuZone


func _ready() -> void:
	# 子节点的 _ready 早于父节点，这里宿主已入树但可能还没跑自己的 _ready；
	# AuZone 的登记列表是普通成员，先于 _ready 初始化，因此此刻登记是安全的。
	var z := get_zone()
	if z != null:
		z.register_behavior(self)


## 宿主 AuZone（即父节点）。
func get_zone() -> AuZone:
	if _zone == null or not is_instance_valid(_zone):
		_zone = get_parent() as AuZone
	return _zone


## 目标进入宿主区域。
func on_entered(_body: Node2D) -> void:
	pass


## 目标离开宿主区域。
func on_exited(_body: Node2D) -> void:
	pass


## 宿主区域成为某互斥通道的胜者（例如从草区走回雨区，雨区重新拿到 surface）。
func on_gained(_channel: StringName) -> void:
	pass


## 宿主区域失去某互斥通道（例如走进嵌套在内层的草区，外层雨区让位）。
func on_lost(_channel: StringName) -> void:
	pass
