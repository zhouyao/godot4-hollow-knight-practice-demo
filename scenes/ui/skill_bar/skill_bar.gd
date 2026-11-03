extends CanvasLayer
class_name SkillBar

## 常驻技能条：底部居中 5 个槽位，游戏内始终存在。
## 层级比技能面板（100）高、比过场（128）低，所以技能面板打开时技能条仍浮在上方，
## 玩家可以直接把技能图标拖进来；暂停菜单打开时由 WorldTemplate 整体隐藏。


@onready var slots_container: HBoxContainer = $Slots

## 玩家引用（由 WorldTemplate._ready 注入）：槽位靠它读冷却剩余时间，为 null 时不画遮罩。
## 用 setter 注入以便连接冷却 / 能量信号，仅在需要时驱动槽位刷新（空闲时零开销）。
var _player_ref: PlayerInitial
var player: PlayerInitial:
	get:
		return _player_ref
	set(value):
		if _player_ref != null:
			_disconnect_player(_player_ref)
		_player_ref = value
		if _player_ref != null:
			_connect_player(_player_ref)

## 需要逐帧刷新的槽位集合（冷却中 / 闪光中 / 待刷新）。空闲时为空，_process 直接跳过，
## 不再每帧无条件刷 5 个槽。
var _active: Dictionary = {}


func _connect_player(p: PlayerInitial) -> void:
	if not p.skill_cooldown_started.is_connected(_on_cooldown_started):
		p.skill_cooldown_started.connect(_on_cooldown_started)
	if not p.energy_changed.is_connected(_on_energy_changed):
		p.energy_changed.connect(_on_energy_changed)
	if not p.health_changed.is_connected(_on_health_changed):
		p.health_changed.connect(_on_health_changed)
	# 注入玩家后做一轮初始刷新：已绑定槽位的变黑态 / 遮罩立即正确（此前还没有轮询过）。
	for slot in _slots:
		if slot.get_skill_id() != &"":
			_active[slot] = true


func _disconnect_player(p: PlayerInitial) -> void:
	if p.skill_cooldown_started.is_connected(_on_cooldown_started):
		p.skill_cooldown_started.disconnect(_on_cooldown_started)
	if p.energy_changed.is_connected(_on_energy_changed):
		p.energy_changed.disconnect(_on_energy_changed)
	if p.health_changed.is_connected(_on_health_changed):
		p.health_changed.disconnect(_on_health_changed)


## 把某个槽加入刷新集合（由冷却开始、能量变化、槽位换绑等事件触发）。
func _mark_slot_active(slot: SkillSlot) -> void:
	_active[slot] = true


## 技能进入冷却：把绑定了该技能的槽位加入刷新集合，开始画遮罩 / 倒计时。
func _on_cooldown_started(skill_id: StringName) -> void:
	for slot in _slots:
		if slot.get_skill_id() == skill_id:
			_active[slot] = true


## 能量变化：所有已绑定槽位都要重算"能否付得起"的变黑态，下一帧统一刷新一次。
func _on_energy_changed(_energy: int) -> void:
	for slot in _slots:
		if slot.get_skill_id() != &"":
			_active[slot] = true


## 生命值变化：满血类技能（如 cure）要重算"还能不能用"的变灰态，下一帧统一刷新一次。
func _on_health_changed(_health: int) -> void:
	for slot in _slots:
		if slot.get_skill_id() != &"":
			_active[slot] = true

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
	# 只在有槽位处于冷却 / 闪光 / 待刷新状态时才做 UI 重算；空闲时直接跳过，
	# 避免每帧无条件刷 5 个槽。刷新返回 false（已静止）的槽位移出集合。
	if not _active.is_empty():
		for slot in _active.keys():
			if not slot.refresh_cooldown():
				_active.erase(slot)
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
