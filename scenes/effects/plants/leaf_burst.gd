extends Node2D
class_name leaf_burst

## 草被割断时迸发的叶片粒子系统。
## 因本版本 CPUParticles2D 不支持逐粒子随机帧，
## 这里用 3 个发射器各取叶片精灵表（32×96）中的一横行（AtlasTexture）来制造 3 种叶形差异。
##
## 起爆必须推迟到本帧末：_ready() 在调用方 add_child() 时就立刻执行，
## 那时调用方还没把本节点摆到草的位置、也还没重置物理插值；
## one_shot + explosiveness=1.0 会让整批叶片在旧位置一次打完，屏幕上什么也看不到。
## 与 chest_burst.gd 的做法一致。

@export var total_lifetime: float = 2.0

## 发射原点相对草的偏移（略偏上，让叶片从草丛中上部迸发），便于调参。
@export var origin_offset: Vector2 = Vector2(0.0, -20.0)

func _ready() -> void:
	# 这里只配置、不起爆，等调用方把 global_position 摆好之后再发射。
	for child in get_children():
		if child is CPUParticles2D:
			var p := child as CPUParticles2D
			p.position = origin_offset
			p.emitting = false
	var t := get_tree().create_timer(total_lifetime)
	t.timeout.connect(queue_free)
	call_deferred("_ignite")


func _ignite() -> void:
	if not is_inside_tree():
		return
	for child in get_children():
		if child is CPUParticles2D:
			(child as CPUParticles2D).emitting = true
