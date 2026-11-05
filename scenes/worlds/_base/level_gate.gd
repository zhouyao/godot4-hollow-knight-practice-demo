extends Area2D
class_name LevelGate

## 区域转场门：玩家进入触发区就切到 target_area 的 target_entry。
##
## 为什么不能只靠 body_entered：
##   换关有黑场（fade_out / fade_in），这期间 GameSession.is_traveling() 为真，
##   门不能立刻发起新换关。但玩家完全可能在黑场里就走到了门上 —— 例如刚落到
##   入口就掉头往回走。body_entered 只会发一次，被忽略就永远丢了，玩家会直接
##   穿门掉出地图（MossHole <-> MossHole_0 实测可复现）。
##
## 因此触发分两条路：
##   1. 每物理帧复查重叠（_physics_process）：黑场结束那一刻只要人还在门里，立刻触发；
##   2. 黑场期间收到 body_entered 就记进 _pending：哪怕人已经走过去了，黑场结束也补一次。
##
## 防重入：
##   · 触发后立刻 _armed = false，玩家真正离开触发区才解锁，避免站在门上反复弹门；
##   · 换关后若本次就是从"本门对应的入口"出生，先保持上锁，等玩家离开再解锁；
##   · GameSession.is_traveling() 期间一律不发起新的换关。

## 目标区域场景（res://.../*.tscn）
@export_file("*.tscn") var target_area: String = ""
## 目标区域里的入口 ID（EntryPoint.entry_id）
@export var target_entry: StringName = &"default"
## 本门对应的回程入口 ID：换关后如果出生入口等于它，本门先不解锁。留空时用节点名。
@export var gate_id: StringName = &""
## 只允许站在地面上时触发（防止空中撞到门上沿误触）。
@export var requires_ground: bool = false

var _armed := true
## 黑场期间玩家穿过了本门：等换关结束再补一次传送。
var _pending := false


func _ready() -> void:
	if gate_id == &"":
		gate_id = StringName(name)
	body_entered.connect(_on_body_entered)
	GameSession.area_changed.connect(_on_area_changed)


func _physics_process(_delta: float) -> void:
	# 黑场里不发起新换关；穿过门的记录留在 _pending，等黑场结束再补。
	if GameSession.is_traveling():
		return

	if _pending:
		_trigger()
		return

	if not _armed:
		# 玩家真正离开触发区才重新上膛
		if not _overlaps_player():
			_armed = true
		return

	if _overlaps_player() and _ground_ok():
		_trigger()


func _on_body_entered(body: Node2D) -> void:
	if not body.is_in_group(&"player"):
		return
	# 黑场期间换关已经排队：先记下来，等 traveling 结束由 _physics_process 补触发。
	if GameSession.is_traveling():
		_pending = true
		return
	if _armed and _ground_ok():
		_trigger()


func _on_area_changed(_area_path: String, entry_id: StringName) -> void:
	_pending = false
	if entry_id == gate_id:
		# 出生点就是本门对应的回程入口：先上锁，等玩家离开再解锁
		_armed = false
		return
	# 出生点不在本门入口：等本帧物理跑完再确认玩家没有压在门里
	await get_tree().physics_frame
	if is_instance_valid(self):
		_armed = not _overlaps_player()


func _trigger() -> void:
	_armed = false
	_pending = false
	if target_area.is_empty():
		return
	# F6 单关调试：GameSession 没有挂载 current_area，直接换场景。
	# 否则新关卡会被实例化到旧关卡节点下，出现两个场景/房间重叠。
	if GameSession.current_area == null:
		GameSession.current_entry_id = target_entry
		get_tree().call_deferred(&"change_scene_to_file", target_area)
		return
	# 延迟到本帧末：本门所属的 Area 可能在换关时被释放，不能在物理回调里继续用它
	GameSession.travel_to.call_deferred(target_area, target_entry)


func _ground_ok() -> bool:
	if not requires_ground:
		return true
	var body := _player_body()
	if body == null:
		return false
	return not (body is CharacterBody2D) or (body as CharacterBody2D).is_on_floor()


func _player_body() -> Node2D:
	for body in get_overlapping_bodies():
		if body.is_in_group(&"player"):
			return body as Node2D
	return null


func _overlaps_player() -> bool:
	return _player_body() != null
