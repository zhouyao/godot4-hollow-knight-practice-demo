extends Button
class_name FocusButton


var focused: bool = false
var focus_from_mouse: bool = false


func focus(play_sound := true) -> void:
	focused = true
	focus_from_mouse = false
	if play_sound:
		UiAudio.play_focus_change()
	grab_focus()


## 静默聚焦：进菜单自动聚焦首个按钮时不吵，但鼠标划过（play_sound=true）要出声，
## 对齐 HK 原版——那边 _on_mouse_entered 直接转成 focus_entered，一样播切换音。
func quiet_focus(play_sound := false) -> void:
	focused = true
	focus_from_mouse = true
	if play_sound:
		UiAudio.play_focus_change()
	grab_focus()


func _on_focus_entered() -> void:
	if focused:
		return
	focus()


func _on_focus_exited() -> void:
	focused = false
	focus_from_mouse = false


func _on_mouse_entered() -> void:
	if !has_focus() and !disabled:
		quiet_focus(true)


func _on_mouse_exited() -> void:
	if has_focus() and focus_from_mouse and !disabled:
		release_focus()


func _on_pressed() -> void:
	UiAudio.play_confirm()
