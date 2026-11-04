extends Button
class_name ResetButton


const SIZE := 40.0

const RESET_ICON := preload("res://assets/icons/reset.svg")


func _ready() -> void:
	icon = RESET_ICON
	custom_minimum_size = Vector2(SIZE, SIZE)
	expand_icon = true
	set_available(false)


func set_available(enabled: bool) -> void:
	disabled = !enabled
	modulate.a = 1.0 if enabled else 0.0
