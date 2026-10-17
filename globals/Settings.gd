extends Node

# 注意：Godot 禁止 class_name 与 autoload 名同名（会报 “hides an autoload singleton”），
# 因此这里不声明 class_name，全局以 autoload 名 Settings 访问。

signal volume_update(bus_name: String, value: float)
# 一次音量调节结束（滑条松手 / 重置）时才发出，用于落盘与播放预览音
signal volume_committed(bus_name: String)
signal binding_update
# 语言切换成功后发出，菜单据此重刷文案
signal locale_changed(locale: String)

# 绑定结果：用于把失败原因反馈到 UI，而不是静默忽略
enum BindResult { OK, RESERVED_KEY, UNSUPPORTED_EVENT }

const SETTINGS_PATH := "user://settings.cfg"
const AUDIO_SETTING_NAME := "Audio"
const INPUT_SETTING_NAME := "Input"
const LOCALE_SETTING_NAME := "Locale"

# 语言在配置里单独占一项，与音量 / 按键分开存
const LOCALE_KEY := "locale"
const DEFAULT_LOCALE := "zh_CN"
# 可切换的语言，顺序即设置菜单里的展示顺序
const LOCALE_OPTIONS: Array[String] = ["zh_CN", "en"]
# 语言名固定用它自己的语言书写，切到英文后中文选项也不会变成译名
const LOCALE_NAMES: Dictionary = {
	"zh_CN": "简体中文",
	"en": "English",
}

const MASTER_BUS_NAME := "Master"
const SOUND_BUS_NAME := "Sound"
const MUSIC_BUS_NAME := "Music"
const VOLUME_BUS_NAMES: Array[String] = [MASTER_BUS_NAME, SOUND_BUS_NAME, MUSIC_BUS_NAME]
const DEFAULT_VOLUME := 0.5
# 键盘/手柄步进与滑条 step 的唯一真相，滑条在 _ready 里据此设置 step
const VOLUME_STEP := 0.05
# 连续调节会把多次写入合并成一次，避免每按一格就全量写盘
const SAVE_DEBOUNCE := 0.3
# 键盘/手柄调节音量没有 drag_ended 可以通知，改动静止这么久就认为一次调节结束
const COMMIT_DEBOUNCE := 0.4

const KEYBOARD_TAG := "key"
const GAMEPAD_TAG := "pad"

const UNBOUND_TEXT := "未绑定"

# 保留给菜单导航与系统功能的按键，不允许被绑定，否则玩家可能把自己锁在设置界面里
const RESERVED_KEYS: Array[int] = [KEY_ESCAPE, KEY_TAB, KEY_ENTER, KEY_KP_ENTER]
# 手柄侧同样要保留：B 是 ui_cancel（任何菜单里按它就返回上一级 / 退出），
# Start 是系统菜单键。留这两颗就够，再多（比如 A 确认键）会连跳跃、攻击都绑不了
const RESERVED_PAD_BUTTONS: Array[int] = [JOY_BUTTON_B, JOY_BUTTON_START]

# 可重绑定的动作，顺序即设置菜单中的展示顺序
const BINDABLE_ACTIONS: Array[StringName] = [&"up", &"down", &"left", &"right", &"attack", &"jump"]

const DEFAULT_KEYBOARD_KEYS: Dictionary = {
	&"up": KEY_W,
	&"down": KEY_S,
	&"left": KEY_A,
	&"right": KEY_D,
	&"attack": KEY_J,
	&"jump": KEY_SPACE,
}

const DEFAULT_GAMEPAD_BUTTONS: Dictionary = {
	&"up": JOY_BUTTON_DPAD_UP,
	&"down": JOY_BUTTON_DPAD_DOWN,
	&"left": JOY_BUTTON_DPAD_LEFT,
	&"right": JOY_BUTTON_DPAD_RIGHT,
	&"attack": JOY_BUTTON_X,
	&"jump": JOY_BUTTON_A,
}

const KEY_DISPLAY_NAMES: Dictionary = {
	KEY_SPACE: "空格",
	KEY_ENTER: "回车",
	KEY_KP_ENTER: "回车",
	KEY_ESCAPE: "Esc",
	KEY_TAB: "Tab",
	KEY_UP: "↑",
	KEY_DOWN: "↓",
	KEY_LEFT: "←",
	KEY_RIGHT: "→",
}

const PAD_BUTTON_NAMES: Dictionary = {
	JOY_BUTTON_A: "A 键",
	JOY_BUTTON_B: "B 键",
	JOY_BUTTON_X: "X 键",
	JOY_BUTTON_Y: "Y 键",
	JOY_BUTTON_LEFT_SHOULDER: "LB 键",
	JOY_BUTTON_RIGHT_SHOULDER: "RB 键",
	JOY_BUTTON_DPAD_UP: "十字键 上",
	JOY_BUTTON_DPAD_DOWN: "十字键 下",
	JOY_BUTTON_DPAD_LEFT: "十字键 左",
	JOY_BUTTON_DPAD_RIGHT: "十字键 右",
	JOY_BUTTON_START: "菜单键",
	JOY_BUTTON_BACK: "返回键",
}

var _config: ConfigFile = ConfigFile.new()
var _bus_indexes: Dictionary = {}
var _save_timer: SceneTreeTimer = null
# bus_name -> 待提交的 SceneTreeTimer，用来判定一次连续调节是否已经停下
var _commit_timers: Dictionary = {}

# physical_keycode -> keycode 的换算要跨 DisplayServer 查询，缓存下来避免每次刷新都问一遍
static var _keycode_cache: Dictionary = {}


func _ready() -> void:
	if _config.load(SETTINGS_PATH) != OK:
		_reset_volume_to_default()
	_cache_bus_indexes()
	_apply_all_volumes()

	ensure_default_bindings()
	load_bindings()
	purge_reserved_bindings()

	# 存档语言优先，没存过时跟随系统语言
	TranslationServer.set_locale(get_locale())

	# 窗口关闭按钮 / 系统快捷键退出前保住最后一次改动。这里连 root 的 close_requested
	# 而不是 NOTIFICATION_WM_CLOSE_REQUEST：后者是否广播到 autoload 节点取决于引擎实现，
	# 而 quit() 触发的退出根本走不到它，那条路径由 Globals.quit_game() 负责
	get_tree().root.close_requested.connect(flush)


#region 音量

# 存档不存在或读取失败时写入默认值，只落一次盘
func _reset_volume_to_default() -> void:
	for bus_name in VOLUME_BUS_NAMES:
		_config.set_value(AUDIO_SETTING_NAME, bus_name, DEFAULT_VOLUME)
	save_settings()


func _apply_all_volumes() -> void:
	for bus_name in VOLUME_BUS_NAMES:
		_apply_volume(bus_name, get_volume(bus_name))


func _apply_volume(bus_name: String, value: float) -> void:
	var index := _bus_index(bus_name)
	if index < 0:
		return
	AudioServer.set_bus_volume_db(index, linear_to_db(value))


# 总线缺失时给出明确报错，而不是往 -1 索引上写数据后静默失效
func _cache_bus_indexes() -> void:
	for bus_name in VOLUME_BUS_NAMES:
		var index := AudioServer.get_bus_index(bus_name)
		if index < 0:
			push_error("音频总线缺失：%s" % bus_name)
			continue
		_bus_indexes[bus_name] = index


func _bus_index(bus_name: String) -> int:
	var cached: Variant = _bus_indexes.get(bus_name)
	if cached != null:
		return cached as int
	var index := AudioServer.get_bus_index(bus_name)
	_bus_indexes[bus_name] = index
	return index


# 存档缺字段时回落到默认值；外部改坏的存档在这里就被夹到合法范围，不会传到 linear_to_db
func get_volume(bus_name: String) -> float:
	var stored: Variant = _config.get_value(AUDIO_SETTING_NAME, bus_name, DEFAULT_VOLUME)
	if stored is bool:
		return DEFAULT_VOLUME
	var value := float(stored)
	if is_nan(value):
		return DEFAULT_VOLUME
	return clampf(value, 0.0, 1.0)


# 任何来源的音量改动都走这里：鼠标拖动、方向键、手柄、代码。
# 只改内存与音频总线，写盘与预览音交给一次“提交”，连续调节不会被拆成多次。
func set_volume(bus_name: String, value: float) -> void:
	var volume := clampf(value, 0.0, 1.0)
	_config.set_value(AUDIO_SETTING_NAME, bus_name, volume)
	_apply_volume(bus_name, volume)
	volume_update.emit(bus_name, volume)
	# 拖动有 drag_ended 可以通知提交，方向键 / 手柄没有，这里兜底排一个静止提交
	_queue_commit(bus_name)


# 一次调节结束（滑条松手 / 重置 / 静止超时）时调用：落盘并通知 UI 播放预览音
func commit_volume(bus_name: String) -> void:
	_cancel_commit(bus_name)
	save_settings()
	volume_committed.emit(bus_name)


# 真正的写盘：多次请求在 SAVE_DEBOUNCE 窗口内合并成一次
func save_settings() -> void:
	if get_tree() == null:
		_flush_settings()
		return
	if _save_timer != null:
		_save_timer.time_left = SAVE_DEBOUNCE
		return
	_save_timer = get_tree().create_timer(SAVE_DEBOUNCE)
	_save_timer.timeout.connect(_flush_settings)


# 退出前把还在 debounce 窗口里的改动立刻写盘，不再等 debounce / 静止提交到点
func flush() -> void:
	_commit_timers.clear()
	_flush_settings()


func _queue_commit(bus_name: String) -> void:
	var timer: SceneTreeTimer = _commit_timers.get(bus_name)
	if timer != null:
		timer.time_left = COMMIT_DEBOUNCE
		return
	if get_tree() == null:
		save_settings()
		return
	timer = get_tree().create_timer(COMMIT_DEBOUNCE)
	_commit_timers[bus_name] = timer
	timer.timeout.connect(_on_commit_timeout.bind(bus_name, timer))


# SceneTreeTimer 没有 stop()，取消只能把登记表里的位置腾空
func _cancel_commit(bus_name: String) -> void:
	_commit_timers.erase(bus_name)


# 比对 timer 身份而不是只看有没有登记：一次提交之后又开了新一轮调节时，
# 上一轮的 timer 到点不能顺手把新一轮也提前提交掉
func _on_commit_timeout(bus_name: String, timer: SceneTreeTimer) -> void:
	if _commit_timers.get(bus_name) != timer:
		return
	_commit_timers.erase(bus_name)
	commit_volume(bus_name)


func _flush_settings() -> void:
	_save_timer = null
	var error := _config.save(SETTINGS_PATH)
	if error != OK:
		push_warning("设置写入失败（%d）：%s" % [error, SETTINGS_PATH])

#endregion


#region 按键绑定

# 保证每个可绑定动作都存在，且键盘/手柄两侧都有默认绑定
func ensure_default_bindings() -> void:
	for action in BINDABLE_ACTIONS:
		if !InputMap.has_action(action):
			InputMap.add_action(action)
		if get_binding(action, false) == null:
			var keyboard_event := default_binding(action, false)
			if keyboard_event:
				InputMap.action_add_event(action, keyboard_event)
		if get_binding(action, true) == null:
			var gamepad_event := default_binding(action, true)
			if gamepad_event:
				InputMap.action_add_event(action, gamepad_event)


# 用配置文件中保存的按键覆盖 InputMap 的默认值
# 注意：action_get_events() 返回的是副本，可以安全地在遍历中修改 InputMap
func load_bindings() -> void:
	for action in BINDABLE_ACTIONS:
		for gamepad in [false, true]:
			var bind_name := bind_key(action, gamepad)
			if !_config.has_section_key(INPUT_SETTING_NAME, bind_name):
				continue
			var saved_event = _config.get_value(INPUT_SETTING_NAME, bind_name)
			if !(saved_event is InputEvent):
				continue
			for existing_event in InputMap.action_get_events(action):
				if is_gamepad_event(existing_event) == gamepad:
					InputMap.action_erase_event(action, existing_event)
			InputMap.action_add_event(action, saved_event)


func default_binding(action: StringName, gamepad: bool) -> InputEvent:
	if gamepad:
		var button: int = DEFAULT_GAMEPAD_BUTTONS.get(action, JOY_BUTTON_INVALID)
		if button == JOY_BUTTON_INVALID:
			return null
		var pad_event := InputEventJoypadButton.new()
		pad_event.button_index = button as JoyButton
		return pad_event

	var keycode: int = DEFAULT_KEYBOARD_KEYS.get(action, KEY_NONE)
	if keycode == KEY_NONE:
		return null
	var key_event := InputEventKey.new()
	key_event.keycode = keycode as Key
	key_event.physical_keycode = keycode as Key
	return key_event


func get_binding(action: StringName, gamepad: bool) -> InputEvent:
	if !InputMap.has_action(action):
		return null
	for event in InputMap.action_get_events(action):
		if is_gamepad_event(event) == gamepad:
			return event
	return null


# 除自己以外，当前还有哪些动作已经占用了同一个按键
static func conflicting_actions(action: StringName, event: InputEvent) -> Array[StringName]:
	var conflicts: Array[StringName] = []
	if event == null:
		return conflicts
	for other_action in BINDABLE_ACTIONS:
		if other_action == action:
			continue
		if InputMap.action_has_event(other_action, event):
			conflicts.append(other_action)
	return conflicts


# 绑定新按键：同类型的旧绑定被替换；被别的动作占用时会抢过来，并给对方补回默认键。
# 返回 BindResult 让 UI 能解释失败原因，而不是静默什么都不做。
func set_binding(action: StringName, event: InputEvent) -> BindResult:
	var new_event := clean_event(event)
	if new_event == null:
		return BindResult.UNSUPPORTED_EVENT
	if is_reserved_event(new_event):
		return BindResult.RESERVED_KEY

	var gamepad := is_gamepad_event(new_event)

	for other_action in conflicting_actions(action, new_event):
		InputMap.action_erase_event(other_action, new_event)
		if get_binding(other_action, gamepad) == null:
			var fallback_event := default_binding(other_action, gamepad)
			if fallback_event and !InputMap.action_has_event(other_action, fallback_event):
				InputMap.action_add_event(other_action, fallback_event)

	for existing_event in InputMap.action_get_events(action):
		if is_gamepad_event(existing_event) == gamepad:
			InputMap.action_erase_event(action, existing_event)
	InputMap.action_add_event(action, new_event)

	save_bindings()
	return BindResult.OK


# 只保留按键本身，去掉按下状态等一次性信息，便于存储与比较
static func clean_event(event: InputEvent) -> InputEvent:
	if event == null:
		return null
	var clean := event.duplicate() as InputEvent
	var key_event := clean as InputEventKey
	if key_event != null:
		key_event.pressed = false
		key_event.echo = false
		return key_event
	var button_event := clean as InputEventJoypadButton
	if button_event != null:
		button_event.pressed = false
		button_event.pressure = 0.0
		return button_event
	return clean


static func is_reserved_event(event: InputEvent) -> bool:
	var key_event := event as InputEventKey
	if key_event != null:
		var keycode := key_of(key_event)
		return keycode != KEY_NONE and RESERVED_KEYS.has(keycode)
	var button_event := event as InputEventJoypadButton
	if button_event != null:
		return RESERVED_PAD_BUTTONS.has(button_event.button_index)
	return false


# 保留名单会随版本变化，旧存档里已经绑上的保留输入在这里一次性退回默认
func purge_reserved_bindings() -> void:
	var changed := false
	for action in BINDABLE_ACTIONS:
		for event in InputMap.action_get_events(action):
			if !is_reserved_event(event):
				continue
			InputMap.action_erase_event(action, event)
			var fallback := default_binding(action, is_gamepad_event(event))
			if fallback and !InputMap.action_has_event(action, fallback):
				InputMap.action_add_event(action, fallback)
			changed = true
	if changed:
		save_bindings()


func reset_binding(action: StringName, gamepad: bool) -> void:
	for existing_event in InputMap.action_get_events(action):
		if is_gamepad_event(existing_event) == gamepad:
			InputMap.action_erase_event(action, existing_event)
	var default_event := default_binding(action, gamepad)
	if default_event:
		InputMap.action_add_event(action, default_event)
	save_bindings()


func is_binding_default(action: StringName, gamepad: bool) -> bool:
	return events_equal(get_binding(action, gamepad), default_binding(action, gamepad))


# 只保存与默认不同的绑定，减小配置文件体积
func save_bindings() -> void:
	for action in BINDABLE_ACTIONS:
		for gamepad in [false, true]:
			var key_name := bind_key(action, gamepad)
			var event := get_binding(action, gamepad)
			if events_equal(event, default_binding(action, gamepad)):
				if _config.has_section_key(INPUT_SETTING_NAME, key_name):
					_config.erase_section_key(INPUT_SETTING_NAME, key_name)
			else:
				_config.set_value(INPUT_SETTING_NAME, key_name, event)
	save_settings()
	binding_update.emit()


static func bind_key(action: StringName, gamepad: bool) -> String:
	return "%s_%s" % [action, GAMEPAD_TAG if gamepad else KEYBOARD_TAG]


# 摇杆也算手柄事件，但当前绑定槽只接受按键（见 KeyBindingRow._input）
static func is_gamepad_event(event: InputEvent) -> bool:
	return event is InputEventJoypadButton or event is InputEventJoypadMotion


static func events_equal(a: InputEvent, b: InputEvent) -> bool:
	if a == null or b == null:
		return a == null and b == null
	if a.get_class() != b.get_class():
		return false
	var key_a := a as InputEventKey
	if key_a != null:
		var key_b := b as InputEventKey
		var same_modifiers := key_a.ctrl_pressed == key_b.ctrl_pressed \
			and key_a.shift_pressed == key_b.shift_pressed \
			and key_a.alt_pressed == key_b.alt_pressed \
			and key_a.meta_pressed == key_b.meta_pressed
		if !same_modifiers:
			return false
		if key_a.keycode != KEY_NONE and key_b.keycode != KEY_NONE and key_a.keycode == key_b.keycode:
			return true
		if key_a.physical_keycode != KEY_NONE and key_b.physical_keycode != KEY_NONE:
			return key_a.physical_keycode == key_b.physical_keycode
		return key_of(key_a) == key_of(key_b)
	var button_a := a as InputEventJoypadButton
	if button_a != null:
		return button_a.button_index == (b as InputEventJoypadButton).button_index
	var motion_a := a as InputEventJoypadMotion
	if motion_a != null:
		var motion_b := b as InputEventJoypadMotion
		return motion_a.axis == motion_b.axis and signf(motion_a.axis_value) == signf(motion_b.axis_value)
	return false


# project.godot 中的默认键位只写 physical_keycode，绑定时得到的会带 keycode，统一取值再比较
static func key_of(event: InputEventKey) -> int:
	if event.keycode != KEY_NONE:
		return event.keycode
	if event.physical_keycode == KEY_NONE:
		return KEY_NONE
	if _keycode_cache.has(event.physical_keycode):
		return _keycode_cache[event.physical_keycode] as int
	var keycode := DisplayServer.keyboard_get_keycode_from_physical(event.physical_keycode)
	_keycode_cache[event.physical_keycode] = keycode
	return keycode if keycode != KEY_NONE else event.physical_keycode


# 静态函数调不到 tr()，这里统一用 TranslationServer
static func event_display_name(event: InputEvent) -> String:
	if event == null:
		return TranslationServer.translate(UNBOUND_TEXT)
	var key_event := event as InputEventKey
	if key_event != null:
		var key_code := key_of(key_event) as Key
		if KEY_DISPLAY_NAMES.has(key_code):
			return TranslationServer.translate(KEY_DISPLAY_NAMES[key_code] as String)
		var key_name := OS.get_keycode_string(key_code)
		return key_name if key_name != "" else TranslationServer.translate(UNBOUND_TEXT)
	var button_event := event as InputEventJoypadButton
	if button_event != null:
		var button: int = button_event.button_index
		if PAD_BUTTON_NAMES.has(button):
			return TranslationServer.translate(PAD_BUTTON_NAMES[button] as String)
		return TranslationServer.translate("手柄按键 %d") % button
	var motion_event := event as InputEventJoypadMotion
	if motion_event != null:
		var horizontal := motion_event.axis == JOY_AXIS_LEFT_X or motion_event.axis == JOY_AXIS_RIGHT_X
		var axis_name := TranslationServer.translate("左摇杆") if horizontal else TranslationServer.translate("右摇杆")
		var direction := ["←", "→"] if horizontal else ["↑", "↓"]
		return "%s %s" % [axis_name, direction[0] if motion_event.axis_value < 0.0 else direction[1]]
	return event.as_text()

#endregion


#region 语言

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
	var stored: Variant = _config.get_value(LOCALE_SETTING_NAME, LOCALE_KEY, "")
	if stored is String and LOCALE_OPTIONS.has(stored as String):
		return stored as String
	return initial_locale()


# 切换语言：立即生效并落盘，菜单靠 locale_changed 重刷文案
func set_locale(locale: String) -> void:
	if !LOCALE_OPTIONS.has(locale):
		push_error("不支持的语言：%s" % locale)
		return
	TranslationServer.set_locale(locale)
	_config.set_value(LOCALE_SETTING_NAME, LOCALE_KEY, locale)
	save_settings()
	locale_changed.emit(locale)


static func locale_display_name(locale: String) -> String:
	return LOCALE_NAMES.get(locale, locale) as String

#endregion
