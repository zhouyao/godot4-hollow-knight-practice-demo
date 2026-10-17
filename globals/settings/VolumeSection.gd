class_name VolumeSection
extends SettingsSection

# 音量设置项：负责三条音频总线（Master / Sound / Music）的运行时维护与落盘。
# 继承自 SettingsSection，写盘去抖由 Settings 统一调度；本类只保留“一次调节结束”
# 所需的静止提交（commit）计时器，因为鼠标拖动有 drag_ended 通知，方向键 / 手柄没有。

signal volume_update(bus_name: String, value: float)
# 一次音量调节结束（滑条松手 / 重置 / 静止超时）时才发出，用于落盘与播放预览音
signal volume_committed(bus_name: String)

const MASTER_BUS_NAME := "Master"
const SOUND_BUS_NAME := "Sound"
const MUSIC_BUS_NAME := "Music"
const VOLUME_BUS_NAMES: Array[String] = [MASTER_BUS_NAME, SOUND_BUS_NAME, MUSIC_BUS_NAME]
const DEFAULT_VOLUME := 0.5
# 键盘/手柄步进与滑条 step 的唯一真相，滑条在 _ready 里据此设置 step
const VOLUME_STEP := 0.05
# 键盘/手柄调节音量没有 drag_ended 可以通知，改动静止这么久就认为一次调节结束
const COMMIT_DEBOUNCE := 0.4

var _bus_indexes: Dictionary = {}
# bus_name -> 待提交的 SceneTreeTimer，用来判定一次连续调节是否已经停下
var _commit_timers: Dictionary = {}


# 加载即把存档里的音量套到音频总线上（缺字段时回落默认值）
func load() -> void:
	_cache_bus_indexes()
	_apply_all_volumes()


# 重置全部总线到默认值并落盘，用于存档损坏 / 首次运行的兜底
func reset() -> void:
	for bus_name in VOLUME_BUS_NAMES:
		_store.set_value(SettingsStore.AUDIO_SETTING_NAME, bus_name, DEFAULT_VOLUME)
	save()
	_apply_all_volumes()


func flush() -> void:
	_commit_timers.clear()


func commit() -> void:
	for bus_name in VOLUME_BUS_NAMES:
		commit_volume(bus_name)


#region 音量

func _apply_all_volumes() -> void:
	for bus_name in VOLUME_BUS_NAMES:
		_apply_volume(bus_name, get_volume(bus_name))


func _apply_volume(bus_name: String, value: float) -> void:
	var index := _bus_index(bus_name)
	if index < 0:
		return
	AudioServer.set_bus_volume_db(index, linear_to_db(value))


# 总线缺失时给出明确报错，而不是往 -1 索引上写数据后静默失效
func _cache_bus_indexes() -> void:
	for bus_name in VOLUME_BUS_NAMES:
		var index := AudioServer.get_bus_index(bus_name)
		if index < 0:
			push_error("音频总线缺失：%s" % bus_name)
			continue
		_bus_indexes[bus_name] = index


func _bus_index(bus_name: String) -> int:
	var cached: Variant = _bus_indexes.get(bus_name)
	if cached != null:
		return cached as int
	var index := AudioServer.get_bus_index(bus_name)
	_bus_indexes[bus_name] = index
	return index


# 存档缺字段时回落到默认值；外部改坏的存档在这里就被夹到合法范围，不会传到 linear_to_db
func get_volume(bus_name: String) -> float:
	var stored: Variant = _store.get_value(SettingsStore.AUDIO_SETTING_NAME, bus_name, DEFAULT_VOLUME)
	if stored is bool:
		return DEFAULT_VOLUME
	var value := float(stored)
	if is_nan(value):
		return DEFAULT_VOLUME
	return clampf(value, 0.0, 1.0)


# 任何来源的音量改动都走这里：鼠标拖动、方向键、手柄、代码。
# 只改内存与音频总线，落盘与预览音交给一次“提交”，连续调节不会被拆成多次。
func set_volume(bus_name: String, value: float) -> void:
	var volume := clampf(value, 0.0, 1.0)
	_store.set_value(SettingsStore.AUDIO_SETTING_NAME, bus_name, volume)
	_apply_volume(bus_name, volume)
	volume_update.emit(bus_name, volume)
	# 拖动有 drag_ended 可以通知提交，方向键 / 手柄没有，这里兜底排一个静止提交
	_queue_commit(bus_name)


# 一次调节结束（滑条松手 / 重置 / 静止超时）时调用：落盘并通知 UI 播放预览音
func commit_volume(bus_name: String) -> void:
	_cancel_commit(bus_name)
	save()
	volume_committed.emit(bus_name)


# VolumeSection 是 RefCounted，没有 get_tree()，统一用 Engine.get_main_loop() 取主循环
func _queue_commit(bus_name: String) -> void:
	var timer: SceneTreeTimer = _commit_timers.get(bus_name)
	if timer != null:
		timer.time_left = COMMIT_DEBOUNCE
		return
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		save()
		return
	timer = tree.create_timer(COMMIT_DEBOUNCE)
	_commit_timers[bus_name] = timer
	timer.timeout.connect(_on_commit_timeout.bind(bus_name, timer))


# SceneTreeTimer 没有 stop()，取消只能把登记表里的位置腾空
func _cancel_commit(bus_name: String) -> void:
	_commit_timers.erase(bus_name)


# 比对 timer 身份而不是只看有没有登记：一次提交之后又开了新一轮调节时，
# 上一轮的 timer 到点不能顺手把新一轮也提前提交掉
func _on_commit_timeout(bus_name: String, timer: SceneTreeTimer) -> void:
	if _commit_timers.get(bus_name) != timer:
		return
	_commit_timers.erase(bus_name)
	commit_volume(bus_name)

#endregion
