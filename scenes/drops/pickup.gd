extends Area2D
class_name Pickup


## 进 Inventory 的键（&"coin" / &"food"）。
@export var item_id: StringName = &"coin"
## 本实体携带的数量，由 DropSpawner 写入。
@export var amount: int = 1

@export_group("运动")
## 出生后多久才可被拾取（秒）：先让玩家看清掉的是什么。
@export var pick_delay: float = 0.05
## 抛出初速度的随机范围（像素/秒）：x 左右散开，y 向上（负值）。
@export var launch_speed_x: float = 140.0
@export var launch_speed_y: float = -320.0
## 下落加速度：注意不能叫 gravity —— Area2D 自带 gravity 属性（点重力），重名会编译失败。
@export var fall_gravity: float = 1400.0
## 落地后的一次小弹跳系数（0 = 不弹）。
@export var bounce: float = 0.35

@export_group("拾取")
## 磁吸半径（像素）：需与场景里 CollisionShape2D 的半径保持一致。
@export var magnet_radius: float = 120.0
## 真正吃掉的距离阈值（像素）。
@export var pick_radius: float = 24.0
## 吸附飞行速度（像素/秒）。
@export var magnet_speed: float = 900.0

@export_group("生命周期")
## 存活时长（秒）：兜底清理掉出地图 / 未被拾取的残留物。
@export var life_time: float = 20.0
## 消失前闪烁的提前量（秒）。
@export var blink_time: float = 3.0

@export_group("表现")
## 绘制层级：默认抬到 1，保证掉落物压在敌人尸体与玩家之上。
## 场景树里 Enemies 容器排在 Drops 之后、且全局都没开 y_sort，
## 纯按树序绘制的话刚爆出来的金币会被尸体整个盖住，玩家根本看不见。
## 这里抬的是自身 z（z_as_relative 默认开，会叠加到父容器上），
## 不搬动容器顺序 —— 重排模板会打乱 level_*.tscn 里继承节点的 index。
@export var draw_z: int = 1

enum Phase { SETTLE, IDLE, MAGNET }

var _phase := Phase.SETTLE
var _vel := Vector2.ZERO
var _ground_y := 0.0
var _age := 0.0
var _player: Node2D = null
## 是否已由 DropSpawner 抛出：场景里预置的 Pickup（放在 Items 下）不走 launch()。
var _launched := false
## 地面高度尚未探测：统一推迟到第一个物理帧（射线查询必须在物理帧内）。
var _need_probe := true

@onready var _audio: AudioStreamPlayer2D = $Audio/Pickup as AudioStreamPlayer2D


func _ready() -> void:
	# 入树后立刻同步一次插值状态，避免从父节点原点"飞"过来。
	reset_physics_interpolation()
	z_index = draw_z
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


## 由 DropSpawner 在 add_child 之后调用；只记速度，探测推迟到物理帧。
func launch(dir: Vector2) -> void:
	_vel = dir
	_launched = true


func _physics_process(delta: float) -> void:
	if _need_probe:
		_need_probe = false
		_ground_y = _probe_ground_y()
		# 预置在场景里的（放在 Items 下）没被抛出：已在地面就直接待拾取，
		# 悬空摆放的则走 SETTLE 自由落体。
		if not _launched and global_position.y >= _ground_y - 0.5:
			_set_phase(Phase.IDLE)

	_age += delta
	if _age >= life_time:
		queue_free()
		return
	if _age >= life_time - blink_time:
		visible = int(_age * 12.0) % 2 == 0

	match _phase:
		Phase.SETTLE:
			_integrate(delta)
		Phase.IDLE:
			_check_idle_magnet()
		Phase.MAGNET:
			_magnet(delta)


func _integrate(delta: float) -> void:
	_vel.y += fall_gravity * delta
	global_position += _vel * delta
	if global_position.y < _ground_y:
		return
	global_position.y = _ground_y
	if bounce > 0.0 and absf(_vel.y) > 120.0:
		_vel = Vector2(_vel.x * 0.4, -absf(_vel.y) * bounce)
		return
	_vel = Vector2.ZERO
	_set_phase(Phase.IDLE)


## IDLE 期间主动查一次当前重叠的玩家。
## 不能只依赖 body_entered：怪物死在脚边时，掉落物下落（SETTLE）阶段就已和玩家重叠，
## 而进入事件在 SETTLE 阶段被忽略；等落地转 IDLE 后玩家始终在范围内，边界事件不会再触发，
## 于是掉落物一直卡在 IDLE，只有玩家走出范围再回来才能拾取。
func _check_idle_magnet() -> void:
	if _age < pick_delay:
		return
	for b in get_overlapping_bodies():
		if b is Node2D and b.is_in_group("player"):
			_player = b
			_set_phase(Phase.MAGNET)
			return


func _magnet(delta: float) -> void:
	var p := _get_player()
	if p == null:
		_set_phase(Phase.IDLE)
		return
	if _age < pick_delay:
		return
	var to_p := p.global_position - global_position
	var d := to_p.length()
	if d <= pick_radius:
		_collect(p)
		return
	global_position += to_p.normalized() * minf(magnet_speed * delta, d)


## 向下打一条射线求地面高度：mask 只查 Objects 层，避免被敌人/投射物干扰。
## 打不到（悬空 / 掉出地图）时退化为出生高度，配合 life_time 自动消失。
func _probe_ground_y() -> float:
	var space := get_world_2d().direct_space_state
	if space == null:
		return global_position.y
	var q := PhysicsRayQueryParameters2D.create(
			global_position, global_position + Vector2(0.0, 800.0))
	q.collision_mask = Globals.LAYER_OBJECTS
	q.exclude = [get_rid()]
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return global_position.y
	return float(hit.get("position", global_position).y)


func _on_body_entered(body: Node2D) -> void:
	if not body.is_in_group("player"):
		return
	_player = body
	if _phase != Phase.SETTLE:
		_set_phase(Phase.MAGNET)


func _on_body_exited(body: Node2D) -> void:
	if body == _player and _phase == Phase.MAGNET:
		_set_phase(Phase.IDLE)


## 阶段切换的唯一入口：必须走这里，子类（CoinPickup 等）才能收到
## "起飞 / 落地"通知去切动画 —— 直接写 _phase = 的赋值无法被观测。
func _set_phase(p: Phase) -> void:
	if _phase == p:
		return
	_phase = p
	_on_phase_changed(p)


## 子类重写：阶段变化时同步表现层（动画 / 音效等）。基类不做任何处理。
## 与 _apply_effect() 一样是给子类的虚钩子，默认空实现。
func _on_phase_changed(_p: Phase) -> void:
	pass


func _get_player() -> Node2D:
	if _player != null and is_instance_valid(_player):
		return _player
	var players := get_tree().get_nodes_in_group("player")
	_player = players[0] as Node2D if not players.is_empty() else null
	return _player


func _collect(by: Node2D) -> void:
	Inventory.add(item_id, amount)
	_apply_effect(by)
	_detach_audio()
	queue_free()


## 音效要在拾取物释放后仍能播完：先把播放器挪出即将被销毁的子树，挂到场景根上延迟释放。
## 注意 _audio 挂在 Audio 容器下（$Audio/Pickup），它的父节点并不是本节点 ——
## 直接对自己调 remove_child(_audio) 会触发 "p_child->data.parent != this" 报错。
## reparent() 内部用的是节点真实的父节点，等价于"从真父节点摘除 + add_child"。
func _detach_audio() -> void:
	if _audio == null or _audio.stream == null:
		return
	var holder := get_tree().current_scene
	if holder == null:
		return
	# keep_global_transform 传 false：音效位置下一行会显式重设，省一次变换换算。
	_audio.reparent(holder, false)
	_audio.global_position = global_position
	_audio.finished.connect(_audio.queue_free)
	_audio.play()


## 子类重写：钱币无需额外效果，食物在此回血。
func _apply_effect(_by: Node2D) -> void:
	pass
