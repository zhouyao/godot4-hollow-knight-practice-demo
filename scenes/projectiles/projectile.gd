extends Ammo
class_name Projectile


## 单发直射弹：飞行、命中结算、到点自毁。
## 同时是其它弹药复用的"子弹本体"：散射弹 / 延迟分裂弹默认都拿它当 bullet_scene。

## 飞行速度（像素 / 秒），默认 6 格每秒（6 * UNIT_SIZE）。
@export var speed: float = 6.0 * 96.0
## 存活时长（秒）：到点自毁，防止打空的投射物永远飞下去。
@export var lifetime: float = 3.0
## 是否穿透：false = 命中第一个目标后立即消失；true = 继续飞行（同一目标不会重复扣血）。
@export var pierce: bool = false
## 出生保护期（秒）：刚生成时很可能与脚下地面重叠，期间不结算命中，避免一出生就被地形秒删。
@export var spawn_grace: float = 0.08

var _dir: Vector2 = Vector2.RIGHT
var _damage: int = 1
var _hit: Array[Node] = []
var _grace := 0.0

func _ready() -> void:
	$LifeTimer.start(lifetime)

## 统一弹药接口（见 Ammo）：Enemy.launch_projectile() 只调用这一个入口。
func fire(dir: Vector2, damage: int) -> void:
	_dir = dir.normalized()
	_damage = damage
	rotation = _dir.angle()
	_grace = spawn_grace

func _physics_process(delta: float) -> void:
	if _grace > 0.0:
		_grace -= delta
	position += _dir * speed * delta

func _on_body_entered(body: Node2D) -> void:
	if _grace > 0.0:
		return
	# 命中谁由阵营决定（见 Ammo.faction / is_target），不再写死 group。
	if is_target(body):
		if not _hit.has(body):
			body.take_damage(_damage, self)
			_hit.append(body)
		if not pierce:
			queue_free()
	elif (body.collision_layer & Globals.LAYER_OBJECTS) != 0:
		queue_free()

func _on_life_timer_timeout() -> void:
	queue_free()
