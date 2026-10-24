extends Node2D
class_name CharacterDebug


## 是否显示能量条（玩家为 true，普通敌人为 false）。关掉后能量条与能量文本一并隐藏。
@export var has_energy := false

## 血条满血时的填充色。
@export var health_color_full := Color(0.90, 0.15, 0.15)
## 血条濒死时的填充色：血量比例越低越接近该色，中间按比例插值。
@export var health_color_low := Color(0.95, 0.85, 0.15)
## 能量条的填充色（仅在 has_energy 为 true 时生效）。
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

	visible = Globals.debug_enabled
	Globals.debug_enabled_changed.connect(_on_debug_enabled_changed)

	_bind_state_machine()

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

func setup_health(max_value: int, current: int) -> void:
	health_bar.max_value = max_value
	set_health(current, max_value)

func set_health(current: int, max_value: int) -> void:
	health_bar.value = current
	_update_health_color(current, max_value)
	_refresh_health_label(current, max_value)

func setup_energy(max_value: int, current: int) -> void:
	if not has_energy:
		return
	energy_bar.max_value = max_value
	set_energy(current, max_value)

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
