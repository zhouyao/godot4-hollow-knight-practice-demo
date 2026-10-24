extends CanvasLayer
class_name Hud


@onready var coin_label: Label = $HBox/CoinLabel
@onready var food_label: Label = $HBox/FoodLabel


func _ready() -> void:
	Inventory.changed.connect(_on_inventory_changed)
	_refresh(&"coin", Inventory.count(&"coin"))
	_refresh(&"food", Inventory.count(&"food"))


func _on_inventory_changed(item_id: StringName, total: int) -> void:
	_refresh(item_id, total)


func _refresh(item_id: StringName, total: int) -> void:
	match item_id:
		&"coin":
			coin_label.text = "钱币: %d" % total
		&"food":
			food_label.text = "食物: %d" % total
