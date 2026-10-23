extends VBoxContainer


@onready var language_option: OptionButton = $OptionRow/LanguageOption

func _ready() -> void:
	_build_language_option()
	Settings.localization.locale_changed.connect(_on_locale_changed)
	_sync_language_option()

func _exit_tree() -> void:
	if Settings.localization.locale_changed.is_connected(_on_locale_changed):
		Settings.localization.locale_changed.disconnect(_on_locale_changed)

func _build_language_option() -> void:
	for locale in Settings.localization.LOCALE_OPTIONS:
		language_option.add_item(Localization.locale_display_name(locale))

func _on_locale_changed(_locale: String) -> void:
	_sync_language_option()

func _sync_language_option() -> void:
	var index := Settings.localization.LOCALE_OPTIONS.find(Settings.localization.get_locale())
	if language_option.selected != index:
		language_option.selected = index

func _on_language_option_item_selected(index: int) -> void:
	Settings.localization.set_locale(Settings.localization.LOCALE_OPTIONS[index])
