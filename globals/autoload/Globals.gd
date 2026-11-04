extends Node


## 关卡准备状态变化时发出：true = 转场 / 加载中（通常用来屏蔽输入），false = 可以正常操作。
signal level_preparing_changed(is_preparing: bool)

const MAIN_MENU_SCENE_PATH := "res://main.tscn"
const SYSTEM_SETTINGS_SCENE_PATH := "res://scenes/menus/settings_menu/system_settings_menu.tscn"
const GAME_SCENE_PATH := "res://scenes/worlds/levels/level_1.tscn"


const LAYER_PLAYER := 1 << 0
const LAYER_ENEMIES := 1 << 1
const LAYER_OBJECTS := 1 << 2
const LAYER_PROJECTILES := 1 << 3
const LAYER_AREAS_AND_ZONES := 1 << 4
const LAYER_DETECTION_AND_ATTACK := 1 << 5
const LAYER_NO_PLAYER_COLLISION := 1 << 6
const LAYER_DROPS := 1 << 7
const LAYER_BACKGROUND_DESTROY := 1 << 8

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

## 帝王之翼（二段跳）解锁标记：放在 autoload 上，换场景后仍然保留。
## 默认 true 便于直接体验；接入拾取物 / 存档流程时改为 false，拾到后调 unlock_monarch_wings()。
var has_monarch_wings: bool = true

func unlock_monarch_wings() -> void:
	has_monarch_wings = true


## 供调试 / 存档回滚使用：关闭后空中按跳不再振翅。
func lock_monarch_wings() -> void:
	has_monarch_wings = false


## 调试信息显示开关变化时发出（角色血条、状态名、回巢倒计时等据此显隐）。
signal debug_enabled_changed(enabled: bool)

var _debug_enabled := true
var debug_enabled: bool:
	set(value):
		if _debug_enabled == value:
			return
		_debug_enabled = value
		debug_enabled_changed.emit(value)
	get:
		return _debug_enabled

func go_to_main_menu() -> void:
	TransitionLayer.change_scene(MAIN_MENU_SCENE_PATH)

func go_to_game() -> void:
	TransitionLayer.change_scene(GAME_SCENE_PATH)

func go_to_system_settings() -> void:
	TransitionLayer.change_scene(SYSTEM_SETTINGS_SCENE_PATH)

func quit_game() -> void:
	Settings.flush()
	get_tree().quit()
