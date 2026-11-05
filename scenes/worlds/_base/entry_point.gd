extends Marker2D
class_name EntryPoint

## 关卡入口标记：GameSession 换关后把常驻玩家放到这里。
##
## entry_id 留空时用节点名，所以在编辑器里给节点改名就等于改入口 ID。
## 位置约定：玩家角色根节点在胶囊中心，站立时脚下还有 75px，
## 因此入口 y 应填"地面高度 - 75"（例如地面 y=500 → 入口 y=425）。

## 入口 ID（LevelGate.target_entry 填的就是它）。
@export var entry_id: StringName = &""

## 玩家出生朝向：0 = 不改变，1 = 朝右，-1 = 朝左。
@export_enum("不改变:0", "朝右:1", "朝左:-1") var facing: int = 0


func _ready() -> void:
	if entry_id == &"":
		entry_id = StringName(name)
