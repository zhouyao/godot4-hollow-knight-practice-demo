extends Node

## 关卡准备期开始 / 结束时发出，供状态机、UI 等订阅（避免每帧轮询）
signal level_preparing_changed(is_preparing: bool)

const MAIN_MENU_SCENE_PATH := "res://main.tscn"
const SYSTEM_SETTINGS_SCENE_PATH := "res://scenes/menus/system_settings_menu.tscn"
const GAME_SCENE_PATH := "res://scenes/world/world_test.tscn"

var _level_preparing := true
var level_preparing: bool:
	set(value):
		if _level_preparing == value:
			return
		_level_preparing = value
		level_preparing_changed.emit(value)
	get:
		return _level_preparing

var UNIT_SIZE: float = 96.0

func go_to_main_menu() -> void:
	TransitionLayer.change_scene(MAIN_MENU_SCENE_PATH)

func go_to_game() -> void:
	TransitionLayer.change_scene(GAME_SCENE_PATH)

func go_to_system_settings() -> void:
	TransitionLayer.change_scene(SYSTEM_SETTINGS_SCENE_PATH)

func quit_game() -> void:
	# Settings 的写盘有 debounce，直接 quit 会把最后一次音量 / 按键改动丢掉
	Settings.flush()
	get_tree().quit()
