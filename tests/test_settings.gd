extends SceneTree

# 零依赖单元测试，覆盖 Settings 中不依赖场景树的纯函数。
# 运行：godot --headless --path . --script res://tests/test_settings.gd

const SettingsScript := preload("res://globals/Settings.gd")

var _passed := 0
var _failed := 0


func _initialize() -> void:
	_test_bind_key()
	_test_is_gamepad_event()
	_test_key_of()
	_test_clean_event()
	_test_events_equal()
	_test_event_display_name()
	_test_locale_options()

	print("通过 %d 项，失败 %d 项" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)


func _check(condition: bool, description: String) -> void:
	if condition:
		_passed += 1
	else:
		_failed += 1
		print("失败：%s" % description)


func _test_locale_options() -> void:
	_check(SettingsScript.LOCALE_OPTIONS.has("zh_CN"), "中文在可选语言里")
	_check(SettingsScript.LOCALE_OPTIONS.has("en"), "英文在可选语言里")

	var initial := SettingsScript.initial_locale()
	_check(SettingsScript.LOCALE_OPTIONS.has(initial), "自动判定的语言一定是可选语言")

	_check(SettingsScript.locale_display_name("zh_CN") == "简体中文", "中文显示自己的名字")
	_check(SettingsScript.locale_display_name("en") == "English", "英文显示自己的名字")
	_check(SettingsScript.locale_display_name("xx") == "xx", "表里没有的语言回落到代号本身")


func _key(keycode: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.physical_keycode = keycode
	return event


func _test_bind_key() -> void:
	_check(SettingsScript.bind_key(&"up", false) == "up_key", "bind_key 生成键盘键名")
	_check(SettingsScript.bind_key(&"jump", true) == "jump_pad", "bind_key 生成手柄键名")


func _test_is_gamepad_event() -> void:
	_check(SettingsScript.is_gamepad_event(InputEventJoypadButton.new()), "手柄按键判定为手柄事件")
	_check(SettingsScript.is_gamepad_event(InputEventJoypadMotion.new()), "摇杆判定为手柄事件")
	_check(!SettingsScript.is_gamepad_event(_key(KEY_W)), "键盘按键不判定为手柄事件")


func _test_key_of() -> void:
	_check(SettingsScript.key_of(_key(KEY_W)) == KEY_W, "key_of 优先取 keycode")

	var physical_only := InputEventKey.new()
	physical_only.physical_keycode = KEY_W
	# headless 下 DisplayServer 不支持 physical -> keycode 转换，跳过该分支
	if DisplayServer.get_name() != "headless":
		_check(SettingsScript.key_of(physical_only) != KEY_NONE, "key_of 回退到 physical_keycode")

	var empty := InputEventKey.new()
	_check(SettingsScript.key_of(empty) == KEY_NONE, "key_of 无按键时返回 KEY_NONE")


func _test_clean_event() -> void:
	var event := _key(KEY_J)
	event.pressed = true
	event.echo = true
	var clean := SettingsScript.clean_event(event)
	_check(clean is InputEventKey, "clean_event 保持按键类型")
	_check(!(clean as InputEventKey).pressed, "clean_event 清除按下状态")
	_check(!(clean as InputEventKey).echo, "clean_event 清除 echo")
	_check(SettingsScript.clean_event(null) == null, "clean_event 容忍 null")


func _test_events_equal() -> void:
	_check(SettingsScript.events_equal(null, null), "两个 null 视为相等")
	_check(!SettingsScript.events_equal(_key(KEY_W), null), "null 与非空不相等")
	_check(SettingsScript.events_equal(_key(KEY_W), _key(KEY_W)), "相同按键相等")
	_check(!SettingsScript.events_equal(_key(KEY_W), _key(KEY_S)), "不同按键不相等")

	var physical_only := InputEventKey.new()
	physical_only.physical_keycode = KEY_W
	_check(SettingsScript.events_equal(_key(KEY_W), physical_only), "只写 physical_keycode 的按键与默认键位相等")

	var shifted := _key(KEY_W)
	shifted.shift_pressed = true
	_check(!SettingsScript.events_equal(_key(KEY_W), shifted), "修饰键不同的按键不相等")

	_check(!SettingsScript.events_equal(_key(KEY_W), InputEventJoypadButton.new()), "不同类型按键不相等")


func _test_event_display_name() -> void:
	_check(SettingsScript.event_display_name(null) == TranslationServer.translate("未绑定"), "无绑定时显示未绑定")
	_check(SettingsScript.event_display_name(_key(KEY_SPACE)) == "空格", "空格键显示中文名")

	var pad_event := InputEventJoypadButton.new()
	pad_event.button_index = JOY_BUTTON_A
	_check(SettingsScript.event_display_name(pad_event) == "A 键", "手柄按键显示中文名")
