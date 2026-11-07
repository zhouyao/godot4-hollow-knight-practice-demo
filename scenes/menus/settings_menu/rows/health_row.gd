extends MenuRow
class_name HealthRow


## true = 控制 Boss 血量，false = 控制小怪血量；两行只差这一项与显示名。
@export var is_boss: bool = false

const RESET_TOOLTIP := "重置默认值"

@onready var value_edit: LineEdit = $ValueEdit
@onready var reset_button: ResetButton = $Reset


func _ready() -> void:
	super._ready()
	# Tr.apply 用 meta 记源文本：先写死中文 key，切语言时不会把译文误当 key。
	name_label.set_meta(Tr.SOURCE_META, display_name)
	reset_button.set_meta(Tr.SOURCE_META_TOOLTIP, RESET_TOOLTIP)
	reset_button.tooltip_text = tr(RESET_TOOLTIP)
	value_edit.text_submitted.connect(_on_text_submitted)
	value_edit.focus_exited.connect(_on_focus_exited)
	reset_button.pressed.connect(_on_reset_pressed)
	_connect_changed()
	_sync()


func _exit_tree() -> void:
	_disconnect_changed()


func _connect_changed() -> void:
	if is_boss:
		Settings.development.boss_health_changed.connect(_on_health_changed)
	else:
		Settings.development.mob_health_changed.connect(_on_health_changed)


func _disconnect_changed() -> void:
	if is_boss:
		if Settings.development.boss_health_changed.is_connected(_on_health_changed):
			Settings.development.boss_health_changed.disconnect(_on_health_changed)
	elif Settings.development.mob_health_changed.is_connected(_on_health_changed):
		Settings.development.mob_health_changed.disconnect(_on_health_changed)


func _get_health() -> int:
	if is_boss:
		return Settings.development.get_boss_health()
	return Settings.development.get_mob_health()


func _set_health(value: int) -> void:
	if is_boss:
		Settings.development.set_boss_health(value)
	else:
		Settings.development.set_mob_health(value)


## 只在回车 / 失焦时提交，避免每敲一个字符就写一次配置；
## 留空或非法输入回落到有效值，越界值由 DevelopmentSection 夹取后回显。
func _on_text_submitted(_text: String) -> void:
	_commit()


func _on_focus_exited() -> void:
	_commit()


func _commit() -> void:
	var typed := value_edit.text.strip_edges()
	if typed.is_empty():
		_set_health(0)
	elif typed.is_valid_int():
		_set_health(typed.to_int())
	var value := _get_health()
	value_edit.text = str(value)
	reset_button.set_available(value != 0)


func _on_reset_pressed() -> void:
	_set_health(0)
	_sync()


func _on_health_changed(_value: int) -> void:
	_sync()


## 外部（信号 / 重置）触发的同步不抢输入焦点：正在编辑时只更新重置按钮。
func _sync() -> void:
	var value := _get_health()
	if not value_edit.has_focus() and value_edit.text != str(value):
		value_edit.text = str(value)
	reset_button.set_available(value != 0)
