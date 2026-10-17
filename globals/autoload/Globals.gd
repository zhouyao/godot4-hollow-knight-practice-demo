extends Node

# 全局单例：集中登记场景路径与切换入口。
# 注意：Godot 禁止 class_name 与 autoload 名同名（会报 “hides an autoload singleton”），
# 因此这里不声明 class_name，全局以 autoload 名 Globals 访问。
# 场景之间不互相 preload，避免 default_menu <-> system_settings_menu 的循环引用。

const MAIN_MENU_SCENE_PATH := "res://main.tscn"
const SYSTEM_SETTINGS_SCENE_PATH := "res://scenes/menus/system_settings_menu.tscn"


func go_to_main_menu() -> void:
	get_tree().change_scene_to_file(MAIN_MENU_SCENE_PATH)


func go_to_system_settings() -> void:
	get_tree().change_scene_to_file(SYSTEM_SETTINGS_SCENE_PATH)


func quit_game() -> void:
	# Settings 的写盘有 debounce，直接 quit 会把最后一次音量 / 按键改动丢掉
	Settings.flush()
	get_tree().quit()
