extends Node2D
class_name WorldTemplate


const PAUSE_MENU_SCENE := preload("res://scenes/menus/pause_menu/pause_menu.tscn")
var pause_menu: CanvasLayer = null

const SKILL_PANEL_SCENE := preload("res://scenes/menus/skill_panel/skill_panel.tscn")
var skill_panel: CanvasLayer = null

## 死亡结算遮罩（黑场 + 3 秒倒数）。
const DEATH_SCREEN_SCENE := preload("res://scenes/ui/death_screen.tscn")

## 常驻技能条（技能面板打开时保持可见以便拖放，暂停菜单打开时隐藏）。
@onready var skill_bar: SkillBar = $SkillBar
@onready var player: PlayerInitial = $Player

## 存档页显示的关卡名；子关卡可在场景里覆盖。
@export var zone_name: String = ""

func _ready():
	Input.set_mouse_mode(Input.MOUSE_MODE_CONFINED_HIDDEN)
	# 技能条靠这个引用读技能冷却：子节点先 ready，这里注入后每帧才会读到值。
	if skill_bar != null:
		skill_bar.player = player
	if player != null:
		player.player_death.connect(_on_player_death)
	# 兜底：进游戏时用存档值对齐一次窗口（覆盖启动延迟 apply 偶发的时序失败）。
	Settings.display.apply_now()
	# 读档：把 SaveManager 里的玩家 / 背包 / 能力数据回填到刚加载好的关卡。
	SaveManager.apply_pending_state(self)

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


func _on_kill_box_body_entered(body: Node2D) -> void:
	if "kill" in body:
		body.kill()
