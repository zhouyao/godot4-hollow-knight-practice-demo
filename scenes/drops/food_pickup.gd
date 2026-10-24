extends Pickup
class_name FoodPickup


## 吃掉一份食物回复的血量；实际回复量 = heal_amount * amount。
@export var heal_amount: int = 2


func _apply_effect(by: Node2D) -> void:
	if by == null or not by.has_method("heal"):
		return
	by.heal(heal_amount * amount)
