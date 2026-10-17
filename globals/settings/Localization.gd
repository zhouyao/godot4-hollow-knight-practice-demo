class_name Localization
extends SettingsSection

# 语言子系统：负责 Locale 的读取、切换与展示名。继承 SettingsSection 接入 Settings 统一的
# 写盘调度，从而把“语言切换”这一块逻辑从 Settings 中独立出来。

# 语言切换成功后发出，菜单据此重刷文案
signal locale_changed(locale: String)

# 语言在配置里单独占一项，与音量 / 按键分开存
const DEFAULT_LOCALE := "zh_CN"
# 可切换的语言，顺序即设置菜单里的展示顺序
const LOCALE_OPTIONS: Array[String] = ["zh_CN", "en"]
# 语言名固定用它自己的语言书写，切到英文后中文选项也不会变成译名
const LOCALE_NAMES: Dictionary = {
	"zh_CN": "简体中文",
	"en": "English",
}

# 没存过语言时的取值：系统语言直接可选就用它，否则退到同语言的第一个变体，
# 再不行回落到 DEFAULT_LOCALE
static func initial_locale() -> String:
	var system_locale := OS.get_locale()
	if LOCALE_OPTIONS.has(system_locale):
		return system_locale
	var language := system_locale.substr(0, 2)
	for option in LOCALE_OPTIONS:
		if option.substr(0, 2) == language:
			return option
	return DEFAULT_LOCALE


# 存档里没存过、或存了表里没有的语言时，都回落到自动判定
func get_locale() -> String:
	var stored: Variant = _store.get_value(SettingsStore.LOCALE_SETTING_NAME, SettingsStore.LOCALE_KEY, "")
	if stored is String and LOCALE_OPTIONS.has(stored as String):
		return stored as String
	return initial_locale()


# 切换语言：立即生效并落盘，菜单靠 locale_changed 重刷文案
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


# 重置为默认语言并落盘、应用（统一接口，便于“恢复默认”一次性重置所有设置项）
func reset() -> void:
	set_locale(DEFAULT_LOCALE)
