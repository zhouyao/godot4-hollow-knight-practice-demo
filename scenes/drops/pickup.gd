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

## 落地射线的容差（像素）：起点上抬、终点下探各留一点，
## 避免金币贴地时射线从碰撞体内部起手反而打不到地面。
const GROUND_PROBE_SKIN := 4.0

var _phase := Phase.SETTLE
var _vel := Vector2.ZERO
var _age := 0.0
var _player: Node2D = null
## 是否已由 DropSpawner 抛出：场景里预置的 Pickup（放在 Items 下）不走 launch()。
var _launched := false
## 首帧贴地判定：射线查询必须在物理帧内，统一推迟到第一个物理帧。
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
		# 预置在场景里的（放在 Items 下）没被抛出：已在地面就直接待拾取，
		# 悬空摆放的则走 SETTLE 自由落体。
		if not _launched and is_finite(_probe_ground(GROUND_PROBE_SKIN, global_position)):
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


## 重力积分 + 逐帧落地检测：金币是横向抛出的，出生点正下方的平台未必是它真正
## 会落到的地方，所以每帧按"当前 x + 本帧位移"向下打一条短射线，飞出平台边缘就继续下落。
## 打不到地面也不再钳到出生高度（那会让空中击杀的掉落物凭空悬停），
## 而是继续自由落体，掉出地图后由 life_time 兜底清理。
func _integrate(delta: float) -> void:
	_vel.y += fall_gravity * delta
	var step := _vel * delta
	var pos := global_position + step
	if step.y > 0.0:
		var ground_y := _probe_ground(step.y, Vector2(pos.x, global_position.y))
		if is_finite(ground_y):
			pos.y = ground_y
			global_position = pos
			if bounce > 0.0 and absf(_vel.y) > 120.0:
				_vel = Vector2(_vel.x * 0.4, -absf(_vel.y) * bounce)
				return
			_vel = Vector2.ZERO
			_set_phase(Phase.IDLE)
			return
	global_position = pos


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
		# 目标消失时恢复重力：磁吸可能已经把金币带到半空，回 IDLE 会让它悬停。
		_set_phase(Phase.SETTLE)
		return
	if _age < pick_delay:
		return
	var to_p := p.global_position - global_position
	var d := to_p.length()
	if d <= pick_radius:
		_collect(p)
		return
	global_position += to_p.normalized() * minf(magnet_speed * delta, d)


## 从 at 向下打一条「本帧位移」长度的射线找地面：返回命中点 y，没命中返回 INF。
## mask 只查 Objects 层，避免被敌人 / 投射物干扰；起点上抬 GROUND_PROBE_SKIN，
## 让贴地的金币也能从地面上方起手命中，而不是从碰撞体内部起手被忽略。
func _probe_ground(length: float, at: Vector2) -> float:
	var space := get_world_2d().direct_space_state
	if space == null:
		return INF
	var from := at - Vector2(0.0, GROUND_PROBE_SKIN)
	var q := PhysicsRayQueryParameters2D.create(
			from, from + Vector2(0.0, length + GROUND_PROBE_SKIN))
	q.collision_mask = Globals.LAYER_OBJECTS
	q.exclude = [get_rid()]
	var hit := space.intersect_ray(q)
	if not hit.has("position"):
		return INF
	return float(hit["position"].y)


func _on_body_entered(body: Node2D) -> void:
	if not body.is_in_group("player"):
		return
	_player = body
	if _phase != Phase.SETTLE:
		_set_phase(Phase.MAGNET)


func _on_body_exited(body: Node2D) -> void:
	if body == _player and _phase == Phase.MAGNET:
		# 没被吃掉的金币继续下落，而不是停在玩家离开时的那个空中高度。
		_set_phase(Phase.SETTLE)


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
	var holder := GameSession.content_root()
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
