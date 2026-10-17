extends VBoxContainer

# 语言设置面板：独立场景，自带 OptionButton 的构建 / 同步 / 选择逻辑。
# 切语言时只回写 Settings.localization，由它广播 locale_changed，
# 各场景（含本面板所在的 SystemSettingsMenu）据此重刷文案。

@onready var language_option: OptionButton = $OptionRow/LanguageOption

func _ready() -> void:
	_build_language_option()
	Settings.localization.locale_changed.connect(_on_locale_changed)
	_sync_language_option()

func _exit_tree() -> void:
	if Settings.localization.locale_changed.is_connected(_on_locale_changed):
		Settings.localization.locale_changed.disconnect(_on_locale_changed)

# 下拉框选项由 Settings.localization.LOCALE_OPTIONS 生成，加一门语言只改那一处。
# 选项文字用语言自己的写法，不参与当前语言的翻译。
func _build_language_option() -> void:
	for locale in Settings.localization.LOCALE_OPTIONS:
		language_option.add_item(Localization.locale_display_name(locale))

# 切语言后只同步选中项（下拉框内文字是固定写法，面板文案由 SystemSettingsMenu 的
# Tr.apply(self) 统一刷新）。
func _on_locale_changed(_locale: String) -> void:
	_sync_language_option()

# 选中项已经是当前语言时就不再回写，避免下拉框与 set_locale 互相触发。
func _sync_language_option() -> void:
	var index := Settings.localization.LOCALE_OPTIONS.find(Settings.localization.get_locale())
	if language_option.selected != index:
		language_option.selected = index

func _on_language_option_item_selected(index: int) -> void:
	Settings.localization.set_locale(Settings.localization.LOCALE_OPTIONS[index])
