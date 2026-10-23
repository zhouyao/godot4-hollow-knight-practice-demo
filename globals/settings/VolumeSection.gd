class_name VolumeSection
extends SettingsSection


## 音量实时变化时发出（拖动滑条过程中，每次 set_volume 都会发）。
## 参数 bus_name：总线名（Master / Sound / Music）；value：线性音量 0.0 ~ 1.0。
signal volume_update(bus_name: String, value: float)
## 音量调整结束并落盘后发出（停止拖动 COMMIT_DEBOUNCE 秒后，或手动 commit 时）。
## 参数 bus_name：已保存的总线名。需要做"改完才写文件"的逻辑请连这个信号。
signal volume_committed(bus_name: String)

const MASTER_BUS_NAME := "Master"
const SOUND_BUS_NAME := "Sound"
const MUSIC_BUS_NAME := "Music"
const VOLUME_BUS_NAMES: Array[String] = [MASTER_BUS_NAME, SOUND_BUS_NAME, MUSIC_BUS_NAME]
const DEFAULT_VOLUME := 0.5
const VOLUME_STEP := 0.05
const COMMIT_DEBOUNCE := 0.4

var _bus_indexes: Dictionary = {}
var _commit_timers: Dictionary = {}


func load() -> void:
	_cache_bus_indexes()
	_apply_all_volumes()


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



func _apply_all_volumes() -> void:
	for bus_name in VOLUME_BUS_NAMES:
		_apply_volume(bus_name, get_volume(bus_name))


func _apply_volume(bus_name: String, value: float) -> void:
	var index := _bus_index(bus_name)
	if index < 0:
		return
	AudioServer.set_bus_volume_db(index, linear_to_db(value))


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


func get_volume(bus_name: String) -> float:
	var stored: Variant = _store.get_value(SettingsStore.AUDIO_SETTING_NAME, bus_name, DEFAULT_VOLUME)
	if stored is bool:
		return DEFAULT_VOLUME
	var value := float(stored)
	if is_nan(value):
		return DEFAULT_VOLUME
	return clampf(value, 0.0, 1.0)


func set_volume(bus_name: String, value: float) -> void:
	var volume := clampf(value, 0.0, 1.0)
	_store.set_value(SettingsStore.AUDIO_SETTING_NAME, bus_name, volume)
	_apply_volume(bus_name, volume)
	volume_update.emit(bus_name, volume)
	_queue_commit(bus_name)


func commit_volume(bus_name: String) -> void:
	_cancel_commit(bus_name)
	save()
	volume_committed.emit(bus_name)


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


func _cancel_commit(bus_name: String) -> void:
	_commit_timers.erase(bus_name)


func _on_commit_timeout(bus_name: String, timer: SceneTreeTimer) -> void:
	if _commit_timers.get(bus_name) != timer:
		return
	_commit_timers.erase(bus_name)
	commit_volume(bus_name)
