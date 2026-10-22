extends Area2D
class_name Projectile

## 敌人投射物（吐东西小怪 / BOSS 远程技能复用）。命中玩家造成伤害后消失（或穿透）。
## 由 Enemy.launch_projectile() 生成并调用 setup() 设定方向与伤害。

@export var speed: float = 6.0 * 96.0
@export var lifetime: float = 3.0
## 是否穿透：false 命中玩家即销毁，true 对同一目标只结算一次但仍存活
@export var pierce: bool = false

var _dir: Vector2 = Vector2.RIGHT
var _damage: int = 1
var _hit: Array[Node] = []

## 生命周期计时放在 _ready() 而不是 setup()：发射方可能先 setup() 再 add_child()，
## 在场景树外调 Timer.start() 会报 "not inside the scene tree" 且计时根本不生效
## （投射物永不销毁）。放 _ready() 后，setup() 在 add_child 之前或之后调用都成立。
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
	elif body.collision_layer == Globals.LAYER_OBJECTS:
		# 撞到地形 / 箱子即销毁
		queue_free()

func _on_life_timer_timeout() -> void:
	queue_free()
