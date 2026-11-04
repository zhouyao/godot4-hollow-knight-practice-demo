extends CanvasLayer

# 淡出期间冻结当前场景：否则退出关卡时，空中的角色会在黑场那 1 秒里继续下落、
# 甚至触发落地音。TransitionLayer 自身 process_mode = ALWAYS，暂停时过场照常播放。
var _busy := false

## 线程化加载完成的场景缓存（路径 -> PackedScene）。
## 首次点“开始游戏”时若用 change_scene_to_file 同步读盘，整个主线程会卡在黑场里
## （冷启动要读几十 MB 纹理/音频再逐个解析）。这里提供 prefetch()，在玩家停留
## 菜单时就把目标场景预加载进内存，点击后直接 change_scene_to_packed。
var _ready_scenes: Dictionary = {}
## 正在后台加载的路径
var _pending: Dictionary = {}
var _pumping := false


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

	$AnimationPlayer.play("fade_to_black")
	await $AnimationPlayer.animation_finished

	# 延迟切换场景；当前场景在下一帧才真正被替换
	if packed != null:
		get_tree().change_scene_to_packed.bind(packed).call_deferred()
	else:
		# 预热没跑成（例如直接调用而未先 prefetch 且线程请求失败）时退回同步加载
		get_tree().change_scene_to_file.bind(target).call_deferred()

	# 等待场景真正切换后再解除暂停，避免黑场期间暂停状态被提前还原
	await get_tree().scene_changed
	get_tree().paused = false

	# 场景已切换完成，立刻解除忙碌锁：否则锁会一直持续到淡出动画结束，
	# 导致返回主菜单后首次点击“设置”在黑场淡出期间被守卫丢弃、需再点一次。
	_busy = false

	$AnimationPlayer.play_backwards("fade_to_black")
	await $AnimationPlayer.animation_finished
