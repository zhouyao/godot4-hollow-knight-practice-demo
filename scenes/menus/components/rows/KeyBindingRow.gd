extends MenuRow
class_name KeyBindingRow

# 一条按键配置项：同一个动作分别提供键盘与手柄两个绑定槽，并各自提供恢复默认按钮。

signal listen_started(row: KeyBindingRow)
signal listen_stopped(row: KeyBindingRow)

const LISTENING_TEXT := "按下新按键…"

# 同一时刻只允许一行处于监听态。用 group 标记替代静态变量，脚本热重载后不会残留旧引用
const LISTENING_GROUP := &"key_binding_listening"

const HINT_SECONDS := 2.0

enum Slot { KEYBOARD, GAMEPAD, NONE = -1 }

@export var action_name: StringName = &""

@onready var keyboard_button: FocusButton = $KeyboardButton
@onready var gamepad_button: FocusButton = $GamepadButton
@onready var keyboard_reset: ResetButton = $KeyboardReset
@onready var gamepad_reset: ResetButton = $GamepadReset
@onready var hint_label: Label = $HintLabel

var _listening_slot: Slot = Slot.NONE
var _hint_timer: SceneTreeTimer = null


func _ready() -> void:
	super._ready()

	keyboard_reset.tooltip_text = tr("恢复默认按键")
	gamepad_reset.tooltip_text = tr("恢复默认按键")

	keyboard_button.pressed.connect(_on_bind_pressed.bind(Slot.KEYBOARD))
	gamepad_button.pressed.connect(_on_bind_pressed.bind(Slot.GAMEPAD))
	keyboard_reset.pressed.connect(_on_reset_pressed.bind(Slot.KEYBOARD))
	gamepad_reset.pressed.connect(_on_reset_pressed.bind(Slot.GAMEPAD))

	Settings.bindings.binding_update.connect(_refresh)
	# 切语言后按键名要跟着变（空格 <-> Space），Tr 只能翻回 meta 里的旧文案，这里再刷一次
	Settings.localization.locale_changed.connect(_on_locale_changed)
	# 同一时刻只有一行在监听输入，其余行不参与 _input 分发
	set_process_input(false)
	_refresh()


func _exit_tree() -> void:
	if Settings.bindings.binding_update.is_connected(_refresh):
		Settings.bindings.binding_update.disconnect(_refresh)
	if Settings.localization.locale_changed.is_connected(_on_locale_changed):
		Settings.localization.locale_changed.disconnect(_on_locale_changed)
	if is_in_group(LISTENING_GROUP):
		remove_from_group(LISTENING_GROUP)


func _on_locale_changed(_locale: String) -> void:
	_refresh()


static func stop_all_listening(tree: SceneTree) -> void:
	if tree == null:
		return
	for row in tree.get_nodes_in_group(LISTENING_GROUP):
		(row as KeyBindingRow).stop_listening()


func stop_listening() -> void:
	if is_in_group(LISTENING_GROUP):
		remove_from_group(LISTENING_GROUP)
	_listening_slot = Slot.NONE
	set_process_input(false)
	listen_stopped.emit(self)
	_refresh()


func _input(event: InputEvent) -> void:
	if _listening_slot == Slot.NONE or !event.is_pressed() or event.is_echo():
		return
	if !is_visible_in_tree():
		stop_listening()
		return

	# 取消键优先处理：Esc / 手柄 B（都是 ui_cancel）退出监听。
	# 手柄 B 也在 InputBindings.RESERVED_PAD_BUTTONS 里，绑不走，只能当作取消
	if event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		stop_listening()
		return

	var want_gamepad := _listening_slot == Slot.GAMEPAD
	if InputBindings.is_gamepad_event(event) != want_gamepad:
		return
	# 摇杆同样属于手柄事件，但当前只支持把手柄按键作为绑定
	if want_gamepad and !(event is InputEventJoypadButton):
		return

	get_viewport().set_input_as_handled()
	_try_bind(event)
	stop_listening()


func _try_bind(event: InputEvent) -> void:
	var conflicts := InputBindings.conflicting_actions(action_name, InputBindings.clean_event(event))
	var result := Settings.bindings.set_binding(action_name, event)
	match result:
		InputBindings.BindResult.RESERVED_KEY:
			_show_hint(tr("该按键已保留给菜单，无法绑定"))
		InputBindings.BindResult.UNSUPPORTED_EVENT:
			_show_hint(tr("不支持的输入源"))
		_:
			if conflicts.is_empty():
				return
			_show_hint(tr("已从 %s 收回该按键") % ", ".join(_conflict_names(conflicts)))


func _on_bind_pressed(slot: Slot) -> void:
	if _listening_slot == slot:
		stop_listening()
		return
	KeyBindingRow.stop_all_listening(get_tree())
	_listening_slot = slot
	add_to_group(LISTENING_GROUP)
	set_process_input(true)
	listen_started.emit(self)
	_refresh()


func _on_reset_pressed(slot: Slot) -> void:
	Settings.bindings.reset_binding(action_name, slot == Slot.GAMEPAD)


func _refresh() -> void:
	var listening_keyboard := _listening_slot == Slot.KEYBOARD
	var listening_gamepad := _listening_slot == Slot.GAMEPAD

	keyboard_button.text = tr(LISTENING_TEXT) if listening_keyboard \
		else InputBindings.event_display_name(Settings.bindings.get_binding(action_name, false))
	gamepad_button.text = tr(LISTENING_TEXT) if listening_gamepad \
		else InputBindings.event_display_name(Settings.bindings.get_binding(action_name, true))

	var idle := !listening_keyboard and !listening_gamepad
	keyboard_reset.set_available(idle and !Settings.bindings.is_binding_default(action_name, false))
	gamepad_reset.set_available(idle and !Settings.bindings.is_binding_default(action_name, true))


func _conflict_names(conflicts: Array[StringName]) -> PackedStringArray:
	var names := PackedStringArray()
	var parent := get_parent()
	for action in conflicts:
		names.append(_sibling_display_name(action, parent))
	return names


# 冲突提示直接用兄弟行已经翻译过的标题，省掉另一份 action -> 名称的映射表
func _sibling_display_name(action: StringName, parent: Node) -> String:
	if parent != null:
		for row in parent.get_children():
			if row is KeyBindingRow and row.action_name == action:
				return (row as KeyBindingRow).name_label.text
	return String(action)


func _show_hint(text: String) -> void:
	hint_label.text = text
	if _hint_timer != null:
		_hint_timer.time_left = HINT_SECONDS
		return
	_hint_timer = get_tree().create_timer(HINT_SECONDS)
	_hint_timer.timeout.connect(_clear_hint)


func _clear_hint() -> void:
	_hint_timer = null
	hint_label.text = ""
