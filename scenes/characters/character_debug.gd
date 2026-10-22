extends Node2D
class_name CharacterDebug

## 角色调试浮层组件：统一怪物与玩家的 Debug 显示（状态名 + 血条 + 能量条）。
## 作为子节点挂在角色下并命名为 "Debug"，即可沿用原 $Debug/* 路径。
## 状态名由组件自己订阅宿主状态机的 state_changed 信号写入，与 StateMachine 彻底解耦。

@export var has_energy := false

@export var health_color_full := Color(0.90, 0.15, 0.15)
@export var health_color_low := Color(0.95, 0.85, 0.15)
@export var energy_color := Color(0.20, 0.70, 1.0)

@onready var state_label: Label = $MarginContainer/StateName
@onready var health_bar: ProgressBar = $HealthBar
@onready var health_label: Label = $HealthLabel
@onready var energy_bar: ProgressBar = $EnergyBar
@onready var energy_label: Label = $EnergyLabel

var _health_fill: StyleBoxFlat
var _energy_fill: StyleBoxFlat


func _ready() -> void:
	energy_bar.visible = has_energy
	energy_label.visible = has_energy

	_health_fill = StyleBoxFlat.new()
	health_bar.add_theme_stylebox_override("fill", _health_fill)

	if has_energy:
		_energy_fill = StyleBoxFlat.new()
		_energy_fill.bg_color = energy_color
		energy_bar.add_theme_stylebox_override("fill", _energy_fill)

	# 全局调试开关：套用当前状态并订阅变化（运行时改 Globals.debug_enabled 即时生效）
	visible = Globals.debug_enabled
	Globals.debug_enabled_changed.connect(_on_debug_enabled_changed)

	# 自行发现并订阅状态机：彻底与 StateMachine 解耦
	_bind_state_machine()


## 在宿主（角色根节点）的兄弟中找 StateMachine 并订阅其 state_changed
func _bind_state_machine() -> void:
	var host := get_parent()
	if host == null:
		return
	for child in host.get_children():
		if child is StateMachine:
			child.state_changed.connect(_on_state_changed)
			break


func _on_state_changed(new_state: StringName, _old_state: StringName) -> void:
	state_label.text = new_state


## 初始化血条（最大值 + 当前值 + 颜色 + 文字）
func setup_health(max_value: int, current: int) -> void:
	health_bar.max_value = max_value
	set_health(current, max_value)


## 刷新血量显示（数值 + 颜色 + 文字）
func set_health(current: int, max_value: int) -> void:
	health_bar.value = current
	_update_health_color(current, max_value)
	_refresh_health_label(current, max_value)


## 初始化能量条（仅 has_energy 时生效）
func setup_energy(max_value: int, current: int) -> void:
	if not has_energy:
		return
	energy_bar.max_value = max_value
	set_energy(current, max_value)


## 刷新能量显示（数值 + 文字）
func set_energy(current: int, max_value: int) -> void:
	if not has_energy:
		return
	energy_bar.value = current
	_refresh_energy_label(current, max_value)


func _update_health_color(current: int, max_value: int) -> void:
	var ratio := clampf(float(current) / float(max_value), 0.0, 1.0)
	_health_fill.bg_color = health_color_low.lerp(health_color_full, ratio)


func _refresh_health_label(current: int, max_value: int) -> void:
	health_label.text = "%d/%d" % [maxi(current, 0), max_value]


func _refresh_energy_label(current: int, max_value: int) -> void:
	energy_label.text = "%d/%d" % [current, max_value]


func _on_debug_enabled_changed(enabled: bool) -> void:
	visible = enabled
