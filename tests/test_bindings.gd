extends Node

# 集成测试：覆盖需要 InputMap / autoload / 场景树的部分（--script 模式不会注册 autoload）。
# 运行：godot --headless --path . --scene res://tests/test_bindings.tscn --quit-after 60

const VOLUME_ROW_SCENE := preload("res://scenes/menus/components/rows/volume_row.tscn")

var _passed := 0
var _failed := 0
var _backup := PackedByteArray()


func _ready() -> void:
	_backup = _read_settings()

	_test_set_binding_ok()
	_test_reserved_key_rejected()
	_test_conflict_detection()
	_test_conflict_steals_key()
	_test_reset_binding()
	_test_volume_clamped()
	_test_slider_step_matches_settings()
	# 回归：滑条曾把存档里非整格的音量吸附后反向写回配置
	_test_slider_does_not_overwrite_config()
	_test_locale_switch()

	# 等写盘合并窗口过去，再把玩家原本的配置放回去
	await get_tree().create_timer(Settings.SAVE_DEBOUNCE + 0.05).timeout
	_restore_settings()
	print("通过 %d 项，失败 %d 项" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func _settings_path() -> String:
	return ProjectSettings.globalize_path(Settings.SETTINGS_PATH)


func _read_settings() -> PackedByteArray:
	var file := FileAccess.open(_settings_path(), FileAccess.READ)
	if file == null:
		return PackedByteArray()
	var data := file.get_buffer(file.get_length())
	file.close()
	return data


# 测试会改动 user://settings.cfg，结束后还原，不打扰玩家的真实设置
func _restore_settings() -> void:
	var path := _settings_path()
	if _backup.is_empty():
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
		return
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return
	file.store_buffer(_backup)
	file.close()


func _test_set_binding_ok() -> void:
	_check(Settings.set_binding(&"up", _key(KEY_K)) == Settings.BindResult.OK, "绑定未被占用的按键成功")
	_check(Settings.events_equal(Settings.get_binding(&"up", false), _key(KEY_K)), "绑定后可以读回新按键")
	Settings.reset_binding(&"up", false)


func _test_reserved_key_rejected() -> void:
	_check(Settings.set_binding(&"up", _key(KEY_ESCAPE)) == Settings.BindResult.RESERVED_KEY, "Esc 被判定为保留键")
	_check(!Settings.events_equal(Settings.get_binding(&"up", false), _key(KEY_ESCAPE)), "保留键没有写进 InputMap")
	_check(Settings.set_binding(&"up", _key(KEY_TAB)) == Settings.BindResult.RESERVED_KEY, "Tab 被判定为保留键")


func _test_conflict_detection() -> void:
	# up 的默认键盘键是 W
	_check(Settings.conflicting_actions(&"jump", _key(KEY_W)).has(&"up"), "已占用该键的动作会被列出")
	_check(Settings.conflicting_actions(&"up", _key(KEY_K)).is_empty(), "未被占用的按键没有冲突")
	_check(Settings.conflicting_actions(&"up", null).is_empty(), "空事件不产生冲突")


func _test_conflict_steals_key() -> void:
	Settings.reset_binding(&"jump", false)
	_check(Settings.set_binding(&"jump", _key(KEY_W)) == Settings.BindResult.OK, "抢占已占用的按键仍然成功")
	_check(Settings.events_equal(Settings.get_binding(&"jump", false), _key(KEY_W)), "跳跃拿到了 W")
	_check(Settings.get_binding(&"up", false) != null, "被抢走的“向上”补回了默认按键")
	Settings.reset_binding(&"jump", false)


func _test_reset_binding() -> void:
	Settings.set_binding(&"down", _key(KEY_L))
	Settings.reset_binding(&"down", false)
	_check(Settings.is_binding_default(&"down", false), "恢复默认后回到默认按键")


func _test_volume_clamped() -> void:
	var original := Settings.get_volume("Music")
	Settings.set_volume("Music", 2.0)
	_check(is_equal_approx(Settings.get_volume("Music"), 1.0), "超过 1 的音量被夹到 1")
	Settings.set_volume("Music", -1.0)
	_check(is_equal_approx(Settings.get_volume("Music"), 0.0), "小于 0 的音量被夹到 0")
	Settings.set_volume("Music", original)


func _test_slider_step_matches_settings() -> void:
	var row := _instantiate_volume_row()
	_check(is_equal_approx(row.slider.step, Settings.VOLUME_STEP * 100.0), "滑条步进由 Settings.VOLUME_STEP 推导")
	row.free()


func _test_slider_does_not_overwrite_config() -> void:
	var row := _instantiate_volume_row()
	Settings.set_volume("Sound", 0.37)
	_check(is_equal_approx(Settings.get_volume("Sound"), 0.37), "非整格的音量不会被滑条吸附后写回")
	row.free()


func _test_locale_switch() -> void:
	var original := Settings.get_locale()
	Settings.set_locale("en")
	_check(TranslationServer.get_locale() == "en", "切换语言后 TranslationServer 跟着变")
	_check(Settings.get_locale() == "en", "切过的语言能从配置里读回")

	Settings.set_locale("zh_CN")
	_check(Settings.get_locale() == "zh_CN", "可以再切回中文")

	# 不支持的语言直接忽略，避免把 TranslationServer 设成一个没有翻译表的语言
	Settings.set_locale("xx")
	_check(Settings.get_locale() == "zh_CN", "不支持的语言被忽略")

	Settings.set_locale(original)


func _instantiate_volume_row() -> VolumeRow:
	var row := VOLUME_ROW_SCENE.instantiate() as VolumeRow
	row.bus_name = "Sound"
	add_child(row)
	return row


func _key(keycode: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.physical_keycode = keycode
	return event


func _check(condition: bool, description: String) -> void:
	if condition:
		_passed += 1
	else:
		_failed += 1
		print("失败：%s" % description)
