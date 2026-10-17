extends Node

# 注意：Godot 禁止 class_name 与 autoload 名同名（会报 “hides an autoload singleton”），
# 因此这里不声明 class_name，全局以 autoload 名 Settings 访问。
#
# 职责：作为设置总调度，持有共享的 SettingsStore 与唯一的去抖写盘计时器，
# 把所有设置项抽象成 SettingsSection（音量 / 按键 / 语言…）统一编排。
# 各 section 只管自己的运行时逻辑与存档读写，需要落盘时调用注入的 _request_save，
# 由这里把多次写请求合并成一次 ConfigFile 落盘。新增设置项（画质、字幕…）
# 只需加一个 SettingsSection 子类并在 _ready 里注册，不必再往本单例里堆代码。

# 连续调节会把多次写入合并成一次，避免每按一格就全量写盘
const SAVE_DEBOUNCE := 0.3

# 配置读写全部委托给 SettingsStore；section / 路径等存储细节集中在其内
var _store := SettingsStore.new()

# 由本单例组合、协调写盘的各个设置项
var volume: VolumeSection
var bindings: InputBindings
var localization: Localization

# 注册的所有 section，统一用于加载与退出前的 flush
var _sections: Array[SettingsSection] = []

var _save_timer: SceneTreeTimer = null


func _ready() -> void:
	# 各 section 共享同一份 store，并通过注入的 Callable 请求去抖落盘
	var request_save := Callable(self, "request_save")
	volume = VolumeSection.new(_store, request_save)
	bindings = InputBindings.new(_store, request_save)
	localization = Localization.new(_store, request_save)
	_sections = [volume, bindings, localization]

	if _store.load_config() != OK:
		# 存档损坏 / 首次运行：音量兜底写默认值，按键与语言各自 load 会回落默认
		volume.reset()

	for section in _sections:
		section.load()

	bindings.ensure_default_bindings()
	bindings.load()
	bindings.purge_reserved_bindings()

	# 存档语言优先，没存过时跟随系统语言
	TranslationServer.set_locale(localization.get_locale())

	# 窗口关闭按钮 / 系统快捷键退出前保住最后一次改动。这里连 root 的 close_requested
	# 而不是 NOTIFICATION_WM_CLOSE_REQUEST：后者是否广播到 autoload 节点取决于引擎实现，
	# 而 quit() 触发的退出根本走不到它，那条路径由 Globals.quit_game() 负责
	get_tree().root.close_requested.connect(flush)


# 各 section 通过注入的 Callable 请求落盘：SAVE_DEBOUNCE 窗口内的多次请求合并成一次写
func request_save() -> void:
	if get_tree() == null:
		_flush_settings()
		return
	if _save_timer != null:
		_save_timer.time_left = SAVE_DEBOUNCE
		return
	_save_timer = get_tree().create_timer(SAVE_DEBOUNCE)
	_save_timer.timeout.connect(_flush_settings)


# 退出前把还在 debounce 窗口里的改动立刻写盘，不再等 debounce / 提交计时器到点
func flush() -> void:
	for section in _sections:
		section.flush()
	_flush_settings()


func _flush_settings() -> void:
	_save_timer = null
	var error := _store.save_config()
	if error != OK:
		push_warning("设置写入失败（%d）：%s" % [error, SettingsStore.SETTINGS_PATH])
