extends Node2D
class_name leaf_burst

## 草被割断时迸发的叶片粒子系统。
## 因本版本 CPUParticles2D 不支持逐粒子随机帧，
## 这里用 3 个发射器各取叶片精灵表（32×96）中的一横行（AtlasTexture）来制造 3 种叶形差异。

@export var total_lifetime: float = 2.0

## 发射原点相对草的偏移（略偏上，让叶片从草丛中上部迸发），便于调参。
@export var origin_offset: Vector2 = Vector2(0.0, -20.0)

func _ready() -> void:
	for child in get_children():
		if child is CPUParticles2D:
			child.position = origin_offset
			child.emitting = false     # 先关掉，避免在原点位置先冒一帧
			child.emitting = true
	var t := get_tree().create_timer(total_lifetime)
	t.timeout.connect(queue_free)
