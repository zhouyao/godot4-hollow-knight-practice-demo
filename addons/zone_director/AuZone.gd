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

@export_group("编辑器预览 Editor Preview")
## 在 2D 编辑器里把区域四个角画成实心直角三角形（运行时不画）。
@export var show_corners_in_editor: bool = true:
	set(value):
		show_corners_in_editor = value
		queue_redraw()
## 矩形内部填充的不透明度：`0` = **完全透明**（默认），只留描边与四角三角形，
## 便于看清底下的关卡内容；调大则显示按通道自动着色的淡色块。
## 同时作用于两处：脚本画的矩形填充，以及内部 `CollisionShape2D` 的
## `debug_color` 的 alpha（Godot 编辑器绘制的形状背景，与 `_debug_color()` 无关）。
## 矩形描边颜色始终由 `_debug_color()` 决定，不受此项影响。
@export_range(0.0, 1.0, 0.01) var fill_alpha: float = 0.0:
	set(value):
		fill_alpha = clampf(value, 0.0, 1.0)
		_sync_debug_color()
		queue_redraw()
## 四角三角形的颜色，与通道自动色（`_debug_color()`）相互独立，可逐区单独配。
@export var corner_color: Color = Color(0.0, 0.0, 0.0):
	set(value):
		corner_color = value
		queue_redraw()
## 三角形的直角边长（世界单位）。编辑器缩得很小时会自动放大，
## 保证至少有 6 个屏幕像素。最小值为 1。
@export var corner_size: float = 80.0:
	set(value):
		corner_size = maxf(value, 1.0)
		queue_redraw()


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
		set_process(false)
	else:
		# 编辑器下定时重绘：_ready 的那一次会被 2D 视口初始化冲掉，
		# 之后若属性没变化就再也看不到四角三角形。
		_sync_debug_color()
		set_process(true)
		queue_redraw()


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
		# alpha 默认 0：编辑器里新建的形状也不铺背景色，由 fill_alpha 统一控制。
		collision.debug_color = Color(0.35, 0.85, 0.55, 0.0)
		collision.shape = RectangleShape2D.new()
		add_child(collision)
		# 让编辑器把新建的形状随场景一起保存（owner 为空时不会落盘）。
		collision.owner = owner
	elif collision.shape == null or not (collision.shape is RectangleShape2D):
		collision.shape = RectangleShape2D.new()
	_own_shape(collision)


## 兜底：每个实例必须独占自己的 RectangleShape2D（正常由 .tscn 里的
## resource_local_to_scene 保证）。子资源默认在同场景的多个实例间共享，一旦共享，
## 改某个 Zone 的 size 会把所有 Zone 的碰撞盒一起改掉 —— 编辑器里表现为
## "调整一个 EnemyZone，其它 EnemyZone 的大小也跟着变"。
func _own_shape(collision: CollisionShape2D) -> void:
	var shape := collision.shape as RectangleShape2D
	if shape == null or shape.resource_local_to_scene:
		return
	if Engine.is_editor_hint():
		# 编辑器里换新的 resource 会往关卡场景里写一条 shape override，交给
		# resource_local_to_scene 兜住，这里不介入。
		return
	collision.shape = shape.duplicate()


## Godot 编辑器用 `CollisionShape2D.debug_color` 画碰撞形状的背景。
## 把它的 alpha 与 `fill_alpha` 对齐：默认 0 = 内部形状背景全透明，
## 只剩脚本画的矩形描边与四角三角形。
## 仅在编辑器里改（运行时不碰节点属性）；值相同时不写，避免反复把场景标脏。
func _sync_debug_color() -> void:
	if not Engine.is_editor_hint():
		return
	var collision := get_node_or_null("CollisionShape2D") as CollisionShape2D
	if collision == null:
		return
	var dc := collision.debug_color
	if is_equal_approx(dc.a, fill_alpha):
		return
	dc.a = fill_alpha
	collision.debug_color = dc


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
	# 默认全透明：中间不铺色块，避免盖住底下的关卡内容。
	# 只有把 fill_alpha 调大时才画淡填充，描边始终保留。
	if fill_alpha > 0.0:
		draw_rect(r, Color(col.r, col.g, col.b, fill_alpha))
	draw_rect(r, col, false, 2.0)
	# 互斥通道画实心圆心、叠加通道画空心圆心，便于一眼分辨本区域说的是哪类话。
	for i in EXCLUSIVE_MARKERS.size():
		if declares(EXCLUSIVE_MARKERS[i]):
			draw_circle(r.position + Vector2(14.0 + 14.0 * float(i), 14.0), 5.0, col)
	for i in ADDITIVE_MARKERS.size():
		if declares(ADDITIVE_MARKERS[i]):
			draw_arc(r.position + Vector2(14.0 + 14.0 * float(i), 30.0),
					5.0, 0.0, TAU, 12, col, 2.0, true)

	_draw_corner_triangles(r)


const REDRAW_INTERVAL := 0.5

var _redraw_accum := 0.0


func _notification(what: int) -> void:
	if Engine.is_editor_hint() and (what == NOTIFICATION_ENTER_TREE or what == NOTIFICATION_VISIBILITY_CHANGED):
		queue_redraw()


func _process(delta: float) -> void:
	if not Engine.is_editor_hint():
		set_process(false)
		return
	_redraw_accum += delta
	if _redraw_accum >= REDRAW_INTERVAL:
		_redraw_accum = 0.0
		queue_redraw()


## 四角实心直角三角形：直角顶点落在角上，两条直角边沿矩形边朝内，斜边指向中心。
## 用 draw_colored_polygon 而不是描边，保证编辑器缩到很小时仍然看得见。
func _draw_corner_triangles(r: Rect2) -> void:
	if not show_corners_in_editor or r.size.x <= 0.0 or r.size.y <= 0.0:
		return

	var canvas_scale := 1.0
	var vp := get_viewport()
	if vp != null:
		canvas_scale = maxf(vp.get_global_canvas_transform().get_scale().x, 0.001)
	var s := maxf(corner_size, 6.0 / canvas_scale)

	var corners := [
		r.position,
		Vector2(r.end.x, r.position.y),
		r.end,
		Vector2(r.position.x, r.end.y),
	]
	# 每个角"朝内"的两个方向，与 corners 顺序一一对应
	var dirs := [
		Vector2(1.0, 1.0), Vector2(-1.0, 1.0),
		Vector2(-1.0, -1.0), Vector2(1.0, -1.0),
	]

	for i in 4:
		var p: Vector2 = corners[i]
		var d: Vector2 = dirs[i]
		var a := p
		var b := p + Vector2(d.x * s, 0.0)
		var c := p + Vector2(0.0, d.y * s)
		# 统一绕序，避免不同角的三角形因顶点方向相反而漏画
		if (b - a).cross(c - a) < 0.0:
			var tmp := b
			b = c
			c = tmp
		draw_colored_polygon(PackedVector2Array([a, b, c]), corner_color)


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
