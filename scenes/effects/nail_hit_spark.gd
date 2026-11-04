extends AnimatedSprite2D
class_name nail_hit_spark

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

## 自身场景缓存：必须用运行期 load，不能用 const preload。
## preload 是编译期常量（写在函数体里也一样），会让本脚本预载"引用了本脚本的 .tscn"，
## 形成脚本<->场景的编译期循环依赖；编辑器按脚本顺序编译时会报
## [ext_resource] referenced non-existent resource at: res://scenes/effects/nail_hit_spark.gd
static var _scene: PackedScene

static func _get_scene() -> PackedScene:
	if _scene == null:
		_scene = load("res://scenes/effects/nail_hit_spark.tscn") as PackedScene
	return _scene

## 在 at 位置、以 parent 为父节点生成一个刀光，返回实例。
## 注意：必须先 add_child 再赋 global_position，否则 at 会被当成父节点局部坐标，
## 若 parent 自身有位移/缩放，刀光就会偏离受击点。
static func spawn(at: Vector2, parent: Node) -> nail_hit_spark:
	var spark := _get_scene().instantiate() as nail_hit_spark
	parent.add_child(spark)
	spark.global_position = at
	return spark
