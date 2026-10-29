@tool
extends Area2D
class_name AuZone


## 可嵌套的 2D 区域。
##
## 职责边界：只管"谁在里面"和"我在哪些通道上说了什么"，不含任何业务逻辑。
## 业务以 AuZoneBehavior 挂件的形式挂在 AuZone 下面，由本节点在进出 / 得失通道时回调。
##
## 嵌套：本节点在场景树中的 AuZone 祖先链层数即 depth，越深 = 越内层 = 越具体。
## 也可以用 parent_zone 跨树显式指定。同深度时按 zone_priority，再按面积小者优先。
##
## 信号名沿用旧 EnemyZone 的 player_entered / player_exited，
## 消费方用 has_signal("player_entered") 判定的旧代码可零改动接入。


## 目标进入本区域时发出。参数 zone 为本节点，player 为进入的 body。
signal player_entered(zone: Node, player: Node2D)
## 目标离开本区域时发出。
signal player_exited(zone: Node, player: Node2D)


@export_group("通道 Channels")
## 地面材质（互斥通道）：grass / water / stone / snow ... 留空 = 不参与仲裁。
@export var surface: StringName = &""
## 环境氛围（叠加通道）：rain / fog / snow / indoor ... 可同时存在多个。
@export var ambient: StringName = &""
## 光照（互斥通道）：dark / torch / bright ... 留空 = 不参与仲裁。
@export var lighting: StringName = &""
## 任意标签（叠加通道）：combat / no_dash ... 供 AuZoneDirector.has_tag() 查询。
@export var tags: Array[StringName] = []
## 仲裁优先级：同深度时数值大者胜，用来强翻"谁更具体"。
## 注意不能叫 priority —— Godot 4.4 起 Area2D 自带 priority 属性，重名会冲突。
@export var zone_priority: int = 0

@export_group("形状 Shape")
## 区域尺寸（像素）。
@export var size: Vector2 = Vector2(256, 128):
	set(value):
		size = value
		_apply_size()
## 碰撞矩形是否以节点原点为中心。false 时矩形从原点向右下展开。
@export var centered: bool = true:
	set(value):
		centered = value
		_apply_size()

@export_group("嵌套 Nesting")
## 可选的显式父区域：跨场景树指定包含关系。留空则按 AuZone 祖先链自动判定。
@export var parent_zone: NodePath = NodePath("")

@export_group("检测 Detection")
## 检测哪些物理层的 body。默认第 1 层 = 玩家层（与 rain / fog 的 PlayerZone 一致）。
## 之所以写死数字而不引用 Globals.LAYER_PLAYER：插件不得依赖游戏工程的 autoload。
@export_flags_2d_physics var detect_mask: int = 1:
	set(value):
		detect_mask = value
		collision_mask = value
## 只响应属于该 Godot 组的 body。留空则不过滤。
@export var target_group: StringName = &"player"


## 仲裁中心的 autoload 节点名。
## 刻意用字符串路径解析而不是直接写全局标识符：插件被复制到新工程、
## autoload 尚未注册时也不会编译失败，只会静默降级（见 _director()）。
const DIRECTOR_NODE := "AuZoneDirector"

var _depth := -1
var _body_count := 0
var _last_body: Node2D = null
## 已登记的 AuZoneBehavior（由挂件 _ready 自行登记 / 由 _collect_behaviors() 扫描补齐）。
var _behavior_nodes: Array = []


func _ready() -> void:
	collision_layer = 0        # 不占物理层：不被攻击区 / 其它 Area 误检
	monitorable = false        # 只检测别人，不被别人检测
	collision_mask = detect_mask
	_ensure_shape()
	_apply_size()
	_collect_behaviors()
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)
		body_exited.connect(_on_body_exited)
	if not Engine.is_editor_hint():
		# 开局就在区域内时 body_entered 的时序不可靠，延迟一帧对齐初值。
		_sync_initial_overlap.call_deferred()


func _exit_tree() -> void:
	var d = _director()
	if d != null:
		d.unregister(self)


## 最近一次进入本区域的 body。
func last_body() -> Node2D:
	if _last_body != null and not is_instance_valid(_last_body):
		_last_body = null
	return _last_body


## 嵌套层数：AuZone 祖先链的长度。0 = 顶层区域。
var depth: int:
	get:
		if _depth < 0:
			_depth = _compute_depth()
		return _depth


## 本 AuZone 是否在某通道上"说了话"（参与了仲裁 / 集合）。
func declares(channel: StringName) -> bool:
	match channel:
		&"surface": return surface != &""
		&"lighting": return lighting != &""
		&"ambient": return ambient != &""
		&"tag": return not tags.is_empty()
	return false


## 本 AuZone 是否是某互斥通道当前的胜者。
func is_effective(channel: StringName = &"surface") -> bool:
	var d = _director()
	if d == null:
		return false
	return d.top_of(channel) == self


## 全局矩形（含父级 scale）—— 同深度仲裁时用它比面积。
func global_rect() -> Rect2:
	var s := get_global_transform().get_scale()
	var sz := Vector2(absf(size.x * s.x), absf(size.y * s.y))
	return Rect2(global_position - sz * 0.5, sz) if centered else Rect2(global_position, sz)


## 取仲裁中心 autoload。返回 untyped（Variant），因此在未注册 autoload 的工程里
## 也不会因静态检查失败——只是所有区域退化为"不生效"。编辑器里一律返回 null。
func _director():
	if Engine.is_editor_hint():
		return null
	var t := get_tree()
	if t == null:
		return null
	return t.root.get_node_or_null(DIRECTOR_NODE)


# ---- 事件转发给挂件 ----

func _on_body_entered(body: Node) -> void:
	if not _matches(body):
		return
	_body_count += 1
	_last_body = body as Node2D
	player_entered.emit(self, body)
	var d = _director()
	if d != null:
		d.notify_entered(self, body as Node2D)
	for b in _behavior_nodes:
		b.on_entered(body)
	queue_redraw()


func _on_body_exited(body: Node) -> void:
	if not _matches(body):
		return
	_body_count = maxi(_body_count - 1, 0)
	if _body_count > 0:
		return              # 多个目标时，最后一个离开才算数
	player_exited.emit(self, body)
	var d = _director()
	if d != null:
		d.notify_exited(self)
	for b in _behavior_nodes:
		b.on_exited(body)
	queue_redraw()


## 由 AuZoneDirector 在仲裁结果变化时回调（区别于"进出区域"）。
func _notify_channel_gained(channel: StringName) -> void:
	for b in _behavior_nodes:
		b.on_gained(channel)
	queue_redraw()


func _notify_channel_lost(channel: StringName) -> void:
	for b in _behavior_nodes:
		b.on_lost(channel)
	queue_redraw()


# ---- 内部 ----

func _matches(body: Node) -> bool:
	if body == null:
		return false
	if target_group != &"" and not body.is_in_group(String(target_group)):
		return false
	return true


func _compute_depth() -> int:
	if not parent_zone.is_empty():
		var p := get_node_or_null(parent_zone) as AuZone
		if p != null and p != self:
			return p.depth + 1
	var d := 0
	var n := get_parent()
	while n != null:
		if n is AuZone:
			d += 1
		n = n.get_parent()
	return d


func _sync_initial_overlap() -> void:
	if not is_inside_tree():
		return
	for body in get_overlapping_bodies():
		if _matches(body):
			_on_body_entered(body)
			break


## 扫描子节点收集挂件。
## 用 has_method 鸭子类型判定而不是 `is AuZoneBehavior`：本类因此不必引用 AuZoneBehavior，
## 与"AuZoneBehavior 引用 AuZone"形成单向依赖，避免两个 class_name 循环解析失败；
## 顺带也兜住了"子类重写 _ready 却忘了 super()"导致漏登记的情况。
func _collect_behaviors() -> void:
	_behavior_nodes.clear()
	for i in get_child_count():
		var c = get_child(i)
		if c != null and c.has_method("on_entered"):
			_behavior_nodes.append(c)


## 供运行时后加的挂件自行登记（见 AuZoneBehavior._ready）。
func register_behavior(b) -> void:
	if b != null and not _behavior_nodes.has(b):
		_behavior_nodes.append(b)


func _ensure_shape() -> void:
	var collision := get_node_or_null("CollisionShape2D") as CollisionShape2D
	if collision == null:
		collision = CollisionShape2D.new()
		collision.name = "CollisionShape2D"
		collision.debug_color = Color(0.35, 0.85, 0.55, 0.3)
		collision.shape = RectangleShape2D.new()
		add_child(collision)
		# 让编辑器把新建的形状随场景一起保存（owner 为空时不会落盘）。
		collision.owner = owner
	elif collision.shape == null or not (collision.shape is RectangleShape2D):
		collision.shape = RectangleShape2D.new()


func _apply_size() -> void:
	var collision := get_node_or_null("CollisionShape2D") as CollisionShape2D
	if collision == null or not (collision.shape is RectangleShape2D):
		return
	collision.shape.size = size
	collision.position = Vector2.ZERO if centered else size / 2.0
	queue_redraw()


func _draw() -> void:
	if not Engine.is_editor_hint():
		return
	var r := Rect2(-size / 2.0, size) if centered else Rect2(Vector2.ZERO, size)
	var col := _debug_color()
	draw_rect(r, Color(col.r, col.g, col.b, 0.09))
	draw_rect(r, col, false, 2.0)
	# 互斥通道画实心圆心、叠加通道画空心圆心，便于一眼分辨本区域说的是哪类话。
	for i in EXCLUSIVE_MARKERS.size():
		if declares(EXCLUSIVE_MARKERS[i]):
			draw_circle(r.position + Vector2(14.0 + 14.0 * float(i), 14.0), 5.0, col)
	for i in ADDITIVE_MARKERS.size():
		if declares(ADDITIVE_MARKERS[i]):
			draw_arc(r.position + Vector2(14.0 + 14.0 * float(i), 30.0),
					5.0, 0.0, TAU, 12, col, 2.0, true)


const EXCLUSIVE_MARKERS: Array[StringName] = [&"surface", &"lighting"]
const ADDITIVE_MARKERS: Array[StringName] = [&"ambient", &"tag"]


func _debug_color() -> Color:
	if surface != &"":
		return Color(0.40, 0.90, 0.45, 0.9)
	if lighting != &"":
		return Color(0.95, 0.80, 0.30, 0.9)
	if ambient != &"":
		return Color(0.45, 0.80, 1.00, 0.9)
	if not tags.is_empty():
		return Color(0.75, 0.50, 0.95, 0.9)
	return Color(0.65, 0.65, 0.65, 0.9)
