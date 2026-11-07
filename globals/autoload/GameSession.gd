extends Node

## 跨关卡会话（autoload）：唯一负责"换 Area"的地方。
##
## 设计约定：
##   · Player / HUD / 相机 / 过场 UI 常驻在 game_root.tscn，永不随关卡重建；
##   · level_*.tscn 只是纯内容（WorldTemplate 底座），由本节点异步加载并挂到 WorldHost；
##   · 换关时先把 Player 从旧 Area 里摘出来保存引用，再销毁旧 Area、挂新 Area 并放回去，
##     这样 Player 在场景树里的绘制顺序与原先"关卡内 Player"完全一致（前景仍盖住玩家）。
##   · 一次性事件（宝箱、拾取物、BOSS）统一记在 SaveManager 的 flags 里，跨关 / 跨存档持久。
##
## 生命周期：
##   game_root._ready() → bind_root() → bootstrap()（黑场里静默加载，不淡入）
##   关卡内 LevelGate → travel_to()（淡出 → 换 Area → 淡入）
##   回主菜单 → reset()（清掉对已释放节点的引用）

signal area_load_started(area_path: String)
signal area_changed(area_path: String, entry_id: StringName)
## 玩家在长椅休息了一次（副本给 UI 弹提示用）。
signal rested(bench_id: StringName)
## 玩家在可坐的椅子上坐下并落盘（副本给 UI 弹"存档成功"用）。
signal sat(seat_id: StringName)


const DEFAULT_ENTRY: StringName = &"default"

## 常驻对象（由 game_root.bind_root 注入）
var player: Node2D = null
var world_host: Node2D = null
var fx_host: Node2D = null

## 当前挂载的区域
## 类型是 Node 而不是 Node2D：区域不一定是世界模板，开场视频（Control 根）也走这条换关流程。
var current_area: Node = null
var current_area_path: String = ""
var current_entry_id: StringName = DEFAULT_ENTRY

var _traveling := false
## 路径 -> PackedScene：切过的关常驻内存，来回走不重复读盘
var _cache: Dictionary = {}
## 正在后台线程加载的规范化路径 -> true，避免同一关重复发起线程请求
var _pending_loads: Dictionary = {}
## 项目初始 zoom（game_root 里 AuCameraRig.zoom）；没配区域 zoom 的关卡回落到它。
var _default_zoom := Vector2.ONE


# ---------------------------------------------------------------- 装配

func bind_root(root: Node) -> void:
	player = root.get_node_or_null(^"Player")
	world_host = root.get_node_or_null(^"WorldHost")
	fx_host = root.get_node_or_null(^"FxHost")

	# zoom 变化（含 tween 逐帧）会改变 half_w / half_h，四条 limit 必须跟着重算。
	# 插件只发信号，项目侧决定是否响应。
	var rig := root.get_node_or_null(^"AuCameraRig") as AuCameraRig
	if rig != null:
		_default_zoom = rig.zoom
		if not rig.zoom_changed.is_connected(_on_camera_zoom_changed):
			rig.zoom_changed.connect(_on_camera_zoom_changed)


func _on_camera_zoom_changed(_new_zoom: Vector2) -> void:
	refresh_camera_limits()


## 公开入口：外部改了 zoom / 视口尺寸后可手动刷新相机边界。
## 换关时由 _swap_area() 自动调用；zoom 变化由 zoom_changed 信号自动触发。
func refresh_camera_limits() -> void:
	_apply_camera_bounds()


func is_traveling() -> bool:
	return _traveling


func zone_name() -> String:
	if current_area != null and "zone_name" in current_area:
		return String(current_area.get(&"zone_name"))
	return ""


## 临时物件（弹幕 / 特效 / 音效 / 掉落）应该挂的根节点：优先当前区域。
## 这样换关时它们随区域一起释放，不会残留到下一关。
func content_root() -> Node:
	if is_instance_valid(current_area):
		return current_area
	return get_tree().current_scene


# ---------------------------------------------------------------- 进出关卡

## game_root 启动时调用：此时屏幕通常已是全黑（从菜单切过来），不做淡入淡出。
## 调用方负责在结束后自行 fade_in。
func bootstrap(area_path: String, entry_id: StringName = DEFAULT_ENTRY) -> void:
	if area_path.is_empty():
		area_path = SaveManager.current_scene_path()
	area_path = _canonical_area_path(area_path)
	area_load_started.emit(area_path)

	await _swap_area(area_path)
	if current_area == null:
		push_error("[GameSession] 启动区域加载失败：%s" % area_path)
		return

	current_area_path = area_path
	current_entry_id = entry_id
	await _place_player(entry_id)
	area_changed.emit(area_path, entry_id)


## 运行时换关（门 / 电梯 / 剧情传送）。
func travel_to(area_path: String, entry_id: StringName = DEFAULT_ENTRY) -> void:
	area_path = _canonical_area_path(area_path)
	if _traveling or area_path.is_empty():
		return
	# 同一关同一入口：不重复触发（防止玩家站在门上反复弹门）
	if area_path == current_area_path and entry_id == current_entry_id:
		return

	_traveling = true
	area_load_started.emit(area_path)
	# 后台加载与淡出动画并行：冷读几十 MB 资源时不把黑场末尾再拖长。
	prefetch_area(area_path)

	await TransitionLayer.fade_out()
	await _swap_area(area_path)

	if current_area != null:
		current_area_path = area_path
		current_entry_id = entry_id
		await _place_player(entry_id)
		area_changed.emit(area_path, entry_id)

	await TransitionLayer.fade_in()
	_traveling = false


## 回主菜单时清掉对已释放节点的引用，避免 autoload 持有悬空指针。
func reset() -> void:
	if is_instance_valid(player):
		# 若停在过场里退回菜单，别把 PROCESS_MODE_DISABLED 留在被复用的玩家上。
		player.process_mode = Node.PROCESS_MODE_INHERIT
		if player.get_parent() != null:
			player.get_parent().remove_child(player)
	player = null

	if is_instance_valid(current_area):
		current_area.queue_free()
	current_area = null

	world_host = null
	fx_host = null
	current_area_path = ""
	current_entry_id = DEFAULT_ENTRY
	_traveling = false


# ---------------------------------------------------------------- 一次性事件

func has_flag(id: String) -> bool:
	if id.is_empty():
		return false
	return SaveManager.is_flagged(id)


func set_flag(id: String) -> void:
	if id.is_empty():
		return
	SaveManager.mark_flag(id)


## 由长椅调用：广播"已休息"，UI 层据此弹提示。
func notify_rested(bench_id: StringName) -> void:
	rested.emit(bench_id)


## 由可坐的椅子调用：广播"已坐下并落盘"，UI 层据此弹"存档成功"。
func notify_sat(seat_id: StringName) -> void:
	sat.emit(seat_id)


# ---------------------------------------------------------------- 内部

func _swap_area(area_path: String) -> void:
	area_path = _canonical_area_path(area_path)
	# 1) 把玩家从旧 Area 里摘出来，避免随旧 Area 一起被释放。
	if is_instance_valid(player) and player.get_parent() != null:
		player.get_parent().remove_child(player)
		# 必须在玩家离树时清：若等它加入新区域后再 clear，
		# 新区域的相机锁区可能已按"旧坐标"注册过，清掉后不会再触发 body_entered。
		AuCameraDirector.clear()

	# 2) 卸载旧 Area。必须等真正出树：否则旧关的 KillBox / Zone 会和新关重叠一帧。
	if is_instance_valid(current_area):
		current_area.queue_free()
		await current_area.tree_exited
	current_area = null

	# 3) 异步加载并实例化新 Area
	var packed := await _load_async(area_path)
	if packed == null:
		push_error("[GameSession] 无法加载区域：%s" % area_path)
		# 兜底：把玩家挂回根节点，至少不会出现"玩家被摘下来后凭空消失"
		if is_instance_valid(player) and player.get_parent() == null:
			_area_host().add_child(player)
		return

	current_area = packed.instantiate()
	_area_host().add_child(current_area)
	_apply_area_zoom()
	_apply_camera_bounds()

	# 4) 把玩家插回"关卡内 Player"原来的绘制位置：模板里是 Drops 之前。
	#    非 Node2D 区域（开场视频等全屏过场）没有地面，玩家会一直下落并把 2D 相机拖走：
	#    挂回 WorldHost、冻结它的处理，换回世界区域时再解冻。
	if is_instance_valid(player):
		var world_area := current_area is Node2D
		player.process_mode = Node.PROCESS_MODE_INHERIT if world_area else Node.PROCESS_MODE_DISABLED
		if world_area:
			var anchor := current_area.get_node_or_null(^"Drops")
			current_area.add_child(player)
			if anchor != null:
				current_area.move_child(player, anchor.get_index())
		else:
			if "velocity" in player:
				player.set(&"velocity", Vector2.ZERO)
			var host := _area_host()
			host.add_child(player)
			if host == current_area.get_parent():
				host.move_child(player, current_area.get_index())

	# 等一帧让新 Area 的 _ready（相机锁区注册、BOSS 读档判定等）跑完
	await get_tree().process_frame


## 换关时应用本区域的镜头缩放配置（`CameraBounds` 的「区域镜头 Zoom」）。
## 区域没配 / 没有 CameraBounds 时复位成 Vector2.ONE，避免上一关的放大缩小残留。
## zoom 变化（含 tween 逐帧）由 zoom_changed → refresh_camera_limits 同步四条 limit。
func _apply_area_zoom() -> void:
	var bounds: Node = null
	if current_area != null:
		bounds = current_area.get_node_or_null(^"CameraBounds")
	if bounds != null and bounds.has_method(&"apply_zoom_config"):
		bounds.call(&"apply_zoom_config", _default_zoom)
		return
	AuCameraDirector.tween_zoom(_default_zoom, 0.0)


## 套用当前区域的相机硬边界；区域没配（Rect2 为空）时恢复默认的大范围。
func _apply_camera_bounds() -> void:
	var root := get_tree().current_scene
	if root == null:
		return
	var rig := root.get_node_or_null(^"AuCameraRig") as AuCameraRig
	if rig == null:
		return

	# 相机边界来自关卡里可拖拽的 CameraBounds 矩形（相机中心活动范围），
	# 组件自己按 zoom 换算成 Camera2D 的四条 limit。
	var bounds_node: Node = null
	if current_area != null:
		bounds_node = current_area.get_node_or_null(^"CameraBounds")
	if bounds_node != null and bounds_node.has_method(&"get_camera_limits"):
		var vp: Vector2 = get_viewport().get_visible_rect().size
		var limits: Rect2 = bounds_node.call(&"get_camera_limits", rig.zoom, vp)
		if limits.size.x > 0.0 and limits.size.y > 0.0:
			rig.set_limits(
				int(limits.position.x), int(limits.position.y),
				int(limits.end.x), int(limits.end.y)
			)
			return

	rig.set_limits(-10000000, -10000000, 10000000, 10000000)


## 区域该挂到哪里：正常是 GameRoot 的 WorldHost；
## F6 单关调试时没有 WorldHost，退回当前根场景。
func _area_host() -> Node:
	if is_instance_valid(world_host):
		return world_host
	return get_tree().current_scene


func _place_player(entry_id: StringName) -> void:
	if not is_instance_valid(player) or current_area == null:
		return

	# 没有入口表（开场视频等非世界区域）：不需要摆放玩家，也不该报"缺入口"。
	if not current_area.has_method(&"get_entry"):
		return

	var marker: Node2D = current_area.call(&"get_entry", entry_id)
	if marker == null and entry_id != DEFAULT_ENTRY:
		push_warning("[GameSession] 入口不存在：%s/%s，回落到默认入口" % [current_area_path, entry_id])
		marker = current_area.call(&"get_entry", DEFAULT_ENTRY)
	if marker == null:
		push_warning("[GameSession] 区域缺少默认入口：%s" % current_area_path)
		return

	player.global_position = marker.global_position
	if "velocity" in player:
		player.set(&"velocity", Vector2.ZERO)
	# 入口可指定出生朝向；与玩家当前朝向不一致时走它自己的翻转流程（精灵 / 碰撞 / 相机锚点）
	var facing := int(marker.get(&"facing")) if marker.get(&"facing") != null else 0
	if facing != 0 and "move_direction" in player and int(player.get(&"move_direction")) != facing:
		if player.has_method(&"_flip_direction"):
			player.call(&"_flip_direction")
		player.set(&"move_direction", facing)
	# 本项目开了 2D 物理插值：瞬移后必须重置，否则第一帧会从旧位置插值飞过来
	player.reset_physics_interpolation()

	# 相机：重新绑定跟随并瞬移到位（锁定行为已在 _swap_area 里清过）
	var camera_marker := player.get_node_or_null(^"CameraPosition") as Node2D
	if camera_marker != null:
		AuCameraDirector.set_follow(camera_marker)
	await snap_camera()


## 把相机瞬移到玩家当前的位置（切关 / 读档 / 传送后调用，避免镜头从旧位置滑过来）。
## 顺序是"先硬切、再等物理帧"：切之前先等一帧的话，那一帧相机还在用旧坐标配新 limit 跑
## get_camera_transform()，既没用，又会让平滑状态再推进一次。
func snap_camera() -> void:
	if not is_instance_valid(player):
		return
	var root := get_tree().current_scene
	if root == null:
		return
	var rig := root.get_node_or_null(^"AuCameraRig") as AuCameraRig
	if rig == null:
		return
	# 对准跟随锚点而不是角色原点：CameraPosition 带 ±100 的水平偏移（还会随朝向翻转），
	# 用原点硬切，淡入后相机会再挪 100~200px。
	var camera_marker := player.get_node_or_null(^"CameraPosition") as Node2D
	# 只需这一次瞬移：插件据此开启入场窗口，锁区由 body_entered 注册时会自动硬切到最终目标。
	rig.teleport_to(camera_marker.global_position if camera_marker != null else player.global_position)
	# 等相机在新位置跑完两个物理帧（limit 钳制 / 插值历史 / 平滑恢复都落定）再允许淡入。
	await get_tree().physics_frame
	await get_tree().physics_frame


func _load_async(path: String) -> PackedScene:
	var key := _canonical_area_path(path)
	# travel_to 已提前发起后台加载；这里只等结果，避免同一份 PackedScene 被请求两次。
	prefetch_area(key)
	var tree := Engine.get_main_loop() as SceneTree
	while _pending_loads.has(key) and tree != null:
		await tree.process_frame
	if _cache.has(key):
		return _cache[key]

	# 线程加载没跑起来（路径异常 / 别的系统占用请求）时退回同步加载。
	var sync := ResourceLoader.load(key, "PackedScene") as PackedScene
	if sync != null:
		_cache[key] = sync
	return sync


## 后台预加载一块 Area；可在淡出前调用，让磁盘 IO 与黑场动画并行。
func prefetch_area(path: String) -> void:
	var key := _canonical_area_path(path)
	if key.is_empty() or _cache.has(key) or _pending_loads.has(key):
		return

	if ResourceLoader.has_cached(key):
		var cached := ResourceLoader.load(key, "PackedScene") as PackedScene
		if cached != null:
			_cache[key] = cached
		return

	if ResourceLoader.load_threaded_request(key, "PackedScene", false) != OK:
		# 别的系统已请求过 / 路径异常：退回同步加载，避免重复消费线程结果。
		var sync := ResourceLoader.load(key, "PackedScene") as PackedScene
		if sync != null:
			_cache[key] = sync
		return

	_pending_loads[key] = true
	_pump_prefetch(key)


func _pump_prefetch(key: String) -> void:
	# 用 MainLoop 的信号而不是 Node.get_tree()：预加载可能在根节点装配期间发起，
	# 此时 autoload 的 data.tree 还未就绪，get_tree() 会返回 null。
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		_pending_loads.erase(key)
		return
	while _pending_loads.has(key):
		var status := ResourceLoader.load_threaded_get_status(key)
		if status == ResourceLoader.THREAD_LOAD_LOADED:
			var packed := ResourceLoader.load_threaded_get(key) as PackedScene
			if packed != null:
				_cache[key] = packed
			_pending_loads.erase(key)
			return
		if status == ResourceLoader.THREAD_LOAD_FAILED \
				or status == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			_pending_loads.erase(key)
			return
		await tree.process_frame


## UID 与 res:// 路径统一成 res:// 作为缓存键，避免同一关被重复加载 / 重复判定。
func _canonical_area_path(path: String) -> String:
	if path.begins_with("uid://"):
		var resolved := ResourceUID.uid_to_path(path)
		if not resolved.is_empty():
			return resolved
	return path
