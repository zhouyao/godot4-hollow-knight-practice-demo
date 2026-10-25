extends VBoxContainer


@onready var mode_option: OptionButton = $ModeRow/ModeOption

func _ready() -> void:
	_build_mode_option()
	Settings.localization.locale_changed.connect(_on_locale_changed)
	Settings.display.window_mode_changed.connect(_on_window_mode_changed)
	Settings.display.sync_from_system()
	_sync_mode_option()

func _exit_tree() -> void:
	if Settings.localization.locale_changed.is_connected(_on_locale_changed):
		Settings.localization.locale_changed.disconnect(_on_locale_changed)
	if Settings.display.window_mode_changed.is_connected(_on_window_mode_changed):
		Settings.display.window_mode_changed.disconnect(_on_window_mode_changed)

# OptionButton 的 item 文本不会被 Tr.apply 覆盖，切语言后要整表重建
func _build_mode_option() -> void:
	mode_option.clear()
	for id in DisplaySection.MODE_IDS:
		mode_option.add_item(tr(DisplaySection.display_name(id)))
		mode_option.set_item_metadata(mode_option.item_count - 1, id)

func _sync_mode_option() -> void:
	var index := DisplaySection.MODE_IDS.find(Settings.display.get_window_mode())
	if mode_option.selected != index:
		mode_option.selected = index

func _on_window_mode_changed(_mode: int) -> void:
	_sync_mode_option()

func _on_locale_changed(_locale: String) -> void:
	_build_mode_option()
	_sync_mode_option()

func _on_mode_option_item_selected(index: int) -> void:
	Settings.display.set_window_mode(int(mode_option.get_item_metadata(index)))
