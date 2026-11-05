class_name DevelopmentSection
extends SettingsSection


## 调试模式变化并落盘后发出。UI 连它同步下拉框的选中项。
signal debug_mode_changed(enabled: bool)

## 保持与现状一致：Demo 中角色调试面板默认显示。
const DEFAULT_DEBUG_MODE := true


## 启动时把存档值回填到运行时开关。autoload 顺序里 Globals 早于 Settings，
## 此时主场景尚未加载，后续角色 _ready() 会读到回填后的值。
func load() -> void:
	var enabled := get_debug_mode()
	Globals.debug_enabled = enabled
	_apply_navigation_debug(enabled)


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
	_apply_navigation_debug(enabled)
	debug_mode_changed.emit(enabled)


func reset() -> void:
	set_debug_mode(DEFAULT_DEBUG_MODE)


## 导航调试绘制的总闸：NavigationAgent2D.debug_enabled 只决定「这只怪画不画路径」，
## 运行时还得先打开 NavigationServer2D 的 debug 才会真正绘制（默认关闭，编辑器里对应
## Debug > Visible Navigation）。这些接口只在 debug build 生效，release 导出直接跳过。
func _apply_navigation_debug(enabled: bool) -> void:
	if OS.is_debug_build():
		NavigationServer2D.set_debug_enabled(enabled)
