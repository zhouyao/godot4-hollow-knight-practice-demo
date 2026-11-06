extends EntryPoint
class_name Bench

## 长椅 / 椅子（存档点）：玩家碰到就存档，并把重生点改成这张长椅。
##
## 为什么继承 EntryPoint：存档里存的出生点就是 entry_id，
## 长椅自己带一个 entry_id 就能被 WorldArea.get_entry() 直接找到，
## 读档 / 死亡后不用额外配置"这张椅子对应哪个入口"。
##
## 位置约定与 EntryPoint 一致：节点原点 = 玩家胶囊中心（离地 75px），
## 所以长椅摆在"地面 y - 75"的位置，视觉方块由 Visual 子节点往下偏。
##
## 两种模式（由 sit_on_enter 决定）：
##   · 关闭（普通长椅）：碰到即存档，玩家保持站立。
##   · 开启（废墟小屋的椅子）：碰到即存档 + 弹"存档成功" + 自动进 sit 状态回血回能，
##     玩家按方向键 / 跳跃 / 攻击 / 技能键可主动起身；起身后本椅子重新上冷却，
##     要等玩家离开检测区再重新进入才会再次触发。

signal rested

## 椅子上方的进场提示（WorldPrompt 自带 5 秒倒计时，只显示一次）。
const WORLD_PROMPT_SCENE := preload("res://scenes/ui/world_prompt.tscn")

## 休息时是否写盘（关掉可用于纯视觉的装饰椅）。
@export var save_on_rest := true
## 两次触发之间的最小间隔（秒），防止玩家贴着椅子反复触发。
@export var rest_cooldown := 1.5
## 休息闪光时长（秒）。
@export var flash_time := 0.25

@export_group("坐下 Sit Down")
## 进入检测区是否自动坐下（坐下期间由 sit 状态每 0.5s 回 1 血 1 能）。
## 普通长椅保持关闭；废墟小屋的 RuinChair 在场景里显式打开。
@export var sit_on_enter := false
## 座位锚点（像素，y 向下为正）：坐下时玩家原点被放到「本节点原点 + 该偏移」并钉住。
## 本节点原点按 EntryPoint 约定落在地面上，所以要靠负的 y 把角色抬到椅面高度：
## 调法是看坐下后屁股相对椅面的高低，差多少就调多少（废墟小屋的椅子约 -43）。
@export var seat_offset: Vector2 = Vector2.ZERO

@export_group("提示 Prompt")
## 提示框锚点（像素，y 向下为正）：存档 / 休息提示的箭头尖落在这里。
## 默认抬到椅背上方、并高过坐下时的角色头顶；想让它更贴近椅子就把 y 调大（更接近 0）。
@export var prompt_offset: Vector2 = Vector2(0, -145)

var _cooldown_until := 0
var _flash_tween: Tween = null
## 当前坐在这张椅子上的玩家：非空期间不重复触发，玩家起身后复位。
var _seat_player: PlayerInitial = null
## 出生 / 读档检查：为 true 表示玩家是被放到椅子上的（不是走进来的），本次重叠不触发坐下。
var _spawn_inside := false
var _spawn_checked := false
## 椅子上方的"坐下"提示：只有可坐的椅子（sit_on_enter）才创建。
var _sit_prompt: WorldPrompt = null

@onready var _detect: Area2D = $DetectArea
@onready var _visual: Sprite2D = $Visual


func _ready() -> void:
	super._ready()
	_detect.body_entered.connect(_on_body_entered)
	_detect.body_exited.connect(_on_body_exited)
	_create_sit_prompt()
	_check_spawn_overlap()


## 可坐的椅子在场景加载完就把提示亮出来：玩家一进场就能看到"坐下"。
## 这是一次性提示：显示 5 秒后自动淡出（WorldPrompt.auto_hide_time），玩家提前坐下则立刻收掉；
## 收掉之后不再重新亮，免得"存档成功"之后又冒出"坐下"。
## 读档正好落在椅子上时同样显示（这种情况不会自动坐），离开检测区再走进来即可坐。
func _create_sit_prompt() -> void:
	if not sit_on_enter:
		return
	var prompt := WORLD_PROMPT_SCENE.instantiate() as WorldPrompt
	if prompt == null:
		return
	add_child(prompt)
	prompt.setup(self, prompt_offset, "坐下")
	_sit_prompt = prompt
	prompt.show_prompt()


## 等两个物理帧（玩家已经被放到入口 / 存档坐标）再判断是否正好站在检测区里。
## 读档时玩家就落在本椅子上，此时触发坐下会在 SaveManager 回填数据之前写盘，写进脏数据。
func _check_spawn_overlap() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame
	_spawn_inside = _has_player_overlap()
	_spawn_checked = true


func _has_player_overlap() -> bool:
	for body in _detect.get_overlapping_bodies():
		if body.is_in_group(&"player"):
			return true
	return false


func _on_body_entered(body: Node2D) -> void:
	if not body.is_in_group(&"player"):
		return
	if sit_on_enter:
		if not _spawn_checked or _spawn_inside:
			return
		_sit_down(body)
		return
	if Time.get_ticks_msec() < _cooldown_until:
		return
	_cooldown_until = Time.get_ticks_msec() + int(rest_cooldown * 1000.0)
	rest()


func _on_body_exited(body: Node2D) -> void:
	if not body.is_in_group(&"player"):
		return
	# 真的离开检测区了：重新武装，下次走进来照常自动坐下。
	_spawn_inside = false
	# 玩家正坐在这张椅子上时，座位锚点（seat_offset）可能刚好落在 DetectArea 边界外，
	# 误触发本信号。此时他其实还在坐，别收掉座位记号（否则会被当成离座再次触发坐下）。
	if body == _seat_player:
		return
	# "坐下"是进场一次性提示：坐下时或 5 秒后淡出，之后不再重新亮。
	# 存档成功（Toast）之后又冒出"坐下"就是这里曾经重新 show 造成的。


## 提示框（"存档成功" / "已休息 · 已保存"）的箭头尖该指向哪：
## game_root 收到 GameSession.sat / rested 后按 entry_id 回查本节点拿到这里。
func get_prompt_anchor() -> Vector2:
	return global_position + prompt_offset


## 主动休息：把重生点切到本长椅并落盘。
func rest() -> void:
	GameSession.current_entry_id = entry_id
	if save_on_rest:
		# 坐标钉在长椅本身：玩家可能是从旁边蹭到检测区的
		SaveManager.save_game(false, global_position)
	_flash()
	GameSession.notify_rested(entry_id)
	rested.emit()


## 自动坐下：存档 → 提示"存档成功" → 把玩家放到座位（原点 + seat_offset）并切进 sit 状态。
## 关卡准备中（转场 / 读档回填）不触发：玩家正好会被放在本椅子上，
## 那时存档会把还没回填的玩家数据写进存档。
func _sit_down(body: Node2D) -> void:
	var player := body as PlayerInitial
	if player == null or _seat_player != null or player.dead:
		return
	if Globals.level_preparing or GameSession.is_traveling() or get_tree().paused:
		return
	if Time.get_ticks_msec() < _cooldown_until:
		return
	_cooldown_until = Time.get_ticks_msec() + int(rest_cooldown * 1000.0)

	# 已经决定要坐下：先收起"坐下"提示，避免和紧跟着弹出的"存档成功"叠在同一处。
	# 不依赖 sit_down() 的返回值 —— 存档反馈已经发出，这次即使切状态失败也该收掉提示。
	if _sit_prompt != null:
		_sit_prompt.hide_prompt()

	GameSession.current_entry_id = entry_id
	if save_on_rest:
		SaveManager.save_game(false, global_position)
	_flash()
	GameSession.notify_sat(entry_id)
	rested.emit()

	if not player.sit_down(global_position + seat_offset):
		return
	# 等真正坐下了才连：起身（坐 / 受击 / 死亡）由状态机通知本椅子收掉记号。
	_seat_player = player
	player.state_machine.state_changed.connect(_on_seat_player_state_changed)


## 玩家离开 sit 状态（主动起身 / 受击 / 死亡）→ 收掉记号并重新上冷却。
func _on_seat_player_state_changed(new_state: StringName, _old_state: StringName) -> void:
	if new_state != PlayerStateNames.SIT:
		_release_seat()


func _release_seat() -> void:
	if is_instance_valid(_seat_player) and _seat_player.state_machine != null \
			and _seat_player.state_machine.state_changed.is_connected(_on_seat_player_state_changed):
		_seat_player.state_machine.state_changed.disconnect(_on_seat_player_state_changed)
	_seat_player = null
	_cooldown_until = Time.get_ticks_msec() + int(rest_cooldown * 1000.0)


func _flash() -> void:
	if _visual == null:
		return
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	_visual.modulate = Color(2.4, 2.8, 3.2, 1.0)
	_flash_tween = create_tween()
	_flash_tween.tween_property(_visual, "modulate", Color.WHITE, flash_time)
