extends Area2D
class_name LevelGate

## 区域转场门：玩家进入触发区就切到 target_area 的 target_entry。
##
## 防弹门三重保险：
##   1. _armed 标志：触发一次后立刻上锁，直到玩家离开触发区；
##   2. 换关完成后，若本次就是从"本门对应的入口"出生，先保持上锁，
##      等玩家真正离开触发区再解锁（避免出来就被弹回去）；
##   3. GameSession.is_traveling() 期间一律忽略。

## 目标区域场景（res://.../*.tscn）
@export_file("*.tscn") var target_area: String = ""
## 目标区域里的入口 ID（EntryPoint.entry_id）
@export var target_entry: StringName = &"default"
## 本门 ID：换关后如果出生入口等于它，本门先不解锁。留空时用节点名。
@export var gate_id: StringName = &""
## 只允许站在地面上时触发（防止空中撞到门上沿误触）。
@export var requires_ground: bool = false

var _armed := true


func _ready() -> void:
	if gate_id == &"":
		gate_id = StringName(name)
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	GameSession.area_changed.connect(_on_area_changed)


func _on_body_entered(body: Node2D) -> void:
	if not _armed or not body.is_in_group(&"player"):
		return
	if GameSession.is_traveling():
		return
	if requires_ground and body is CharacterBody2D and not (body as CharacterBody2D).is_on_floor():
		return
	_armed = false
	# 延迟一帧：本门所属的 Area 马上会被释放，不能在信号回调里继续用它
	GameSession.travel_to.call_deferred(target_area, target_entry)


func _on_body_exited(body: Node2D) -> void:
	if body.is_in_group(&"player"):
		_armed = true


func _on_area_changed(_area_path: String, entry_id: StringName) -> void:
	_armed = entry_id != gate_id
	# 出生点不在本门范围内 → 立刻解锁；真在范围内则等 body_exited 再解锁
	await get_tree().physics_frame
	if is_instance_valid(self) and not _overlaps_player():
		_armed = true


func _overlaps_player() -> bool:
	for body in get_overlapping_bodies():
		if body.is_in_group(&"player"):
			return true
	return false
