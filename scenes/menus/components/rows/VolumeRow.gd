extends MenuRow
class_name VolumeRow

# 一条音量配置项：显示名称 + 音量滑条 + 数值 + 非默认值时出现的重置按钮。

@export var bus_name: String = ""

@onready var slider: HSlider = $Slider
@onready var value_label: Label = $ValueLabel
@onready var reset_button: ResetButton = $Reset


func _ready() -> void:
	super._ready()
	# step 由 Settings.VOLUME_STEP 推导，不再在场景里另写一份 5.0
	slider.step = Settings.VOLUME_STEP * 100.0
	reset_button.tooltip_text = tr("重置默认值")

	slider.value_changed.connect(_on_value_changed)
	slider.drag_ended.connect(_on_drag_ended)
	reset_button.pressed.connect(_on_reset_pressed)
	Settings.volume_update.connect(_on_volume_update)

	# 滑条会把值吸附到 step 网格上，这里用 set_value_no_signal 写入，
	# 否则回弹的 value_changed 会把存档里非整格的音量反向覆盖掉
	_sync_to(Settings.get_volume(bus_name))


func _exit_tree() -> void:
	if Settings.volume_update.is_connected(_on_volume_update):
		Settings.volume_update.disconnect(_on_volume_update)


# 鼠标拖动与方向键都从这里进：只改音频总线与显示。
# 落盘与预览音由 Settings 负责：鼠标走 drag_ended 的即时提交，
# 方向键 / 手柄没有结束事件，由 Settings 的静止提交兜底
func _on_value_changed(value: float) -> void:
	Settings.set_volume(bus_name, value / 100.0)
	_sync_from_slider()


func _on_drag_ended(_value_changed: bool) -> void:
	Settings.commit_volume(bus_name)


func _on_reset_pressed() -> void:
	Settings.set_volume(bus_name, Settings.DEFAULT_VOLUME)
	Settings.commit_volume(bus_name)


# 音量也可能被本行以外的来源改动，这里只把变化同步回滑条，不再回写 config
func _on_volume_update(updated_bus: String, value: float) -> void:
	if updated_bus != bus_name:
		return
	_sync_to(value)


func _sync_to(value: float) -> void:
	slider.set_value_no_signal(value * 100.0)
	_sync_from_slider()


# 以滑条的值为准来显示，保证被 step 吸附后的滑块位置与百分比数字始终一致
func _sync_from_slider() -> void:
	value_label.text = "%d%%" % roundi(slider.value)
	var changed := absf(slider.value / 100.0 - Settings.DEFAULT_VOLUME) > Settings.VOLUME_STEP * 0.5
	reset_button.set_available(changed)
