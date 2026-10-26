class_name InputBindings
extends SettingsSection


## 任意按键绑定写入后发出（设置绑定、恢复默认、清空冲突键都会触发）。
## 不携带参数：设置界面收到后应整行刷新（KeyBindingRow 就是连它做 _refresh 的）。
signal binding_update

enum BindResult { OK, RESERVED_KEY, UNSUPPORTED_EVENT }

const KEYBOARD_TAG := "key"
const GAMEPAD_TAG := "pad"

const UNBOUND_TEXT := "未绑定"

const RESERVED_KEYS: Array[int] = [KEY_ESCAPE, KEY_TAB, KEY_ENTER, KEY_KP_ENTER]
const RESERVED_PAD_BUTTONS: Array[int] = [JOY_BUTTON_B, JOY_BUTTON_START]

## 技能条 5 个槽位对应的动作名，下标即槽位序号（与 SkillBarSection 的槽位一致）。
## 玩家施放与技能条角标都从这个表取，保证三者不会错位。
const SKILL_SLOT_ACTIONS: Array[StringName] = [
	&"skill_slot_1", &"skill_slot_2", &"skill_slot_3", &"skill_slot_4", &"skill_slot_5"]

const BINDABLE_ACTIONS: Array[StringName] = [
	&"up", &"down", &"left", &"right", &"attack", &"jump", &"skill",
	&"skill_slot_1", &"skill_slot_2", &"skill_slot_3", &"skill_slot_4", &"skill_slot_5"]

## 大键盘 1~5（不是小键盘 KEY_KP_*）。
const DEFAULT_KEYBOARD_KEYS: Dictionary = {
	&"up": KEY_W,
	&"down": KEY_S,
	&"left": KEY_A,
	&"right": KEY_D,
	&"attack": KEY_J,
	&"jump": KEY_SPACE,
	&"skill": KEY_P,
	&"skill_slot_1": KEY_1,
	&"skill_slot_2": KEY_2,
	&"skill_slot_3": KEY_3,
	&"skill_slot_4": KEY_4,
	&"skill_slot_5": KEY_5,
}

## 技能槽刻意不设手柄默认键：手柄列显示"未绑定"，玩家想要可自行绑定。
const DEFAULT_GAMEPAD_BUTTONS: Dictionary = {
	&"up": JOY_BUTTON_DPAD_UP,
	&"down": JOY_BUTTON_DPAD_DOWN,
	&"left": JOY_BUTTON_DPAD_LEFT,
	&"right": JOY_BUTTON_DPAD_RIGHT,
	&"attack": JOY_BUTTON_X,
	&"jump": JOY_BUTTON_A,
	&"skill": JOY_BUTTON_Y,
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

static var _keycode_cache: Dictionary = {}



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




func load() -> void:
	for action in BINDABLE_ACTIONS:
		for gamepad in [false, true]:
			var bind_name := bind_key(action, gamepad)
			if !_store.has_key(SettingsStore.INPUT_SETTING_NAME, bind_name):
				continue
			var saved_event = _store.get_value(SettingsStore.INPUT_SETTING_NAME, bind_name, null)
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

	save()
	return BindResult.OK




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


static func bind_key(action: StringName, gamepad: bool) -> String:
	return "%s_%s" % [action, GAMEPAD_TAG if gamepad else KEYBOARD_TAG]


## 槽位下标 → 按键动作名（如 0 → skill_slot_1）。越界返回 &""。
static func slot_action(slot: int) -> StringName:
	if slot < 0 or slot >= SKILL_SLOT_ACTIONS.size():
		return &""
	return SKILL_SLOT_ACTIONS[slot]




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
		save()




func reset_binding(action: StringName, gamepad: bool) -> void:
	for existing_event in InputMap.action_get_events(action):
		if is_gamepad_event(existing_event) == gamepad:
			InputMap.action_erase_event(action, existing_event)
	var default_event := default_binding(action, gamepad)
	if default_event:
		InputMap.action_add_event(action, default_event)
	save()


func reset() -> void:
	for action in BINDABLE_ACTIONS:
		reset_binding(action, false)
		reset_binding(action, true)


func is_binding_default(action: StringName, gamepad: bool) -> bool:
	return events_equal(get_binding(action, gamepad), default_binding(action, gamepad))




func save() -> void:
	for action in BINDABLE_ACTIONS:
		for gamepad in [false, true]:
			var key_name := bind_key(action, gamepad)
			var event := get_binding(action, gamepad)
			if events_equal(event, default_binding(action, gamepad)):
				if _store.has_key(SettingsStore.INPUT_SETTING_NAME, key_name):
					_store.erase_key(SettingsStore.INPUT_SETTING_NAME, key_name)
			else:
				_store.set_value(SettingsStore.INPUT_SETTING_NAME, key_name, event)
	_request_save.call()
	binding_update.emit()




static func event_display_name(event: InputEvent) -> String:
	if event == null:
		return TranslationServer.translate(UNBOUND_TEXT)
	var key_event := event as InputEventKey
	if key_event != null:
		var key_code := key_of(key_event) as Key
		if KEY_DISPLAY_NAMES.has(key_code):
			return TranslationServer.translate(KEY_DISPLAY_NAMES[key_code] as String)
		var key_name := OS.get_keycode_string(key_code)
		if key_name != "":
			return key_name
		return TranslationServer.translate(UNBOUND_TEXT)
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
