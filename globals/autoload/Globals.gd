extends Node

## 关卡准备期开始 / 结束时发出，供状态机、UI 等订阅（避免每帧轮询）
signal level_preparing_changed(is_preparing: bool)

const MAIN_MENU_SCENE_PATH := "res://main.tscn"
const SYSTEM_SETTINGS_SCENE_PATH := "res://scenes/menus/system_settings_menu.tscn"
const GAME_SCENE_PATH := "res://scenes/worlds/world_test.tscn"

# ---- 2D 物理层位掩码 ----
# 与「项目设置 → 层名称 → 2d_physics」一一对应：层号 n 的掩码是 1 << (n - 1)。
# 集中放这里的好处：改层号只需改本文件，不用在场景和各脚本里找散落的数字；
# 写代码时用 Globals.LAYER_XXX 而不是裸数字 2 / 32，可读性也更好。
# 注意：这里只定义掩码常量，不代替 .tscn 里的 collision_layer / collision_mask 设置。

## 层 1：玩家本体。玩家 CharacterBody2D 默认就在这一层。
const LAYER_PLAYER := 1 << 0
## 层 2：敌人。玩家各攻击判定区靠它过滤「只打怪、不弹地板」。
const LAYER_ENEMIES := 1 << 1
## 层 3：可站立、可击打的场景物件（地面、箱子…）。
const LAYER_OBJECTS := 1 << 2
## 层 4：子弹 / 投射物。
const LAYER_PROJECTILES := 1 << 3
## 层 5：触发区（相机锁定区、KillBox…）自己所在的层，它们靠 mask 只探测玩家。
const LAYER_AREAS_AND_ZONES := 1 << 4
## 层 6：玩家 / 敌人身上各攻击、侦测 Area2D 的专用层，避免被物理世界当成实体互相碰撞。
## 目前没有任何东西的 mask 指向本层，所以复用它是安全的；将来要做弹反 / 格挡，
## 只需在那一侧的 Area 的 mask 里加上本层即可。
const LAYER_DETECTION_AND_ATTACK := 1 << 5
## 层 7：不与玩家碰撞的物体（单向平台、纯装饰…）。
const LAYER_NO_PLAYER_COLLISION := 1 << 6
## 层 8：掉落物。
const LAYER_DROPS := 1 << 7
## 层 9：可被前刺打掉的背景装饰（前刺判定区额外侦测这一层）。
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
