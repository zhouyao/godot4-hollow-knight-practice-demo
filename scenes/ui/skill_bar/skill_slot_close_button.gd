extends Control
class_name SkillSlotCloseButton

## 已绑定槽位右上角的小叉：点击即解绑当前槽位。
## 自身只负责绘制与点击，可见性由 SkillSlot.refresh_close_button 控制
##（仅技能面板打开且本槽已绑定时显示，避免游戏中误触）。


var _slot: SkillSlot
var _hover := false


func _ready() -> void:
	custom_minimum_size = Vector2(22, 22)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_slot = get_parent() as SkillSlot
	mouse_entered.connect(func(): _hover = true; queue_redraw())
	mouse_exited.connect(func(): _hover = false; queue_redraw())
	gui_input.connect(_on_gui_input)


func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			get_viewport().set_input_as_handled()
			if _slot != null:
				_slot.request_remove()


func _draw() -> void:
	var c := size * 0.5
	var radius := c.x
	var fill := Color(0.88, 0.3, 0.3, 0.96) if _hover else Color(0.55, 0.18, 0.18, 0.9)
	draw_circle(c, radius, fill)
	var t := radius * 0.4
	var lw := maxf(2.0, radius * 0.22)
	draw_line(c - Vector2(t, t), c + Vector2(t, t), Color.WHITE, lw, true)
	draw_line(c - Vector2(t, -t), c + Vector2(t, -t), Color.WHITE, lw, true)
