extends Node


## 任一物品数量变化时发出；HUD 据此刷新。
signal changed(item_id: StringName, total: int)


var _items: Dictionary = {}


func add(item_id: StringName, amount: int) -> int:
	var total := int(_items.get(item_id, 0)) + amount
	_items[item_id] = total
	changed.emit(item_id, total)
	return total


func count(item_id: StringName) -> int:
	return int(_items.get(item_id, 0))


func spend(item_id: StringName, amount: int) -> bool:
	if count(item_id) < amount:
		return false
	add(item_id, -amount)
	return true


## 新开一局 / 回到主菜单时清空。
func reset() -> void:
	_items.clear()


## 存档用：把物品表转成可 JSON 序列化的字典。
func to_dict() -> Dictionary:
	var out := {}
	for item_id in _items:
		out[String(item_id)] = int(_items[item_id])
	return out


## 读档用：整体覆盖物品表，并逐个发信号让 HUD 刷新。
func load_from_dict(data: Dictionary) -> void:
	_items.clear()
	for key in data:
		var item_id := StringName(String(key))
		var total := int(data[key])
		_items[item_id] = total
		changed.emit(item_id, total)
