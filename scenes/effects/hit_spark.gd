extends AnimatedSprite2D
class_name hit_spark

## 通用受击刀光特效：任意对象（草、敌人、宝箱等）受击时，
## 在受击点生成一次短促刀光，播完自动销毁。

@export var rand_rot_min := -50.0
@export var rand_rot_max := 0.0
@export var rand_scale_min := 0.5
@export var rand_scale_max := 1.0

func _ready() -> void:
	rotation_degrees = randf_range(rand_rot_min, rand_rot_max)
	var s := randf_range(rand_scale_min, rand_scale_max)
	scale = Vector2(s, s)
	play("nailhit")                       # 每帧约 0.05s，3 帧≈0.15s
	animation_finished.connect(queue_free) # 播完自毁

## 在 at 位置、以 parent 为父节点生成一个刀光，返回实例。
## （preload 放在函数内，避免 hit_spark.gd 与 hit_spark.tscn 互相预载的循环依赖）
## 注意：必须先 add_child 再赋 global_position，否则 at 会被当成父节点局部坐标，
## 若 parent 自身有位移/缩放，刀光就会偏离受击点。
static func spawn(at: Vector2, parent: Node) -> hit_spark:
	var scene := preload("res://scenes/effects/hit_spark.tscn")
	var spark := scene.instantiate()
	parent.add_child(spark)
	spark.global_position = at
	return spark
