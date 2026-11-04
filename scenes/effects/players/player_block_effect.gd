extends Node2D
class_name PlayerBlockEffect

## 玩家格挡火花：格挡成功时在身前生成一次短促火花，播完自动销毁。
## 由 PlayerInitial._on_blocked 在玩家身前 spawn，靠复制玩家全局坐标跟随，不依赖父子变换。

## 自身场景，spawn 时实例化。
## 必须用运行期 load 而非 const preload：preload 是编译期常量，会让本脚本预载
## "引用了本脚本的 .tscn"，形成脚本<->场景的编译期循环依赖，
## 编辑器按脚本顺序编译时会报 [ext_resource] referenced non-existent resource。
static var _scene: PackedScene

static func _get_scene() -> PackedScene:
	if _scene == null:
		_scene = load("res://scenes/effects/players/player_block_effect.tscn") as PackedScene
	return _scene

@onready var _anchor: Node2D = $Anchor
@onready var _sprite: AnimatedSprite2D = $Anchor/BlockDeffect

## 火花相对玩家的身前偏移（像素）：x 沿朝向自动翻到身前、y 略微抬高。可微调。
@export var front_offset: Vector2 = Vector2(40.0, -30.0)
## 翻转方向：+1 朝右用正向、朝左用镜像；-1 反之。按贴图原始朝向微调。
@export var face_sign: int = 1

var _player: PlayerInitial

static func spawn(player: PlayerInitial, parent: Node) -> PlayerBlockEffect:
	if player == null or parent == null or not parent.is_inside_tree():
		return null
	var eff := _get_scene().instantiate() as PlayerBlockEffect
	parent.add_child(eff)
	eff._setup(player)
	return eff

func _setup(player: PlayerInitial) -> void:
	_player = player
	global_position = player.global_position
	_refresh_orientation()
	if _sprite != null and not _sprite.is_playing():
		_sprite.play(&"block")

func _ready() -> void:
	if _player == null and get_parent() != null:
		_player = get_parent() as PlayerInitial
	_refresh_orientation()
	if _sprite != null and not _sprite.is_playing():
		_sprite.play(&"block")
	if _sprite != null:
		_sprite.animation_finished.connect(queue_free)

func _physics_process(_delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		return
	global_position = _player.global_position
	_refresh_orientation()

func _refresh_orientation() -> void:
	if _player == null:
		return
	var dir: int = _player.move_direction
	if dir == 0:
		dir = 1
	_anchor.position.x = dir * front_offset.x
	_anchor.position.y = front_offset.y
	_sprite.scale = Vector2(face_sign * dir * 0.3, 0.3)
