extends CanvasLayer
class_name SkillBar

## 常驻技能条：底部居中 5 个槽位，游戏内始终存在。
## 层级比技能面板（100）高、比过场（128）低，所以技能面板打开时技能条仍浮在上方，
## 玩家可以直接把技能图标拖进来；暂停菜单打开时由 WorldTemplate 整体隐藏。


@onready var slots_container: HBoxContainer = $Slots

## 玩家引用（由 WorldTemplate._ready 注入）：槽位靠它读冷却剩余时间，为 null 时不画遮罩。
var player: PlayerInitial

var _slots: Array[SkillSlot] = []
var _drop_active := false
## 最近一次落点命中测试的时间戳（毫秒）：用于检测拖拽是否已结束（含松手取消）。
var _last_drag_tick := 0

## 技能面板是否打开：控制槽位右上角删除叉是否可见（避免游戏中误操作）。
var _panel_open := false


func _ready() -> void:
	for child in slots_container.get_children():
		if child is SkillSlot:
			var slot := child as SkillSlot
			slot.bar = self
			_slots.append(slot)


## 每帧刷新槽位冷却遮罩，之后处理拖动中的悬停高亮：
## 悬停高亮只在拖动时命中测试（拖出所有槽位立即熄灭，不依赖鼠标按键状态，
## 原生拖放期间鼠标事件是被吞掉的）。
## 高亮颜色由槽位是否可放决定：可放=绿（HL_OK）、不可放=红（HL_REJECT）。
func _process(_delta: float) -> void:
	for slot in _slots:
		slot.refresh_cooldown()
	if not _drop_active:
		return
	# 一段时间没有落点命中测试 => 拖拽已结束（含松手取消），熄灭避免残留高亮
	if Time.get_ticks_msec() - _last_drag_tick > 120:
		_drop_active = false
		for slot in _slots:
			slot.set_highlight(SkillSlot.HL_NONE)
		return
	var mouse := get_viewport().get_mouse_position()
	var over_any := false
	for slot in _slots:
		var hit := slot.get_global_rect().has_point(mouse)
		if hit:
			slot.set_highlight(SkillSlot.HL_OK if slot.is_drop_acceptable() else SkillSlot.HL_REJECT)
		else:
			slot.set_highlight(SkillSlot.HL_NONE)
		over_any = over_any or hit
	if not over_any:
		_drop_active = false


## 槽位收到合法拖动数据时回调：标记拖动进行中（无论可放与否都要给红/绿反馈）。
func on_slot_drag_active() -> void:
	_drop_active = true
	_last_drag_tick = Time.get_ticks_msec()


## 有一次成功落点后回调：熄灭全部高亮。
func on_slot_dropped() -> void:
	_drop_active = false
	for slot in _slots:
		slot.set_highlight(SkillSlot.HL_NONE)


## 由 WorldTemplate 在打开 / 关闭技能面板时调用：控制槽位删除叉是否可见。
func set_panel_open(open: bool) -> void:
	_panel_open = open
	for slot in _slots:
		slot.refresh_close_button()


func is_panel_open() -> bool:
	return _panel_open
