class_name Localization
extends SettingsSection


## 语言切换成功并写入存档后发出。参数 locale：新的语言代码（zh_CN / en / zh_TW）。
## 界面收到后需要重刷文本（KeyBindingRow 等连它刷新按键提示）。
signal locale_changed(locale: String)

const DEFAULT_LOCALE := "zh_CN"
const LOCALE_OPTIONS: Array[String] = ["zh_CN", "en", "zh_TW"]
const LOCALE_NAMES: Dictionary = {
	"zh_CN": "简体中文",
	"en": "English",
	"zh_TW": "繁體中文",
}

static func initial_locale() -> String:
	var system_locale := OS.get_locale()
	if LOCALE_OPTIONS.has(system_locale):
		return system_locale
	var language := system_locale.substr(0, 2)
	for option in LOCALE_OPTIONS:
		if option.substr(0, 2) == language:
			return option
	return DEFAULT_LOCALE


func get_locale() -> String:
	var stored: Variant = _store.get_value(SettingsStore.LOCALE_SETTING_NAME, SettingsStore.LOCALE_KEY, "")
	if stored is String and LOCALE_OPTIONS.has(stored as String):
		return stored as String
	return initial_locale()


func set_locale(locale: String) -> void:
	if !LOCALE_OPTIONS.has(locale):
		push_error("不支持的语言：%s" % locale)
		return
	TranslationServer.set_locale(locale)
	_store.set_value(SettingsStore.LOCALE_SETTING_NAME, SettingsStore.LOCALE_KEY, locale)
	save()
	locale_changed.emit(locale)


static func locale_display_name(locale: String) -> String:
	return LOCALE_NAMES.get(locale, locale) as String


func reset() -> void:
	set_locale(DEFAULT_LOCALE)
