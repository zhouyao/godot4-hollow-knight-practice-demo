extends CanvasLayer

## 全局黑场（autoload）+ 场景加载服务。
##
## 职责拆分：
##   · fade_out() / fade_in()：纯黑场，供 GameSession 做关卡切换；
##   · change_scene()：菜单 ↔ 游戏这类"换根场景"的操作，只负责淡出 + 切场景，
##     不负责淡入 —— 目标场景准备就绪后自己调用 fade_in()，
##     这样"加载多久"由场景自己掌握，不会出现在半加载状态就被揭开黑场。
##
## 本节点 process_mode = ALWAYS（见 transition_layer.tscn），暂停时淡入淡出照常播。

signal faded_out
signal faded_in

## 菜单切换用的较长淡入淡出
const SCENE_FADE := 0.45

var _busy := false

## 线程化加载完成的场景缓存（路径 -> PackedScene）。
## 首次点“开始游戏”时若用 change_scene_to_file 同步读盘，整个主线程会卡在黑场里
## （冷启动要读几十 MB 纹理/音频再逐个解析）。这里提供 prefetch()，在玩家停留
## 菜单时就把目标场景预加载进内存，点击后直接 change_scene_to_packed。
var _ready_scenes: Dictionary = {}
## 正在后台加载的路径
var _pending: Dictionary = {}
var _pumping := false

var _fade_tween: Tween = null

@onready var _rect: ColorRect = $ColorRect


func is_black() -> bool:
	return _rect != null and _rect.modulate.a >= 0.999


# ---------------------------------------------------------------- 淡入淡出

## 淡到全黑。已经是全黑时立即返回（从菜单切进关卡时不会先闪一下）。
func fade_out(duration := -1.0) -> void:
	if is_black():
		faded_out.emit()
		return
	_kill_fade()
	_fade_tween = create_tween()
	_fade_tween.tween_property(_rect, "modulate:a", 1.0, duration if duration >= 0.0 else SCENE_FADE)
	await _fade_tween.finished
	faded_out.emit()


## 从全黑淡回画面。本来就不黑时立即返回。
func fade_in(duration := -1.0) -> void:
	if not is_black():
		faded_in.emit()
		return
	_kill_fade()
	_fade_tween = create_tween()
	_fade_tween.tween_property(_rect, "modulate:a", 0.0, duration if duration >= 0.0 else SCENE_FADE)
	await _fade_tween.finished
	faded_in.emit()


## 立刻变成全黑 / 全透明，不播动画（调试或场景初始化用）。
func set_black(instant: bool) -> void:
	_kill_fade()
	_rect.modulate.a = 1.0 if instant else 0.0


func _kill_fade() -> void:
	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()
	_fade_tween = null


# ---------------------------------------------------------------- 场景加载

## 预热场景：后台线程加载，不阻塞主线程。重复调用安全。
func prefetch(target: String) -> void:
	if target.is_empty() or _ready_scenes.has(target) or _pending.has(target):
		return
	# 之前加载过的场景已被 ResourceCache 记住，取个引用即可，不必再走线程。
	if ResourceLoader.has_cached(target):
		_ready_scenes[target] = ResourceLoader.load(target, "PackedScene")
		return
	if ResourceLoader.load_threaded_request(target, "PackedScene", true) != OK:
		return
	_pending[target] = true
	if not _pumping:
		_pumping = true
		_pump()


## 每帧取一次后台加载结果，加载完成的场景转入 _ready_scenes 长期持有。
## 放在 await process_frame 上，所以暂停（黑场）期间也照常推进。
func _pump() -> void:
	while not _pending.is_empty():
		for path in _pending.keys():
			var status := ResourceLoader.load_threaded_get_status(path)
			if status == ResourceLoader.THREAD_LOAD_LOADED:
				_ready_scenes[path] = ResourceLoader.load_threaded_get(path)
				_pending.erase(path)
			elif status == ResourceLoader.THREAD_LOAD_FAILED \
					or status == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
				_pending.erase(path)
		await get_tree().process_frame
	_pumping = false


## 换根场景（菜单 ↔ 游戏）。淡出 → 切场景 → 放手。
## 目标场景必须在自己准备完成后调用 fade_in()，否则黑场不会揭开。
func change_scene(target: String) -> void:
	# 守卫：双击按钮 / 连按 Esc 会并发启动第二个协程，必须忽略重复触发
	if _busy:
		return
	_busy = true

	get_tree().paused = true

	# 先发起加载再去播黑场：加载与淡出动画并行，最坏情况也不会在动画播完后
	# 才开始等磁盘 IO。预热命中时这里只是从字典取引用，几乎没有耗时。
	prefetch(target)
	while not _ready_scenes.has(target) and _pending.has(target):
		await get_tree().process_frame
	var packed: PackedScene = _ready_scenes.get(target)

	await fade_out(SCENE_FADE)

	# 延迟切换场景；当前场景在下一帧才真正被替换
	if packed != null:
		get_tree().change_scene_to_packed.bind(packed).call_deferred()
	else:
		# 预热没跑成（例如直接调用而未先 prefetch 且线程请求失败）时退回同步加载
		get_tree().change_scene_to_file.bind(target).call_deferred()

	# 等场景真正切换；不在这里解除暂停 —— 由新场景在准备就绪后自己处理
	await get_tree().scene_changed
	_busy = false
