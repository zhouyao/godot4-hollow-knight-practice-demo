class_name SavePlayerDetails
extends HBoxContainer

## 存档槽左侧的状态摘要：生命 / 灵魂（能量）/ 钱币。
## 数值来自 SaveManager.get_summary()，没有存档数据时显示 “—”。


@onready var _health_label: Label = $Health/Label
@onready var _energy_label: Label = $Energy/Label
@onready var _coin_label: Label = $Coin/Label


func display(summary: Dictionary) -> void:
	var max_health := int(summary.get("max_health", 0))
	var health := int(summary.get("health", 0))
	_health_label.text = "%d/%d" % [health, max_health] if max_health > 0 else "—"

	var max_energy := int(summary.get("max_energy", 0))
	var energy := int(summary.get("energy", 0))
	_energy_label.text = "%d/%d" % [energy, max_energy] if max_energy > 0 else "—"

	_coin_label.text = str(int(summary.get("coin", 0)))
