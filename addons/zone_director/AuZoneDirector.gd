extends Node

## 区域仲裁中心（autoload：AuZoneDirector）。
##
## 所有 AuZone 在检测到目标进出时通知本节点，由本节点维护"当前活跃区域集"
## 并对互斥通道做仲裁。消费方（玩家 / 敌人 / 环境特效）只查询本节点，不需要自己去连信号。
##
## 通道模型：
##   · 互斥通道（EXCLUSIVE_CHANNELS）—— 同一时刻只有一个胜者，如 surface（地面材质）、
##     lighting（光照）。嵌套时"最内层 / 优先级最高 / 面积最小"者胜。
##   · 叠加通道 —— 全部并存，如 ambient（rain / fog 可同时生效）、tags。
##
## 与 AuCameraDirector 同构：单点入口 + 可插拔行为（行为挂在 AuZone 上，见 AuZoneBehavior）。


## 生效区域集合变化时发出（进入 / 离开区域，或仲裁结果切换）。
signal active_set_changed
## 互斥通道的胜者变化时发出：channel、新胜者（可能为 null）、旧胜者（可能为 null）。
signal effective_changed(channel: StringName, zone: AuZone, old: AuZone)


## 互斥通道：同一时刻只有一个胜者。
const EXCLUSIVE_CHANNELS: Array[StringName] = [&"surface", &"lighting"]
## 全部通道：互斥通道 + 叠加通道（供遍历 / 调试用）。
const ALL_CHANNELS: Array[StringName] = [&"surface", &"ambient", &"lighting", &"tag"]


## 离开区域后的宽限时长（秒）：边界上反复横跳时避免表现闪烁。
## 期间若进入任何区域，待退出会被一并取消（交接不闪断）。
@export var exit_grace: float = 0.15


var _active: Array[AuZone] = []
var _winners: Dictionary = {}
var _pending_exit: Dictionary = {}
var _last_body: Node2D = null


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if _pending_exit.is_empty():
		return
	var dirty := false
	# keys() 返回拷贝，遍历中 erase 安全。
	for z in _pending_exit.keys():
		var left: float = float(_pending_exit[z]) - delta
		if left <= 0.0:
			_pending_exit.erase(z)
			_active.erase(z)
			dirty = true
		else:
			_pending_exit[z] = left
	if dirty:
		_commit()


# ---- 注册 / 通知 ----

## AuZone 出树时调用：立刻移出活跃集（不走宽限，节点都要没了）。
func unregister(zone: AuZone) -> void:
	if zone == null:
		return
	_pending_exit.erase(zone)
	if _active.has(zone):
		_active.erase(zone)
		_commit()


## AuZone 检测到目标进入：加入活跃集，并取消所有待退出。
func notify_entered(zone: AuZone, body: Node2D) -> void:
	if zone == null:
		return
	_last_body = body
	_pending_exit.clear()
	if not _active.has(zone):
		_active.append(zone)
	_commit()


## AuZone 检测到目标离开：进入宽限期，到点才真正移出。
func notify_exited(zone: AuZone) -> void:
	if zone == null or not _active.has(zone):
		return
	_pending_exit[zone] = exit_grace


# ---- 仲裁 ----

## 互斥通道当前的胜者；无人声明该通道时返回 null。
func top_of(channel: StringName) -> AuZone:
	var best: AuZone = null
	for z in _active:
		if not z.declares(channel):
			continue
		if best == null or _outranks(z, best):
			best = z
	return best


## 逐级比较，先分出胜负就停：depth 深者胜 → zone_priority 高者胜 → 面积小者胜 → 树序稳定。
func _outranks(a: AuZone, b: AuZone) -> bool:
	if a.depth != b.depth:
		return a.depth > b.depth
	if a.zone_priority != b.zone_priority:
		return a.zone_priority > b.zone_priority
	var ra := a.global_rect().get_area()
	var rb := b.global_rect().get_area()
	if ra != rb:
		return ra < rb
	return a.get_index() < b.get_index()


# ---- 查询 API（消费方主要用这几个）----

## 当前地面材质（互斥）。没有任何区域声明时返回 &"default"。
func surface() -> StringName:
	var z := top_of(&"surface")
	return z.surface if z != null else &"default"


## 当前光照（互斥）。没有任何区域声明时返回 &"default"。
func lighting() -> StringName:
	var z := top_of(&"lighting")
	return z.lighting if z != null else &"default"


## 是否处于某环境氛围中（叠加，可同时为多个）。
func has_ambient(name: StringName) -> bool:
	for z in _active:
		if z.ambient == name:
			return true
	return false


## 是否带有某标签（叠加）。
func has_tag(name: StringName) -> bool:
	for z in _active:
		if z.tags.has(name):
			return true
	return false


## 当前活跃区域（已按仲裁顺序排序：越靠前越优先）。
func active_zones() -> Array[AuZone]:
	var out := _active.duplicate()
	out.sort_custom(_outranks)
	return out


## 最近一次进入区域的 body（脚步音之类需要它读速度 / 是否着地）。
func last_body() -> Node2D:
	if _last_body != null and not is_instance_valid(_last_body):
		_last_body = null
	return _last_body


## 清空全部状态（切关卡时用；正常路径由各 AuZone 的 unregister 自行摘除）。
func reset() -> void:
	_active.clear()
	_pending_exit.clear()
	_winners.clear()
	_last_body = null


# ---- 内部 ----

func _commit() -> void:
	_prune_invalid()
	var changed := false
	for channel in EXCLUSIVE_CHANNELS:
		var top := top_of(channel)
		var old: AuZone = _winners.get(channel)
		if top == old:
			continue
		changed = true
		_winners[channel] = top
		if old != null and is_instance_valid(old):
			old._notify_channel_lost(channel)
		if top != null:
			top._notify_channel_gained(channel)
		effective_changed.emit(channel, top, old)
	if changed:
		active_set_changed.emit()


func _prune_invalid() -> void:
	for i in range(_active.size() - 1, -1, -1):
		if not is_instance_valid(_active[i]):
			_active.remove_at(i)
