extends Node

signal camera_shake(strength, fade_speed)

const MAIN_MENU_SCENE_PATH := "res://main.tscn"
const SYSTEM_SETTINGS_SCENE_PATH := "res://scenes/menus/system_settings_menu.tscn"
const GAME_SCENE_PATH := "res://scenes/world/world_template.tscn"

var level_preparing: bool = true

var UNIT_SIZE: float = 96.0

var horizontal_locks: Array[float]
var vertical_locks: Array[float]
var look_ups: Array[bool]
var look_downs: Array[bool]

var player_pos: Vector2

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
	
func shake_camera(strength, fadeSpeed):
	camera_shake.emit(strength, fadeSpeed)	
	
