extends Node2D
class_name WorldArea

## 关卡底座（Area）：只负责"一块区域"的内容。
##
## Player / HUD / SkillBar / 相机 / 暂停菜单 / 死亡结算全部常驻在
## res://scenes/worlds/game_root.tscn，由 GameSession 统一调度；
## 本脚本只保留"关卡自己该知道的事"：区域名、入口点、出门判定。
##
## 节点约定（world_template.tscn 已固定，子关卡继承后只往里填内容）：
##   LevelTransitions/
##     Entries/        EntryPoint：换关后玩家落点
##     Gates/          LevelGate：走进来就切到别的区域
##   CameraBounds/     CameraBoundsRect：编辑器里可拖拽的相机中心活动范围
##   Drops/            掉落物容器（GameSession 把常驻 Player 插在它前面，保持绘制顺序）
##   KillBox/          掉出地图即死
##   EnemyZones/       敌人领地
##   CameraLock/       相机锁定区

## 存档页显示的关卡名；子关卡可在场景里覆盖。
@export var zone_name: String = ""


func _ready() -> void:
	# 直接用 F6 运行本关卡时自举一个可玩的临时环境（正常流程不会走到这里）
	if get_tree().current_scene == self:
		_bootstrap_standalone()


## 按 entry_id 找入口标记。找不到返回 null，由 GameSession 回落 / 报警。
func get_entry(entry_id: StringName) -> Node2D:
	var base := get_node_or_null(^"LevelTransitions")
	if base == null:
		return null

	var containers: Array[Node] = []
	var entries := base.get_node_or_null(^"Entries")
	if entries != null:
		containers.append(entries)
	containers.append(base)

	for container in containers:
		for child in container.get_children():
			if child is Node2D and child.get(&"entry_id") == entry_id:
				return child as Node2D

	# 兜底 1：入口点直接用 entry_id 当节点名时，按名字查
	var by_name := base.get_node_or_null(String(entry_id))
	if by_name is Node2D:
		return by_name as Node2D

	# 兜底 2：长椅这类"自带 entry_id 的物件"不一定挂在 LevelTransitions 下，
	# 全树扫描一次（只在换关 / 读档时调用，节点量级很小）。
	for node in find_children("*", "", true, false):
		if node is Node2D and node.get(&"entry_id") == entry_id:
			return node as Node2D
	return null


func _on_kill_box_body_entered(body: Node2D) -> void:
	if "kill" in body:
		body.kill()


# ---------------------------------------------------------------- 单关调试自举

## F6 直接跑 level_*.tscn 时补上玩家与相机，避免必须先进 game_root 才能调试。
func _bootstrap_standalone() -> void:
	var player_scene := load("res://scenes/characters/players/player/player.tscn") as PackedScene
	if player_scene == null:
		return

	var rig := preload("res://addons/camera_director/AuCameraRig.gd").new()
	rig.name = "AuCameraRig"
	add_child(rig)

	var p := player_scene.instantiate()
	p.name = "Player"
	add_child(p)

	var marker := get_entry(&"default")
	p.global_position = marker.global_position if marker != null else Vector2.ZERO
	p.reset_physics_interpolation()

	GameSession.player = p
