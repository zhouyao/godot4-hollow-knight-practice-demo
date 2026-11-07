extends MenuRow
class_name VolumeRow


## 本行控制的音频总线名，必须是 AudioServer 里存在的总线（Master / Sound / Music 之一）。
@export var bus_name: String = ""

@onready var slider: HSlider = $Slider
@onready var value_label: Label = $ValueLabel
@onready var reset_button: ResetButton = $Reset


func _ready() -> void:
	super._ready()
	slider.step = Settings.volume.VOLUME_STEP * 100.0
	reset_button.set_meta(Tr.SOURCE_META_TOOLTIP, "重置默认值")
	reset_button.tooltip_text = tr("重置默认值")

	slider.value_changed.connect(_on_value_changed)
	slider.drag_ended.connect(_on_drag_ended)
	reset_button.pressed.connect(_on_reset_pressed)
	Settings.volume.volume_update.connect(_on_volume_update)

	_sync_to(Settings.volume.get_volume(bus_name))


func _exit_tree() -> void:
	if Settings.volume.volume_update.is_connected(_on_volume_update):
		Settings.volume.volume_update.disconnect(_on_volume_update)


func _on_value_changed(value: float) -> void:
	Settings.volume.set_volume(bus_name, value / 100.0)
	_sync_from_slider()


func _on_drag_ended(_value_changed: bool) -> void:
	Settings.volume.commit_volume(bus_name)


func _on_reset_pressed() -> void:
	Settings.volume.set_volume(bus_name, Settings.volume.DEFAULT_VOLUME)
	Settings.volume.commit_volume(bus_name)


func _on_volume_update(updated_bus: String, value: float) -> void:
	if updated_bus != bus_name:
		return
	_sync_to(value)


func _sync_to(value: float) -> void:
	slider.set_value_no_signal(value * 100.0)
	_sync_from_slider()


func _sync_from_slider() -> void:
	value_label.text = "%d%%" % roundi(slider.value)
	var changed := absf(slider.value / 100.0 - Settings.volume.DEFAULT_VOLUME) > Settings.volume.VOLUME_STEP * 0.5
	reset_button.set_available(changed)
