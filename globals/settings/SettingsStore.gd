extends RefCounted
class_name SettingsStore


const SETTINGS_PATH := "user://settings.cfg"
const AUDIO_SETTING_NAME := "Audio"
const INPUT_SETTING_NAME := "Input"
const LOCALE_SETTING_NAME := "Locale"
const SKILL_BAR_SETTING_NAME := "SkillBar"
const DISPLAY_SETTING_NAME := "Display"
const DEVELOPMENT_SETTING_NAME := "Development"
const LOCALE_KEY := "locale"
const DEBUG_MODE_KEY := "debug_mode"
const HOME_PATH_KEY := "home_path"
const WINDOW_MODE_KEY := "window_mode"
const WINDOW_SIZE_KEY := "window_size"

var _config: ConfigFile = ConfigFile.new()


func load_config() -> int:
	return _config.load(SETTINGS_PATH)


func save_config() -> int:
	return _config.save(SETTINGS_PATH)


func get_value(section: String, key: String, default: Variant) -> Variant:
	return _config.get_value(section, key, default)


func set_value(section: String, key: String, value: Variant) -> void:
	_config.set_value(section, key, value)


func has_key(section: String, key: String) -> bool:
	return _config.has_section_key(section, key)


func erase_key(section: String, key: String) -> void:
	_config.erase_section_key(section, key)
