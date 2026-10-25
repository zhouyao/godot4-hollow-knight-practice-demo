class_name SkillBarSection
extends SettingsSection


## 槽位内容变化后发出（拖放装配、清空都会触发）。
## 参数 slot：0 起的槽位下标。技能条与玩家施放都连这个信号。
signal slot_changed(slot: int)

## 技能条槽位数量：技能条 UI、按键绑定、玩家施放三处共用这一个常量。
const SLOT_COUNT := 5
const SLOT_KEYS: Array[String] = ["slot_1", "slot_2", "slot_3", "slot_4", "slot_5"]

var _slots: Array[StringName] = []


func _init(store: SettingsStore, request_save: Callable) -> void:
	super._init(store, request_save)
	_slots.resize(SLOT_COUNT)


func load() -> void:
	_slots.resize(SLOT_COUNT)
	for i in SLOT_COUNT:
		var stored: Variant = _store.get_value(SettingsStore.SKILL_BAR_SETTING_NAME, SLOT_KEYS[i], "")
		_slots[i] = StringName(stored) if stored is String else &""


## 取出槽位里的技能 id；空槽返回 &""。
func get_skill(slot: int) -> StringName:
	if slot < 0 or slot >= _slots.size():
		return &""
	return _slots[slot]


## 查找 skill_id 已绑定的槽位下标；找不到返回 -1。
## except_slot 用于在"槽间移动"时排除自身来源，避免误判为重复。
func find_skill(skill_id: StringName, except_slot: int = -1) -> int:
	for i in SLOT_COUNT:
		if i != except_slot and _slots[i] == skill_id:
			return i
	return -1


## 装配 / 清空槽位（传 &"" 清空）。内容没变则直接返回。
func set_skill(slot: int, skill_id: StringName) -> void:
	if slot < 0 or slot >= SLOT_COUNT or _slots[slot] == skill_id:
		return
	_slots[slot] = skill_id
	_persist(slot)
	save()
	slot_changed.emit(slot)


## 空槽不写进配置文件（与 InputBindings 保持一致：默认值不落盘）。
func _persist(slot: int) -> void:
	var key := SLOT_KEYS[slot]
	var section := SettingsStore.SKILL_BAR_SETTING_NAME
	if _slots[slot] == &"":
		if _store.has_key(section, key):
			_store.erase_key(section, key)
		return
	_store.set_value(section, key, String(_slots[slot]))
