extends Node

## 存档管理（autoload）：固定 4 个槽位，JSON 落盘到 user://saves/slot_N.json。
##
## 职责：
##   · 读写 / 删除存档文件；
##   · 给存档页提供预览信息（区域、游玩时长、生命、能量、钱币）；
##   · 运行时从当前关卡采集玩家 / 背包 / 能力状态；
##   · 读档后把数据回填到新加载的关卡（WorldTemplate 在 _ready 里调用 apply_pending_state）。
##
## 写盘点：暂停菜单“退回主菜单”、退出游戏、关闭窗口；另外新建存档时立刻写一个初始档。

## 存档写入完成（存档页 / 调试可用）。
signal slot_saved(slot: int)
## 存档被删除。
signal slot_deleted(slot: int)

const SLOT_COUNT := 4
const SAVE_DIR := "user://saves"
const SAVE_VERSION := 1
const DEFAULT_SCENE_PATH := "res://scenes/worlds/levels/level_1.tscn"

## 当前选中的槽位（1 起）；-1 表示还没有进入任何存档。
var current_slot: int = -1

var _data: Dictionary = {}
## 本次游玩计时起点（微秒）。存档时把这一段累加进 play_time。
var _play_started_usec: int = 0
## 已 load_game 但还没回填到关卡。
var _pending_load := false


func _ready() -> void:
	_ensure_save_dir()
	# 关闭窗口时先存档再退出；保存逻辑在 _notification 里统一处理。
	get_tree().auto_accept_quit = false


func _notification(what: int) -> void:
	if what != NOTIFICATION_WM_CLOSE_REQUEST:
		return
	save_game()
	Settings.flush()
	get_tree().quit()


# ---------------------------------------------------------------- 查询

func slot_path(slot: int) -> String:
	return "%s/slot_%d.json" % [SAVE_DIR, slot]


func has_slot(slot: int) -> bool:
	return _valid_slot(slot) and FileAccess.file_exists(slot_path(slot))


## 存档页预览数据。文件不存在或损坏时 exists = false。
func get_summary(slot: int) -> Dictionary:
	var empty := {
		"exists": false,
		"zone": "",
		"play_time": 0.0,
		"health": 0,
		"max_health": 0,
		"energy": 0,
		"max_energy": 0,
		"coin": 0,
		"food": 0,
		"scene_path": DEFAULT_SCENE_PATH,
		"saved_at": "",
	}
	if not has_slot(slot):
		return empty

	var data := _read_slot(slot)
	if data.is_empty():
		return empty

	var player: Dictionary = data.get("player", {}) if data.get("player") is Dictionary else {}
	var inventory: Dictionary = data.get("inventory", {}) if data.get("inventory") is Dictionary else {}

	return {
		"exists": true,
		"zone": String(data.get("zone", "")),
		"play_time": float(data.get("play_time", 0.0)),
		"health": int(player.get("health", 0)),
		"max_health": int(player.get("max_health", 0)),
		"energy": int(player.get("energy", 0)),
		"max_energy": int(player.get("max_energy", 0)),
		"coin": int(inventory.get("coin", 0)),
		"food": int(inventory.get("food", 0)),
		"scene_path": String(data.get("scene_path", DEFAULT_SCENE_PATH)),
		"saved_at": String(data.get("saved_at", "")),
	}


## 读档 / 新建后要进入的关卡。
func current_scene_path() -> String:
	var path := String(_data.get("scene_path", ""))
	if path.is_empty() or not ResourceLoader.exists(path):
		return DEFAULT_SCENE_PATH
	return path


func current_data() -> Dictionary:
	return _data.duplicate(true)


## 是否已永久击败（只对 persistent_id 非空的 BOSS / 精英生效）。
func is_defeated(id: String) -> bool:
	if id.is_empty():
		return false
	var defeated: Variant = _data.get("defeated", [])
	return defeated is Array and id in defeated


## 标记永久击败并立刻落盘：BOSS 属于关键进度，不等下一次手动存档。
## 普通杂兵不要调用（persistent_id 留空，重新进关照常刷新）。
func mark_defeated(id: String) -> void:
	if id.is_empty() or current_slot < 0:
		return
	var defeated: Array = []
	var stored: Variant = _data.get("defeated", [])
	if stored is Array:
		defeated = stored
	if id in defeated:
		return
	defeated.append(id)
	_data["defeated"] = defeated
	# 此时玩家在关卡里，save_game() 会顺带记录当前状态与场景。
	save_game()


# ---------------------------------------------------------------- 生/读/存/删

## 新建存档：重置背包与运行时数据，立刻写一个初始档。
func new_game(slot: int) -> bool:
	if not _valid_slot(slot):
		return false

	current_slot = slot
	_pending_load = false
	_data = {
		"version": SAVE_VERSION,
		"slot": slot,
		"scene_path": DEFAULT_SCENE_PATH,
		"zone": "",
		"play_time": 0.0,
		"saved_at": "",
		"player": {},
		"inventory": {},
		"monarch_wings": Globals.has_monarch_wings,
		"defeated": [],
	}

	Inventory.reset()
	_play_started_usec = Time.get_ticks_usec()
	return save_game(true)


## 读取存档到内存；真正回填要等关卡加载完成（apply_pending_state）。
func load_game(slot: int) -> bool:
	if not has_slot(slot):
		return false

	var data := _read_slot(slot)
	if data.is_empty():
		return false

	_data = data
	current_slot = slot
	_pending_load = true
	_play_started_usec = Time.get_ticks_usec()
	# 兼容旧档：没有 defeated 字段时补一个空表，后续 mark_defeated 直接追加。
	if not (_data.get("defeated") is Array):
		_data["defeated"] = []
	return true


## 采集当前关卡状态并写盘。
## force = true 时即使当前不在关卡里也写（新建存档时用）。
func save_game(force := false) -> bool:
	if current_slot < 0:
		return false

	var world := get_tree().current_scene
	var player := _find_player(world)
	if player == null and not force:
		# 主菜单 / 转场中：没有可采集的世界状态，别用空数据覆盖已有存档。
		return false

	# 只有在关卡里（找得到 Player）才覆盖场景 / 区域，避免在主菜单新建存档时
	# 把 scene_path 写成 main.tscn。
	if player != null and world != null:
		var scene_path := String(world.scene_file_path)
		if not scene_path.is_empty():
			_data["scene_path"] = scene_path
		var zone := String(world.get("zone_name")) if "zone_name" in world else ""
		if not zone.is_empty():
			_data["zone"] = zone

	if player != null and player.has_method("to_save_dict"):
		_data["player"] = player.to_save_dict()
		_data["monarch_wings"] = Globals.has_monarch_wings

	_data["inventory"] = Inventory.to_dict()
	_data["play_time"] = _accumulated_play_time()
	_data["saved_at"] = Time.get_datetime_string_from_system(false, true)
	_data["version"] = SAVE_VERSION

	if not _write_slot():
		return false
	slot_saved.emit(current_slot)
	return true


func delete_slot(slot: int) -> void:
	if not _valid_slot(slot):
		return
	var path := slot_path(slot)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	if current_slot == slot:
		current_slot = -1
		_data.clear()
		_play_started_usec = 0
		_pending_load = false
	slot_deleted.emit(slot)


## 关卡加载完成后由 WorldTemplate 调用：把读档数据回填到玩家 / 背包 / 能力。
func apply_pending_state(world: Node) -> void:
	if not _pending_load:
		return
	_pending_load = false

	var player := _find_player(world)
	if player != null and player.has_method("apply_save_dict"):
		var player_data: Dictionary = _data.get("player", {}) if _data.get("player") is Dictionary else {}
		player.apply_save_dict(player_data)

	var inventory: Dictionary = _data.get("inventory", {}) if _data.get("inventory") is Dictionary else {}
	Inventory.load_from_dict(inventory)
	Globals.has_monarch_wings = bool(_data.get("monarch_wings", Globals.has_monarch_wings))


# ---------------------------------------------------------------- 内部

func format_play_time(seconds: float) -> String:
	var total := maxi(int(seconds), 0)
	@warning_ignore("integer_division")
	var hours := total / 3600
	@warning_ignore("integer_division")
	var minutes := (total % 3600) / 60
	if hours > 0:
		return "%dH %dM" % [hours, minutes]
	return "%dM" % minutes


func _valid_slot(slot: int) -> bool:
	return slot >= 1 and slot <= SLOT_COUNT


func _ensure_save_dir() -> void:
	if not DirAccess.dir_exists_absolute(SAVE_DIR):
		DirAccess.make_dir_recursive_absolute(SAVE_DIR)


func _accumulated_play_time() -> float:
	var total := float(_data.get("play_time", 0.0))
	if _play_started_usec > 0:
		total += float(Time.get_ticks_usec() - _play_started_usec) / 1_000_000.0
		_play_started_usec = Time.get_ticks_usec()
	return total


func _find_player(world: Node) -> Node:
	if world == null:
		return null
	var node := world.get_node_or_null("Player")
	if node != null:
		return node
	return world.find_child("Player", true, false)


func _read_slot(slot: int) -> Dictionary:
	var path := slot_path(slot)
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_warning("存档读取失败（%d）：%s" % [FileAccess.get_open_error(), path])
		return {}
	var text := file.get_as_text()
	file.close()

	var parsed: Variant = JSON.parse_string(text)
	if parsed is Dictionary:
		return parsed
	push_warning("存档 JSON 解析失败：%s" % path)
	return {}


func _write_slot() -> bool:
	_ensure_save_dir()
	var path := slot_path(current_slot)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_warning("存档写入失败（%d）：%s" % [FileAccess.get_open_error(), path])
		return false
	file.store_string(JSON.stringify(_data, "\t"))
	file.close()
	return true
