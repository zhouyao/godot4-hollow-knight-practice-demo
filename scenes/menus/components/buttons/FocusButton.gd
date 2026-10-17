extends Button
class_name FocusButton

# 菜单按钮：聚焦时播放切换音，按下时播放确认音。
# 音效由 autoload 上的 UiAudio 播放，音频播放器不会随场景切换一起被销毁，
# 所以菜单动作在按下的瞬间就可以执行，不必等音效放完，避免操作上的停滞感。

# 同时兼作 _on_focus_entered 的回声开关，避免 grab_focus() 回调导致音效重播
var focused: bool = false
# 标记焦点是否由鼠标悬停抢来，只有鼠标抢来的焦点才会在移出时释放
var focus_from_mouse: bool = false


func focus(play_sound := true) -> void:
	focused = true
	focus_from_mouse = false
	if play_sound:
		UiAudio.play_focus_change()
	grab_focus()


# 鼠标悬停等场景只抢焦点，不播音效
func quiet_focus() -> void:
	focused = true
	focus_from_mouse = true
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
		quiet_focus()


func _on_mouse_exited() -> void:
	if has_focus() and focus_from_mouse and !disabled:
		release_focus()


func _on_pressed() -> void:
	UiAudio.play_confirm()
