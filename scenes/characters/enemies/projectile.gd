extends Area2D
class_name Projectile


## 飞行速度（像素 / 秒），默认 6 格每秒（6 * UNIT_SIZE）。
@export var speed: float = 6.0 * 96.0
## 存活时长（秒）：到点自毁，防止打空的投射物永远飞下去。
@export var lifetime: float = 3.0
## 是否穿透：false = 命中第一个玩家后立即消失；true = 继续飞行（同一目标不会重复扣血）。
@export var pierce: bool = false

var _dir: Vector2 = Vector2.RIGHT
var _damage: int = 1
var _hit: Array[Node] = []

func _ready() -> void:
	$LifeTimer.start(lifetime)

func setup(dir: Vector2, damage: int) -> void:
	_dir = dir.normalized()
	_damage = damage
	rotation = _dir.angle()

func _physics_process(delta: float) -> void:
	position += _dir * speed * delta

func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		if not _hit.has(body):
			body.take_damage(_damage, self)
			_hit.append(body)
		if not pierce:
			queue_free()
	elif (body.collision_layer & Globals.LAYER_OBJECTS) != 0:
		queue_free()

func _on_life_timer_timeout() -> void:
	queue_free()
