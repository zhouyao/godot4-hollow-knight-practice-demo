extends Node2D
class_name PlayerDashEffect

## 玩家冲刺残影（地面 / 空中通用）。
## 由 dash 状态在 enter() 时 spawn，在 exit()（dash 结束或被打断）时调用 finish() 做淡出销毁。
## 默认停在冲刺起点（玩家冲出去后它自然留在尾部，即经典 afterimage）；
## dash 期间循环播放 dash_effect 动画，并按玩家朝向水平翻转，通过定位节点 Anchor 锚定在玩家身后；
## 想让它全程贴着玩家走，可在检查器把 follow_player 勾上。dash 结束先淡出再自动 queue_free。


## 自身场景，spawn 时实例化。
## 必须用运行期 load 而非 const preload：preload 是编译期常量（写在函数体里也一样），
## 会让本脚本预载"引用了本脚本的 .tscn"，形成脚本<->场景的编译期循环依赖，
## 编辑器按脚本顺序编译时会报 [ext_resource] referenced non-existent resource。
static var _scene: PackedScene

static func _get_scene() -> PackedScene:
	if _scene == null:
		_scene = load("res://scenes/effects/players/player_dash_effect.tscn") as PackedScene
	return _scene

@onready var _anchor: Node2D = $Anchor
@onready var _sprite: AnimatedSprite2D = $Anchor/DashEffect

## 残影锚定在玩家身后的偏移（像素）：x 为水平（沿冲刺反方向，按朝向自动翻转）、y 为垂直。
## 水平默认已大于玩家半身宽，确保残影从身体后侧露出；按贴图布局与手感微调。可调。
@export var behind_offset: Vector2 = Vector2(200.0, -50.0)
## 是否全程贴着玩家跟随：false（默认）= 停在冲刺起点形成尾部残影；true = 实时跟随玩家位置。可调。
@export var follow_player: bool = false
## 淡出时长（秒）：dash 结束后渐隐再到销毁。可调。
@export var fade_duration: float = 0.16
## 总存活上限（秒）：即便 finish 未被调用也强制淡出，杜绝残留节点。可调。
@export var max_lifetime: float = 1.2
## 绘制层级：>0 画在玩家/背景之上（更显眼）；想压在玩家身后改回负数（如 -1）。可调。
@export var z_index_behind: int = 1
## 翻转方向：+1 表示朝右用正向、朝左用镜像；-1 反之。按贴图原始朝向调。可调。
@export var face_sign: int = -1
## 空中冲刺残影相对地面额外的垂直下移量（像素），0 表示地面/空中一致。可调。
@export var air_vertical_offset: float = -70.0

var _player: PlayerInitial
var _following := true
var _finished := false
var _is_air := false


## 在 player 所在场景生成一份冲刺残影，返回实例（失败返回 null）。
## parent 必须已入树；通常传 player.get_parent()（世界节点）。
## 残影靠复制玩家全局坐标跟随，不依赖父子变换，避免淡出时还跟着玩家跑。
static func spawn(player: PlayerInitial, parent: Node) -> PlayerDashEffect:
	if player == null or parent == null or not parent.is_inside_tree():
		return null
	var eff := _get_scene().instantiate() as PlayerDashEffect
	parent.add_child(eff)
	eff._setup(player)
	return eff


func _setup(player: PlayerInitial) -> void:
	_player = player
	_is_air = not player.is_on_floor()
	# 出生即钉在玩家当前位置（冲刺起点）；之后是否继续跟随由 follow_player 决定。
	global_position = player.global_position
	z_index = z_index_behind
	_refresh_orientation()
	if _sprite != null and not _sprite.is_playing():
		_sprite.play(&"dash_effect")
	# 保险：到达总存活上限强制收尾，确保不会因异常路径留下节点。
	var life := get_tree().create_timer(max_lifetime)
	life.timeout.connect(_force_finish)


func _ready() -> void:
	# 直接实例化（非经 spawn）时也能跑：默认跟随父节点。
	if _player == null and get_parent() != null:
		_player = get_parent() as PlayerInitial
		_refresh_orientation()
		if _sprite != null and not _sprite.is_playing():
			_sprite.play(&"dash_effect")


func _physics_process(_delta: float) -> void:
	if not _following or _player == null or not is_instance_valid(_player):
		return
	# 默认不跟随：残影停在冲刺起点（尾部）。勾上 follow_player 才实时贴着玩家。
	if follow_player:
		global_position = _player.global_position
	_refresh_orientation()


## 按玩家朝向刷新：定位节点锚到身后、精灵按移动方向水平翻转。
func _refresh_orientation() -> void:
	if _player == null:
		return
	var dir: int = _player.move_direction
	if dir == 0:
		dir = 1
	# 锚点放在冲刺方向的反方向（身后）：x 水平、y 垂直（两者均可调）。
	_anchor.position.x = -dir * behind_offset.x
	# 空中冲刺残影在垂直偏移基础上再略向下垫一点，体现"状态判定"的差异。
	_anchor.position.y = behind_offset.y + (air_vertical_offset if _is_air else 0.0)
	# 精灵按朝向翻转：face_sign 决定镜像方向，与贴图原始朝向匹配即可。
	_sprite.scale.x = face_sign * dir
	_sprite.scale.y = 1.0


## 由 dash 状态在 exit 时调用：开始淡出并自动销毁。多次调用安全。
func finish() -> void:
	if _finished:
		return
	_finished = true
	_following = false
	if _sprite == null:
		queue_free()
		return
	var tw := create_tween()
	tw.tween_property(_sprite, "modulate:a", 0.0, fade_duration)
	tw.tween_callback(queue_free)


## 总存活上限触发时的强制收尾（与 finish 共享逻辑，幂等）。
func _force_finish() -> void:
	if not is_instance_valid(self):
		return
	finish()
