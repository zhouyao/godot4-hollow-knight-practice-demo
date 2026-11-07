class_name DevelopmentSection
extends SettingsSection


## 调试模式变化并落盘后发出。UI 连它同步下拉框的选中项。
signal debug_mode_changed(enabled: bool)
## 首页路径变化并落盘后发出。UI 连它同步输入框。
signal home_path_changed(path: String)
## 敌方出生血量覆盖变化并落盘后发出。UI 连它同步输入框。
signal boss_health_changed(value: int)
signal mob_health_changed(value: int)

## 调试模式默认关闭；只有开发设置里手动选「开启」才显示角色调试信息与寻路路径。
const DEFAULT_DEBUG_MODE := false
## 敌方出生血量覆盖：0 = 沿用关卡原始值（默认，不打乱现有关卡数值）；
## 1~999 = 该类敌人一律满血出生，max_health 与 initial_health 同时取该值。
const DEFAULT_BOSS_HEALTH := 0
const DEFAULT_MOB_HEALTH := 0
const MAX_HEALTH_OVERRIDE := 999
## 默认首页 = 开场动画。以前硬编码在 SaveManager.DEFAULT_SCENE_PATH，
## 现在由开发设置提供，SaveManager 只保留同名常量作最后的兜底。
const DEFAULT_HOME_PATH := "res://scenes/worlds/levels/opening_cinematic/opening cinematic.tscn"


## 启动时把存档值回填到运行时开关。autoload 顺序里 Globals 早于 Settings，
## 此时主场景尚未加载，后续角色 _ready() 会读到回填后的值。
func load() -> void:
	var enabled := get_debug_mode()
	Globals.debug_enabled = enabled
	_apply_navigation_debug(enabled)
	Globals.set_enemy_health_overrides(get_boss_health(), get_mob_health())


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


# ---------------------------------------------------------------- 首页路径

## 只接受工程内真实存在的 .tscn / .scn 场景：坏路径一律回落到开场动画，
## 避免进游戏时 GameSession 加载失败黑屏。存档里的区域路径也全是 res:// 开头。
static func is_valid_home_path(path: String) -> bool:
	if not path.begins_with("res://") or not ResourceLoader.exists(path):
		return false
	var ext := path.get_extension().to_lower()
	return ext == "tscn" or ext == "scn"


func get_home_path() -> String:
	var stored: Variant = _store.get_value(
		SettingsStore.DEVELOPMENT_SETTING_NAME,
		SettingsStore.HOME_PATH_KEY,
		DEFAULT_HOME_PATH,
	)
	if stored is String and is_valid_home_path(stored):
		return stored
	return DEFAULT_HOME_PATH


## 返回是否真的写入了新路径（路径无效或与当前值相同都返回 false）。
func set_home_path(path: String) -> bool:
	var normalized := path.strip_edges()
	if not is_valid_home_path(normalized) or normalized == get_home_path():
		return false
	_store.set_value(
		SettingsStore.DEVELOPMENT_SETTING_NAME,
		SettingsStore.HOME_PATH_KEY,
		normalized,
	)
	save()
	home_path_changed.emit(normalized)
	return true


func reset_home_path() -> void:
	set_home_path(DEFAULT_HOME_PATH)


# ---------------------------------------------------------------- 敌方血量

## ConfigFile 里 bool 与数值容易混（历史上有过写错类型的配置），float 也一并接受。
## 越界 / 非法值夹到合法区间，避免血条上限与 BOSS 阶段比例算出脏值。
static func _sanitize_health(stored: Variant) -> int:
	if stored is bool:
		return 0
	if stored is int:
		return clampi(stored, 0, MAX_HEALTH_OVERRIDE)
	if stored is float and not is_nan(stored):
		return clampi(roundi(stored), 0, MAX_HEALTH_OVERRIDE)
	return 0


func get_boss_health() -> int:
	return _sanitize_health(_store.get_value(
		SettingsStore.DEVELOPMENT_SETTING_NAME,
		SettingsStore.BOSS_HEALTH_KEY,
		DEFAULT_BOSS_HEALTH,
	))


func set_boss_health(value: int) -> void:
	var normalized := clampi(value, 0, MAX_HEALTH_OVERRIDE)
	if normalized == get_boss_health():
		return
	_store.set_value(
		SettingsStore.DEVELOPMENT_SETTING_NAME,
		SettingsStore.BOSS_HEALTH_KEY,
		normalized,
	)
	save()
	Globals.set_enemy_health_overrides(normalized, get_mob_health())
	boss_health_changed.emit(normalized)


func get_mob_health() -> int:
	return _sanitize_health(_store.get_value(
		SettingsStore.DEVELOPMENT_SETTING_NAME,
		SettingsStore.MOB_HEALTH_KEY,
		DEFAULT_MOB_HEALTH,
	))


func set_mob_health(value: int) -> void:
	var normalized := clampi(value, 0, MAX_HEALTH_OVERRIDE)
	if normalized == get_mob_health():
		return
	_store.set_value(
		SettingsStore.DEVELOPMENT_SETTING_NAME,
		SettingsStore.MOB_HEALTH_KEY,
		normalized,
	)
	save()
	Globals.set_enemy_health_overrides(get_boss_health(), normalized)
	mob_health_changed.emit(normalized)


func reset() -> void:
	set_debug_mode(DEFAULT_DEBUG_MODE)
	reset_home_path()
	set_boss_health(DEFAULT_BOSS_HEALTH)
	set_mob_health(DEFAULT_MOB_HEALTH)


## 导航调试绘制的总闸：NavigationAgent2D.debug_enabled 只决定「这只怪画不画路径」，
## 运行时还得先打开 NavigationServer2D 的 debug 才会真正绘制（默认关闭，编辑器里对应
## Debug > Visible Navigation）。这些接口只在 debug build 生效，release 导出直接跳过。
func _apply_navigation_debug(enabled: bool) -> void:
	if OS.is_debug_build():
		NavigationServer2D.set_debug_enabled(enabled)
