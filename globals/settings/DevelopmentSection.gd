class_name DevelopmentSection
extends SettingsSection


## 调试模式变化并落盘后发出。UI 连它同步下拉框的选中项。
signal debug_mode_changed(enabled: bool)

## 保持与现状一致：Demo 中角色调试面板默认显示。
const DEFAULT_DEBUG_MODE := true


## 启动时把存档值回填到运行时开关。autoload 顺序里 Globals 早于 Settings，
## 此时主场景尚未加载，后续角色 _ready() 会读到回填后的值。
func load() -> void:
	Globals.debug_enabled = get_debug_mode()


func get_debug_mode() -> bool:
	var stored: Variant = _store.get_value(
		SettingsStore.DEVELOPMENT_SETTING_NAME,
		SettingsStore.DEBUG_MODE_KEY,
		DEFAULT_DEBUG_MODE,
	)
	if stored is bool:
		return stored as bool
	return DEFAULT_DEBUG_MODE


func set_debug_mode(enabled: bool) -> void:
	if enabled == get_debug_mode():
		return
	_store.set_value(
		SettingsStore.DEVELOPMENT_SETTING_NAME,
		SettingsStore.DEBUG_MODE_KEY,
		enabled,
	)
	save()
	# 立即驱动在场的玩家 / 敌人 / Boss 调试面板（CharacterDebug 连了这个信号）
	Globals.debug_enabled = enabled
	debug_mode_changed.emit(enabled)


func reset() -> void:
	set_debug_mode(DEFAULT_DEBUG_MODE)
