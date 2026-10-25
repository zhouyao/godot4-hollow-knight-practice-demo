class_name DisplaySection
extends SettingsSection


## 窗口模式变化并落盘后发出。参数 mode：MODE_WINDOWED / MODE_FULLSCREEN。
## UI 连它刷新下拉框选中项。
signal window_mode_changed(mode: int)

## 对外只暴露这两档 id
const MODE_WINDOWED := 0
const MODE_FULLSCREEN := 1
const MODE_IDS: Array[int] = [MODE_WINDOWED, MODE_FULLSCREEN]
const DEFAULT_MODE := MODE_WINDOWED
## 开机后延迟多久才开始改窗口，避开 macOS 的窗口初始化窗口期
const STARTUP_DELAY := 1.0
## 窗口模式下锁定为 16:9，避免被拖成超宽/超高导致大黑边或露出场景外内容。
const ASPECT := 16.0 / 9.0


## 进入全屏前的窗口尺寸，切回窗口时用它还原。
## 不使用 DisplayServer.WINDOW_MODE_FULLSCREEN：macOS 上那是原生全屏（独立 Space），
## 4.7.2 + gl_compatibility 实测一旦进入，之后的任何 window_set_mode 调用都会让进程冻结，
## 永远退不回来。这里改用无边框窗口铺满屏幕，功能等价且可随时切回，也没有切 Space 的动画。
var _windowed_size: Vector2i

## 程序化切换窗口/全屏进行中：期间抑制 16:9 夹取，避免和切换逻辑互相打架。
var _applying := false
## 夹取自身的重入守卫：window_set_size 会再次触发 size_changed，用它挡掉那一圈。
var _clamping := false


func _init(store: SettingsStore, request_save: Callable) -> void:
	super._init(store, request_save)
	_windowed_size = DisplayServer.window_get_size()
	# 连接窗口 resize 事件以在窗口模式下锁定 16:9；root 可能尚未就绪，分帧重试。
	_try_connect_resize()


## 返回 tr() 用的源文本，同时是 translations.csv 的 key
static func display_name(id: int) -> String:
	return "全屏" if id == MODE_FULLSCREEN else "窗口"


## 窗口当前所在屏幕的矩形（多显示器下不能写死第 0 块屏，否则会用错屏幕的尺寸和原点）。
## position 是跨屏的全局坐标，可直接喂给 window_set_position()。
static func current_screen_rect() -> Rect2i:
	var index := DisplayServer.window_get_current_screen()
	return Rect2i(DisplayServer.screen_get_position(index), DisplayServer.screen_get_size(index))


## 当前实际模式：先看是否处于原生全屏，否则按窗口尺寸是否铺满屏幕来判。
## 不能用 borderless 标记判断——为了绕开 macOS 的冻结问题，窗口模式也可能处于无边框状态。
static func current_system_mode() -> int:
	match DisplayServer.window_get_mode():
		DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN, DisplayServer.WINDOW_MODE_FULLSCREEN:
			return MODE_FULLSCREEN
	var size := DisplayServer.window_get_size()
	var screen := current_screen_rect().size
	return MODE_FULLSCREEN if size.x >= screen.x and size.y >= screen.y else MODE_WINDOWED


func load() -> void:
	var stored_size: Variant = _store.get_value(
		SettingsStore.DISPLAY_SETTING_NAME, SettingsStore.WINDOW_SIZE_KEY, Vector2i.ZERO
	)
	if stored_size is Vector2i:
		var size := stored_size as Vector2i
		if size.x > 0 and size.y > 0:
			_windowed_size = size

	# 启动阶段不能立刻改窗口：macOS 上窗口还没就绪，实测会在窗口调整时直接把进程打死
	#（下一帧都不行）。等场景树稳定后再套用上次的模式。
	var target := get_window_mode()
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		_apply(target)
		return
	tree.create_timer(STARTUP_DELAY).timeout.connect(func() -> void: _apply_startup(target))


func _apply_startup(id: int) -> void:
	if id == current_system_mode():
		return
	_apply(id)


func reset() -> void:
	set_window_mode(DEFAULT_MODE)


## 用存档里的当前值强制套用一次窗口状态，供场景切换后兜底：
## 万一启动阶段的延迟 apply 因时序没跑成，进游戏时仍能对齐。
## 已对齐时直接跳过，避免重复 set_position 触发 macOS 的间歇性退出。
func apply_now() -> void:
	if get_window_mode() == current_system_mode():
		return
	_apply(get_window_mode())


func get_window_mode() -> int:
	var stored: Variant = _store.get_value(
		SettingsStore.DISPLAY_SETTING_NAME, SettingsStore.WINDOW_MODE_KEY, DEFAULT_MODE
	)
	if stored is bool:
		return DEFAULT_MODE
	var id := int(stored)
	return id if MODE_IDS.has(id) else DEFAULT_MODE


func set_window_mode(id: int) -> void:
	if !MODE_IDS.has(id):
		push_error("不支持的窗口模式：%d" % id)
		return
	if id == get_window_mode():
		return
	_store.set_value(SettingsStore.DISPLAY_SETTING_NAME, SettingsStore.WINDOW_MODE_KEY, id)
	_apply(id)
	save()
	window_mode_changed.emit(id)


## 打开设置界面时调一次，把菜单之外的变化（macOS 绿按钮 / Win F11）同步回存档
func sync_from_system() -> void:
	# 只认菜单之外的原生全屏（macOS 绿按钮 / Win F11），其余情况一律不动配置。
	# 不能按尺寸判断：macOS 上我们自己触发的 resize 有约 1 秒延迟，
	# 这期间按尺寸会误判成"窗口"，把用户刚选的全屏回滚掉。
	match DisplayServer.window_get_mode():
		DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN, DisplayServer.WINDOW_MODE_FULLSCREEN:
			if get_window_mode() == MODE_FULLSCREEN:
				return
			_store.set_value(SettingsStore.DISPLAY_SETTING_NAME, SettingsStore.WINDOW_MODE_KEY, MODE_FULLSCREEN)
			save()
			window_mode_changed.emit(MODE_FULLSCREEN)
		_:
			return


## macOS 上在同一个渲染帧里连续改窗口几何有概率冻死进程，
## 所以每一步之间都让出一帧，避开窗口系统的处理窗口期。
func _apply(id: int) -> void:
	_applying = true
	await _apply_stepped(id)
	_applying = false


func _apply_stepped(id: int) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null:
		await tree.process_frame
	if id == MODE_FULLSCREEN:
		await _apply_fullscreen()
		return
	await _apply_windowed()


func _apply_fullscreen() -> void:
	var screen := current_screen_rect()
	_windowed_size = _clamp_to_aspect(DisplayServer.window_get_size())
	if _windowed_size.x <= 0 or _windowed_size.y <= 0:
		_windowed_size = screen.size
	_store.set_value(SettingsStore.DISPLAY_SETTING_NAME, SettingsStore.WINDOW_SIZE_KEY, _windowed_size)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
	# 全屏用 expand：铺满整块屏幕，非 16:9 显示器也不留黑边（对应空洞骑士全屏填满）。
	_set_stretch_aspect(Window.CONTENT_SCALE_ASPECT_EXPAND)
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null:
		await tree.process_frame
	# 先把窗口挪到目标屏幕，再在原地放大尺寸：避免先改尺寸时窗口还停在旧位置、
	# 整屏尺寸却已套用，导致那一帧窗口被甩出屏幕左右外缘，出现左右颜色不一致的残影。
	DisplayServer.window_set_position(screen.position)
	if tree != null:
		await tree.process_frame
	DisplayServer.window_set_size(screen.size)


func _apply_windowed() -> void:
	var screen := current_screen_rect()
	# 退回窗口模式必须先关掉无边框标记，否则标题栏、拖动和缩放手柄都不会恢复。
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
	# 窗口模式用 keep：配合 16:9 锁定，窗口始终铺满、无黑边、不露场景外内容。
	_set_stretch_aspect(Window.CONTENT_SCALE_ASPECT_KEEP)
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null:
		await tree.process_frame
	DisplayServer.window_set_size(_windowed_size)
	if tree != null:
		await tree.process_frame
	var offset: Vector2 = Vector2(screen.size - _windowed_size) * 0.5
	DisplayServer.window_set_position(screen.position + Vector2i(offset.round()))


## 把任意尺寸夹成 16:9，保留较大的那一边，避免拖拽时窗口忽大忽小。
static func _clamp_to_aspect(size: Vector2i) -> Vector2i:
	var w := float(size.x)
	var h := float(size.y)
	if w <= 0.0 or h <= 0.0:
		return size
	if w / h > ASPECT:
		return Vector2i(size.x, int(round(w / ASPECT)))
	return Vector2i(int(round(h * ASPECT)), size.y)


## root 就绪前可能为 null，分帧重试连接 size_changed。
func _try_connect_resize() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		if tree != null:
			tree.process_frame.connect(_try_connect_resize, CONNECT_ONE_SHOT)
		return
	if not tree.root.size_changed.is_connected(_on_size_changed):
		tree.root.size_changed.connect(_on_size_changed)


## 运行时切换拉伸宽高比：窗口模式用 keep（锁定的 16:9 窗口正好铺满），
## 全屏用 expand（铺满整块屏幕，非 16:9 屏多显示一点世界、不留黑边，对应空洞骑士全屏填满）。
func _set_stretch_aspect(mode: int) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return
	var win := tree.root as Window
	if win != null:
		win.content_scale_aspect = mode


## 用户拖拽改变窗口尺寸时，把窗口夹回 16:9。全屏或程序化切换期间跳过。
func _on_size_changed() -> void:
	if _applying or _clamping:
		return
	if current_system_mode() == MODE_FULLSCREEN:
		return
	var size := DisplayServer.window_get_size()
	var target := _clamp_to_aspect(size)
	if target == size:
		return
	_clamping = true
	# 用 call_deferred 把几何修改挪出 size_changed 信号上下文，规避 macOS 同帧改窗口冻结。
	DisplayServer.window_set_size.call_deferred(target)
	# 等本次 resize 事件平息后再解 guard，避免与后续 size_changed 串台。
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null:
		tree.process_frame.connect(func() -> void: _clamping = false, CONNECT_ONE_SHOT)
