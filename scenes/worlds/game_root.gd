extends Node2D

## 游戏根节点（常驻）：Player / HUD / 相机 / 暂停 / 死亡结算都在这里，
## 关卡内容由 GameSession 异步挂到 WorldHost 下，切关时只换 WorldHost 的子节点。
##
## 为什么玩家不放在关卡里：切关时重建玩家会丢掉血量、能量、能力、相机绑定、
## 技能条引用等一整套运行时状态；而"把玩家在 Area 之间搬家"只有一次 remove/add，
## 还能保持它在场景树里的绘制顺序（前景仍盖住玩家）。

const PAUSE_MENU_SCENE := preload("res://scenes/menus/pause_menu/pause_menu.tscn")
const SKILL_PANEL_SCENE := preload("res://scenes/menus/skill_panel/skill_panel.tscn")
## 死亡结算遮罩（黑场 + 3 秒倒数）。
const DEATH_SCREEN_SCENE := preload("res://scenes/ui/death_screen.tscn")
## 轻量提示条（休息 / 存档反馈等）。
const TOAST_SCENE := preload("res://scenes/ui/toast.tscn")
## BOSS 击败后的胜利提示（与区域标题同版式）。
const VICTORY_TITLE_SCENE := preload("res://scenes/ui/victory_title.tscn")
## boss_defeated 在死亡瞬间发出，击败演出还要 2~3 秒才收尾；稍等再弹，别盖住升空 / 坠落淡出。
const VICTORY_DELAY := 1.6

var pause_menu: CanvasLayer = null
var skill_panel: CanvasLayer = null
## 同一时间只允许一层胜利标题（一个关卡可能连着打两只 BOSS）。
var victory_title: VictoryTitle = null

@onready var skill_bar: SkillBar = $SkillBar
@onready var hud: Hud = $Hud
@onready var player: PlayerInitial = $Player


func _ready() -> void:
	GameSession.bind_root(self)
	Input.set_mouse_mode(Input.MOUSE_MODE_CONFINED_HIDDEN)

	# 技能条靠这个引用读技能冷却；HUD 同理。两者都只绑定一次，切关不再重来。
	if skill_bar != null:
		skill_bar.player = player
	if hud != null:
		hud.bind_player(player)
	if player != null:
		player.player_death.connect(_on_player_death)
	GameSession.rested.connect(_on_rested)
	GameSession.sat.connect(_on_sat)
	GameSession.boss_defeated.connect(_on_boss_defeated)

	# 兜底：进游戏时用存档值对齐一次窗口（覆盖启动延迟 apply 偶发的时序失败）。
	Settings.display.apply_now()

	# 在"全黑"状态下把第一块区域挂上去：加载完成后才解除暂停，避免玩家在黑场里下落。
	await GameSession.bootstrap(SaveManager.current_scene_path(), SaveManager.current_entry_id())

	# 读档：把存档里的玩家 / 背包 / 能力数据回填到常驻玩家上。
	# 必须放在 bootstrap 之后 —— 存档坐标要覆盖"入口落点"。
	SaveManager.apply_pending_state(self)

	get_tree().paused = false
	Globals.level_preparing = false
	TransitionLayer.fade_in()


# ---------------------------------------------------------------- 提示

## BOSS 击败：等击败演出（升空消散 / 坠落淡出）播得差不多，再弹胜利标题。
## 标题挂在常驻的 GameRoot 下，切关不会重复创建；BOSS 的 _dead() 有守卫，整场只广播一次。
func _on_boss_defeated(_boss_id: String) -> void:
	var area := GameSession.current_area
	await get_tree().create_timer(VICTORY_DELAY).timeout
	# 期间回存档页 / 死亡结算 / 换了关卡，都不再补弹。
	if not is_instance_valid(self) or get_tree().paused or GameSession.current_area != area:
		return
	if victory_title != null and is_instance_valid(victory_title):
		victory_title.queue_free()
	victory_title = VICTORY_TITLE_SCENE.instantiate() as VictoryTitle
	add_child(victory_title)


## 长椅休息：在长椅上方弹一句"已休息 · 已保存"。
func _on_rested(bench_id: StringName) -> void:
	_show_toast("已休息 · 已保存", bench_id)


## 椅子上坐下（自动存档）：在椅子上方弹一句"存档成功"。
func _on_sat(seat_id: StringName) -> void:
	_show_toast("存档成功", seat_id)


## anchor_id 对应的物件（长椅 / 椅子）决定提示框的箭头落点；
## 拿不到（没挂 entry_id 的临时提示等）就回落屏幕下方居中，至少不会不显示。
func _show_toast(text: String, anchor_id: StringName = &"") -> void:
	var toast := TOAST_SCENE.instantiate() as Toast
	if toast == null:
		return
	add_child(toast)
	var anchor := _toast_anchor(anchor_id)
	if anchor == Vector2.INF:
		toast.show_text(text)
	else:
		toast.show_text_at(text, anchor)


## 按 entry_id 回查物件（WorldArea.get_entry），问它要提示框锚点。
func _toast_anchor(anchor_id: StringName) -> Vector2:
	if anchor_id == &"" or not is_instance_valid(GameSession.current_area):
		return Vector2.INF
	var area := GameSession.current_area
	if not area.has_method(&"get_entry"):
		return Vector2.INF
	var target: Node2D = area.call(&"get_entry", anchor_id)
	if target == null or not target.has_method(&"get_prompt_anchor"):
		return Vector2.INF
	return target.call(&"get_prompt_anchor")


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"skill"):
		get_viewport().set_input_as_handled()
		if skill_panel == null:
			open_skill_panel()
		return
	if !event.is_action_pressed(&"ui_cancel"):
		return
	get_viewport().set_input_as_handled()
	if pause_menu == null:
		open_pause()


func open_pause() -> void:
	get_tree().paused = true
	_set_skill_bar_visible(false)
	pause_menu = PAUSE_MENU_SCENE.instantiate()
	pause_menu.process_mode = Node.PROCESS_MODE_ALWAYS
	pause_menu.tree_exiting.connect(_on_pause_menu_exited)
	add_child(pause_menu)


func _on_pause_menu_exited() -> void:
	pause_menu = null
	_set_skill_bar_visible(true)


func _set_skill_bar_visible(should_show: bool) -> void:
	if skill_bar != null:
		skill_bar.visible = should_show


func open_skill_panel() -> void:
	get_tree().paused = true
	skill_panel = SKILL_PANEL_SCENE.instantiate()
	skill_panel.process_mode = Node.PROCESS_MODE_ALWAYS
	skill_panel.tree_exiting.connect(_on_skill_panel_exited)
	add_child(skill_panel)
	if skill_bar != null:
		skill_bar.set_panel_open(true)


func _on_skill_panel_exited() -> void:
	skill_panel = null
	if skill_bar != null:
		skill_bar.set_panel_open(false)


# ---------------------------------------------------------------- 死亡结算

## 死亡结算：冻结游戏 → 等死亡动作播完 → 黑场倒数 3 秒 → 回存档选择页。
func _on_player_death() -> void:
	_start_death_sequence()


func _start_death_sequence() -> void:
	# 暂停前先把死亡动作与死亡音效标成 ALWAYS：
	# 树一旦暂停，普通 AudioStreamPlayer2D 会被直接停掉（事后再改也恢复不了），
	# 死亡动作同理，必须提前放行。
	var action_player := player.action_animation_player
	action_player.process_mode = Node.PROCESS_MODE_ALWAYS

	var death_sfx := player.get_node_or_null(^"Audio/death") as AudioStreamPlayer2D
	if death_sfx != null:
		death_sfx.process_mode = Node.PROCESS_MODE_ALWAYS
		if not death_sfx.playing:
			death_sfx.play()

	# 暂停整棵树：敌人 / 物理 / 其它 UI 全停，只留下死亡动作、死亡音效与死亡遮罩。
	get_tree().paused = true

	if action_player.has_animation(PlayerStateNames.DEATH):
		if action_player.current_animation != PlayerStateNames.DEATH or not action_player.is_playing():
			action_player.play(PlayerStateNames.DEATH)
		await action_player.animation_finished

	var death_screen := DEATH_SCREEN_SCENE.instantiate()
	add_child(death_screen)
	await death_screen.play()
	Globals.return_to_save_select()
