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

@export_group("背景视差 Parallax")
## 让本关所有 `ParallaxBg`（Background/ 下挂 parallax_bg.gd 的节点）共用同一个参考机位：
## 相机走到参考机位时，整个背景与编辑器里的摆放**完全重合**，之后才按 move_layer 视差。
## 关掉 = 旧行为（每层以自己的位置为锚，运行时永远对不上编辑器构图）。
@export var parallax_reference_enabled := false

## 参考机位取 `CameraBounds` 的中心（相机活动范围的正中）。
## 关掉则用下面的 `parallax_reference_camera` 手填。
@export var parallax_reference_from_bounds := true

## 手填的参考机位（世界坐标，相机中心点）；只在上一项关闭时生效。
@export var parallax_reference_camera := Vector2.ZERO

## 背景视差是否有可用参考机位（`ParallaxBg` 逐层向上找本节点时调用）。
func has_parallax_reference() -> bool:
	return parallax_reference_enabled


## 本关的参考机位；取不到 `CameraBounds` 时回落到手填值。
func get_parallax_reference_camera() -> Vector2:
	if not parallax_reference_from_bounds:
		return parallax_reference_camera
	var bounds := get_node_or_null(^"CameraBounds")
	if bounds != null and bounds.has_method(&"get_center_rect"):
		var rect: Rect2 = bounds.call(&"get_center_rect")
		if rect.size != Vector2.ZERO:
			return rect.get_center()
	return parallax_reference_camera


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

	var rig := preload("res://addons/camera_director/AuCameraRig.gd").new() as AuCameraRig
	rig.name = "AuCameraRig"
	add_child(rig)
	# F6 时 GameSession.bind_root 不会跑，zoom_changed 没人接：自己接一条刷新边界。
	if not rig.zoom_changed.is_connected(_on_standalone_zoom_changed):
		rig.zoom_changed.connect(_on_standalone_zoom_changed)

	var p := player_scene.instantiate()
	p.name = "Player"
	add_child(p)

	var entry_id := GameSession.current_entry_id
	if entry_id == &"":
		entry_id = &"default"
	var marker := get_entry(entry_id)
	if marker == null:
		marker = get_entry(&"default")
	p.global_position = marker.global_position if marker != null else Vector2.ZERO
	p.reset_physics_interpolation()

	GameSession.player = p

	# 正常流程由 GameSession._swap_area() 应用区域 zoom；F6 直接跑单关时在这里补上。
	var bounds := get_node_or_null(^"CameraBounds")
	if bounds != null and bounds.has_method(&"apply_zoom_config"):
		bounds.call(&"apply_zoom_config", rig.zoom)

	# F6 时相机是在 (0,0) 新建的，正常换关那套 teleport_to 没有跑，不硬切就会
	# 从原点平滑滑到玩家身上（表现为开场"镜头下移"）。这里补一次瞬移：
	# 目标取角色原点，与各关卡 _process 里的 set_target_pos() 保持一致，进场后零位移。
	rig.teleport_to(p.global_position)


func _on_standalone_zoom_changed(_new_zoom: Vector2) -> void:
	_apply_camera_bounds_for_standalone()


## F6 单关调试：按当前 zoom 重算四条 limit。子类（moss_hole 等）可覆盖同名方法。
func _apply_camera_bounds_for_standalone() -> void:
	var rig := get_node_or_null(^"AuCameraRig") as AuCameraRig
	var bounds := get_node_or_null(^"CameraBounds")
	if rig == null or bounds == null or not bounds.has_method(&"get_camera_limits"):
		return
	var limits: Rect2 = bounds.call(&"get_camera_limits", rig.zoom, get_viewport().get_visible_rect().size)
	if limits.size.x > 0.0 and limits.size.y > 0.0:
		rig.set_limits(
			int(limits.position.x), int(limits.position.y),
			int(limits.end.x), int(limits.end.y)
		)
