extends Node2D
class_name ViewCuller

## 全局视野剔除：屏幕外的节点静默，省掉 AI / 物理 / 动画 / 音频开销。
##
## **唯一入口是分组**：只有把场景根节点加入 `view_cull` 组，它才会被剔除。
## 没有默认覆盖、没有隐式列表 —— 想让谁参与，就在谁身上加一行 groups。
##
## 接入方式（在**关卡里的实例**上声明 `groups=["view_cull"]`）：
##   · 敌人：level_1 的 5 只怪、level_2 的 2 只怪；
##   · 草：level_1 的 4 株草；
##   · `enemy.tscn` 与 `grass.tscn` 都**刻意不加**，否则所有实例被强制参与、无法逐个关闭。
## 本项目统一按实例声明，所以"这只参与、那只不参与"完全由放置处决定。
##
## 保护规则不看分组，只看节点自身状态；装饰节点上这些探测天然为假，会自动跳过：
##   · `combat_active == true` → 永不静默（否则玩家跑出屏幕就能脱战）；
##   · `is Boss` 或 `persistent_id` 非空 → 永不静默（BOSS / 一次性精英要全程跑阶段与雾门）。
##
## 判据：只有"逻辑可以被安全冻结"的节点才应该加入。
## 反例是 Pickup —— 它的存活时间在 `_physics_process` 里累加（见 pickup.gd），
## 一旦冻结就永不消失，掉在屏幕外的金币会一直堆在内存里。
## 另一个反例是门 / 长椅 / BOSS 触发器 / AuZone：它们必须在玩家离开时也能响应。

const CULL_GROUP := &"view_cull"

@export_group("开关")
## 总开关：关掉后立即恢复所有被静默的目标（排查"怪不动"的第一步）。
@export var enabled := true:
	set(value):
		enabled = value
		if not value:
			_restore_all()
		else:
			_refresh(true)

@export_group("频率")
## 距离检测间隔（秒）。越小越跟手，越大越省。
@export var check_interval := 0.15

@export_group("空间阈值")
## 视野矩形外扩多少像素时唤醒。
## 下限 ≈ 冲刺位移（1680 px/s × 0.15s = 252）+ 相机平滑滞后（≈280）≈ 550。
@export var activate_margin := 600.0
## 迟滞：休眠距离 = activate_margin + hysteresis，防止边界反复开关。
@export var hysteresis := 200.0

@export_group("保护规则")
## 战斗中的敌人不静默（否则玩家跑出屏幕就能脱战）。
@export var protect_in_combat := true

@export_group("静默动作")
## 静默时同时暂停节点下的 AudioStreamPlayer2D。
## 声音由 AudioServer 驱动，不保证会随 process_mode 一起停。
@export var cull_audio := true

@export_group("调试")
## 画出视野框 / 内外圈 / 每个目标的状态点。
@export var debug_draw := false:
	set(value):
		debug_draw = value
		queue_redraw()

var _area: Node = null
var _targets: Array[Node] = []
## Node -> bool：每个目标当前是否活跃。初始视为 true，第一次判定会关掉远处的。
var _active: Dictionary = {}
var _timer := 0.0

var _deactivate_margin: float:
	get:
		return activate_margin + hysteresis


func _ready() -> void:
	GameSession.area_changed.connect(_on_area_changed)
	# 兜底：若本节点的 _ready 晚于第一次 area_changed，这里补一次
	if GameSession.current_area != null:
		_area = GameSession.current_area
		_rebuild()
		_refresh(true)


func _process(delta: float) -> void:
	if not enabled:
		return
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = maxf(check_interval, 0.02)
	_refresh(false)


## 立即重扫目标：运行时动态生成的敌人（召唤物等）需要手动调用一次。
func refresh_targets() -> void:
	_area = GameSession.current_area
	_rebuild()
	_refresh(true)


func _on_area_changed(_area_path: String, _entry_id: StringName) -> void:
	_area = GameSession.current_area
	_rebuild()
	_refresh(true)


# ---------------------------------------------------------------- 目标收集

func _rebuild() -> void:
	# 先恢复即将失去跟踪的节点：否则"运行时被移出分组"的节点会永远停在静默状态。
	# 换关时旧 Area 的节点已释放，is_instance_valid 会跳过。
	_restore_all()
	_targets.clear()
	if not is_instance_valid(_area):
		return
	for n in get_tree().get_nodes_in_group(CULL_GROUP):
		_try_add(n)
	if debug_draw:
		queue_redraw()


## 只收当前区域的后代：换关瞬间旧 Area 可能还没释放干净。
func _try_add(n: Node) -> void:
	if not is_instance_valid(n) or not (n is Node2D):
		return
	if not _area.is_ancestor_of(n):
		return
	if _targets.has(n):
		return
	_targets.append(n)


# ---------------------------------------------------------------- 判定

func _refresh(force: bool) -> void:
	if not enabled:
		return
	var rect := _view_rect()
	if rect.size == Vector2.ZERO:
		return
	var inner := rect.grow(activate_margin)
	var outer := rect.grow(_deactivate_margin)

	for n in _targets:
		if not is_instance_valid(n):
			continue
		var currently := bool(_active.get(n, true))
		var want := _wants_active(n, inner, outer, currently)
		if force or want != currently:
			_apply(n, want)

	if debug_draw:
		queue_redraw()


func _wants_active(n: Node, inner: Rect2, outer: Rect2, currently: bool) -> bool:
	# 保护规则基于节点自身状态而非分组：装饰节点没有这些属性，探测结果天然为假。
	# 用 == true 而不是 bool()：get() 在属性不存在时返回 null，而 bool(null) 会报错。
	if protect_in_combat and n.get(&"combat_active") == true:
		return true
	if _is_special(n):
		return true

	var pos: Vector2 = (n as Node2D).global_position
	# 迟滞：已经在屏幕上 → 出了外圈才关；已经关了 → 进入内圈才开
	return outer.has_point(pos) if currently else inner.has_point(pos)


## BOSS 与一次性精英永不静默：它们要全程跑阶段、血条、BGM 与雾门逻辑。
func _is_special(n: Node) -> bool:
	if n is Boss:
		return true
	var pid: Variant = n.get(&"persistent_id")
	return pid != null and not String(pid).is_empty()


func _view_rect() -> Rect2:
	var cam := get_viewport().get_camera_2d()
	if cam == null:
		# 菜单 / 单关调试尚未挂相机：返回空矩形表示"本轮不判定"
		return Rect2()
	# 用 get_screen_center_position()：它已经过 Camera2D 的 limit 钳制，
	# 与玩家实际看到的画面一致（camera.global_position 在锁区边界会差出几百像素）。
	var center := cam.get_screen_center_position()
	var size := get_viewport().get_visible_rect().size / cam.zoom
	return Rect2(center - size * 0.5, size)


# ---------------------------------------------------------------- 执行

func _apply(n: Node, active: bool) -> void:
	_active[n] = active

	if n is CanvasItem:
		(n as CanvasItem).visible = active
	n.process_mode = Node.PROCESS_MODE_INHERIT if active else Node.PROCESS_MODE_DISABLED

	# 碰撞体必须 deferred：开关可能发生在物理回调期间，直接改会被引擎拒绝
	for shape in n.find_children("*", "CollisionShape2D", true, false):
		(shape as CollisionShape2D).set_deferred("disabled", not active)

	if cull_audio:
		for p in n.find_children("*", "AudioStreamPlayer2D", true, false):
			(p as AudioStreamPlayer2D).stream_paused = not active


func _restore_all() -> void:
	for n in _targets:
		if is_instance_valid(n):
			_apply(n, true)
	# 恢复后清空状态表：下次启用时按"已在场"重新判定
	_active.clear()
	queue_redraw()


# ---------------------------------------------------------------- 调试绘制

func _draw() -> void:
	if not debug_draw:
		return
	var rect := _view_rect()
	if rect.size == Vector2.ZERO:
		return

	draw_rect(rect, Color(1.0, 1.0, 1.0, 0.22), false, 2.0)
	draw_rect(rect.grow(activate_margin), Color(0.35, 1.0, 0.45, 0.22), false, 2.0)
	draw_rect(rect.grow(_deactivate_margin), Color(1.0, 0.78, 0.25, 0.18), false, 1.0)

	for n in _targets:
		if not is_instance_valid(n):
			continue
		var p: Vector2 = (n as Node2D).global_position
		var active := bool(_active.get(n, true))
		draw_circle(p, 16.0, Color(0.35, 1.0, 0.45, 0.55) if active else Color(1.0, 0.3, 0.3, 0.55))
