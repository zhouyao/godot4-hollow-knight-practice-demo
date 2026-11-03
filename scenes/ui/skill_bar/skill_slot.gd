extends Control
class_name SkillSlot

## 技能条上的单个槽位：图标 + 右下角键位角标 + 冷却遮罩 + 拖动悬停高亮。
## 本节点是原生拖放的落点（_can_drop_data / _drop_data），
## 子节点一律 mouse_filter=IGNORE，保证命中落到这个根节点上。


const DRAG_KEY_SKILL_ID := &"skill_id"
## 拖动数据中携带的来源槽下标：面板来源记为 -1，槽内来源记为 slot_index。
const DRAG_KEY_SOURCE_SLOT := &"source_slot"

## 拖放悬停高亮状态：无 / 可放（绿）/ 不可放（红）。
const HL_NONE := 0
const HL_OK := 1
const HL_REJECT := 2

## 图标不可用态用的材质：能量不足时把 amount 拉到 1（变黑），够用时拉回 0（原色）。
const DISABLED_SHADER := preload("res://shaders/icon_disabled.gdshader")

## 倒计时数字的配色：剩余比例 1（刚起手）冷白 → 0（即将就绪）亮金，两者线性插值。
const CD_COLOR_COLD := Color(0.88, 0.93, 1.0)
const CD_COLOR_HOT := Color(1.0, 0.83, 0.45)
## 冷却刚归零那一下的闪光色。
const CD_FLASH_COLOR := Color(1.0, 0.97, 0.85)
## 最后一秒的呼吸：触发阈值（秒）、频率（次/秒）、最大放大比例。
const CD_PULSE_LEFT := 1.0
const CD_PULSE_HZ := 3.0
const CD_PULSE_SCALE := 0.16
## 就绪闪光：峰值放大倍率与总时长（秒）。
const CD_FLASH_SCALE := 1.4
const CD_FLASH_TIME := 0.22

## 本槽下标（0 起），与 InputBindings 的 skill_slot_N 一一对应。
@export var slot_index: int = 0

## 槽位尺寸（像素）。改这里即可调整单个技能格子大小，图标与冷却遮罩会按比例内缩。
@export var slot_size: Vector2 = Vector2(88, 88):
	set(value):
		slot_size = value
		if is_node_ready():
			_apply_size()
## 图标/冷却遮罩相对槽位四边的内缩比例（默认约 11.4%，即原来的 10/88）。
@export var inset_ratio: float = 10.0 / 88.0:
	set(value):
		inset_ratio = value
		if is_node_ready():
			_apply_size()

@onready var highlight: Panel = $Highlight
@onready var icon_rect: TextureRect = $Icon
@onready var key_label: Label = $KeyHint
@onready var cooldown_mask: CooldownMask = $CooldownMask
@onready var cooldown_label: Label = $CooldownLabel
@onready var close_button: SkillSlotCloseButton = $CloseButton

## 所属技能条（由 SkillBar._ready 注入）。
var bar: SkillBar

## 本槽当前是否可放置正在拖拽的技能（供 SkillBar 决定红/绿高亮）。
var _drop_acceptable := false
## 高亮 Panel 的独立 stylebox 副本：用于运行时切换边框颜色（绿=可放 / 红=不可放）。
var _highlight_style: StyleBoxFlat


## 按 slot_size 与 inset_ratio 同步槽位最小尺寸及图标/冷却遮罩的内缩边距。
## 内缩用比例换算（默认 10/88），这样改尺寸时图标不会被裁切错位。
## 注意：HBoxContainer 会把子节点高度拉伸到自身高度，而它默认被锚点钉死在 88px，
## 所以要同步把父容器高度改成 slot_size.y（底对齐、向上生长），高度才会真正变化。
func _apply_size() -> void:
	custom_minimum_size = slot_size
	var inset := slot_size.x * inset_ratio
	icon_rect.offset_left = inset
	icon_rect.offset_top = inset
	icon_rect.offset_right = -inset
	icon_rect.offset_bottom = -inset
	cooldown_mask.offset_left = inset
	cooldown_mask.offset_top = inset
	cooldown_mask.offset_right = -inset
	cooldown_mask.offset_bottom = -inset
	var parent := get_parent()
	if parent is BoxContainer:
		var box := parent as BoxContainer
		# 高度：底对齐、向上生长。
		box.offset_top = box.offset_bottom - slot_size.y
		# 宽度：跟随内容总宽（含各槽最小宽与间距），并保持对称偏移，
		# 这样容器始终水平居中（锚点在 0.5），改槽宽也不会偏左/偏右。
		var min_w := box.get_combined_minimum_size().x
		box.offset_left = -min_w * 0.5
		box.offset_right = min_w * 0.5

## 图标当前是否处于"能量不足"的不可用态（只在状态翻转时改材质参数）。
var _grayed := false

## 上一帧剩余的冷却秒数：用来识别"刚从冷却中恢复"，触发就绪闪光。
var _prev_cooldown_left: float = 0.0
## 上一帧渲染的倒计时文本键：0.1s 量化（int(left*10)）。仅在键变化时重算字符串，
## 把每帧的 String 分配从 ~60/s 降到 ~10/s，避免冷却期间的 GC 抖动。
var _cd_text_key: int = -1
## 上一帧写入的 CD 字体色：仅在随量化键变化时重写，避免每帧重建主题缓存。
var _cd_color: Color = Color(0.0, 0.0, 0.0, 0.0)
## 就绪闪光动画：放闪光期间不能被 refresh_cooldown 当作"已经归零"清掉。
var _flash_tween: Tween


func _ready() -> void:
	_apply_size()
	# 复制一份独立的高亮 stylebox，便于运行时切换边框颜色（绿=可放 / 红=不可放），
	# 否则改的是 tscn 里共享的子资源，会污染所有槽。
	_highlight_style = (highlight.get_theme_stylebox("panel") as StyleBoxFlat).duplicate()
	highlight.add_theme_stylebox_override("panel", _highlight_style)
	var disabled_material := ShaderMaterial.new()
	disabled_material.shader = DISABLED_SHADER
	# 必须显式落一次：_set_grayed 会因为"状态没变"短路掉首次调用，
	# 不写这行就一直吃 shader 默认值（哪怕是 0.0，靠默认值兜底也不够明确）。
	disabled_material.set_shader_parameter("amount", 0.0)
	icon_rect.material = disabled_material
	_set_grayed(false)
	_sync_cd_label_pivot()
	cooldown_label.resized.connect(_sync_cd_label_pivot)
	Settings.bindings.binding_update.connect(_refresh_key)
	Settings.skill_bar.slot_changed.connect(_on_slot_changed)
	_refresh_key()
	_refresh()


func _exit_tree() -> void:
	if Settings.bindings.binding_update.is_connected(_refresh_key):
		Settings.bindings.binding_update.disconnect(_refresh_key)
	if Settings.skill_bar.slot_changed.is_connected(_on_slot_changed):
		Settings.skill_bar.slot_changed.disconnect(_on_slot_changed)


## 右下角角标 = 该槽位当前绑定的按键（改动按键设置后实时刷新，未绑定显示"未绑定"）。
func _refresh_key() -> void:
	key_label.text = InputBindings.event_display_name(
		Settings.bindings.get_binding(InputBindings.slot_action(slot_index), false))


func set_highlight(state: int) -> void:
	if state == HL_NONE:
		highlight.visible = false
		return
	highlight.visible = true
	_highlight_style.border_color = (
		Color(0.30, 0.90, 0.45) if state == HL_OK else Color(0.95, 0.32, 0.32))


## 本槽当前是否可放置正在拖拽的技能（供 SkillBar 决定红/绿高亮）。
func is_drop_acceptable() -> bool:
	return _drop_acceptable


func get_skill_id() -> StringName:
	return Settings.skill_bar.get_skill(slot_index)


func _refresh() -> void:
	var def := Skills.by_id(get_skill_id())
	if def == null:
		icon_rect.texture = null
		icon_rect.tooltip_text = ""
		refresh_close_button()
		return
	icon_rect.texture = def.icon
	icon_rect.tooltip_text = tr(def.display_name)
	refresh_close_button()


func _on_slot_changed(slot: int) -> void:
	if slot != slot_index:
		return
	_refresh()
	# 换绑后该槽的冷却 / 能量态可能已变，交给技能条按需重刷（哪怕刚解绑也要清一次）。
	if bar != null:
		bar._mark_slot_active(self)


## 右上角删除叉可见性：仅本槽已绑定且技能面板打开时显示（避免游戏中误触）。
func refresh_close_button() -> void:
	if close_button == null:
		return
	var bound := get_skill_id() != &""
	close_button.visible = bound and (bar != null and bar.is_panel_open())


## 删除叉点击回调：解绑当前槽位。
func request_remove() -> void:
	Settings.skill_bar.set_skill(slot_index, &"")


## 每帧由 SkillBar 调用（仅当本槽处于冷却 / 闪光 / 待刷新时）：读玩家冷却表刷新扇形遮罩、
## 倒计时数字与配色，并按能量是否够用把图标变黑。拿不到玩家引用或空槽时恢复静息态。
## 返回 true 表示还需要继续刷新（仍在冷却 / 闪光中），false 表示已静止可移出刷新集合。
## 数字的强化层次：黑描边（始终）+ 冷白→亮金插值（全程）+ 最后一秒呼吸 + 归零闪光。
## 文本与字体色按 0.1s 量化：显示值不变时跳过字符串分配与主题缓存重建，冷却期间 GC 抖动最小。
func refresh_cooldown() -> bool:
	var player := bar.player if bar != null else null
	var skill_id := get_skill_id()
	if not is_instance_valid(player) or skill_id == &"":
		cooldown_mask.set_ratio(0.0)
		_set_grayed(false)
		_stop_flash()
		_prev_cooldown_left = 0.0
		_clear_cd_label()
		return false

	var left := player.skill_cooldown_left(skill_id)
	cooldown_mask.set_ratio(player.skill_cooldown_ratio(skill_id))
	# 冷却与能量是两回事：冷却期间也能看出"还剩多久"，能量不够 / 满血（cure）才是按不出去。
	_set_grayed(not player.can_use_skill(skill_id))

	if left > 0.0:
		_stop_flash()
		_prev_cooldown_left = left
		var ratio := player.skill_cooldown_ratio(skill_id)
		cooldown_label.visible = true
		# 量化到 0.1s：相邻帧显示值相同则跳过字符串分配与主题色重写（冷却数字本就是 1 位小数）。
		var key := int(left * 10.0 + 0.5)
		if key != _cd_text_key:
			_cd_text_key = key
			cooldown_label.text = "%.1f" % left
			var color := CD_COLOR_COLD.lerp(CD_COLOR_HOT, 1.0 - ratio)
			_cd_color = color
			cooldown_label.add_theme_color_override("font_color", color)
		cooldown_label.scale = Vector2.ONE * (1.0 + CD_PULSE_SCALE * _pulse_amount(left))
		return true

	if _prev_cooldown_left > 0.0:
		_prev_cooldown_left = 0.0
		_flash_ready()
		return true
	if _is_flashing():
		return true
	_clear_cd_label()
	return false


## 剩余不足 CD_PULSE_LEFT 秒时按正弦呼吸（0..1），用剩余时间当相位，天然跟着倒数走。
func _pulse_amount(left: float) -> float:
	if left > CD_PULSE_LEFT:
		return 0.0
	return 0.5 + 0.5 * sin(TAU * CD_PULSE_HZ * (CD_PULSE_LEFT - left))


## 冷却刚归零：把数字留在原地做一次短促的高亮弹跳，"可以用了"这一刻要有反馈。
func _flash_ready() -> void:
	_stop_flash()
	cooldown_label.text = "0.0"
	cooldown_label.visible = true
	cooldown_label.scale = Vector2.ONE
	cooldown_label.add_theme_color_override("font_color", CD_FLASH_COLOR)
	_cd_text_key = -1
	_flash_tween = create_tween()
	_flash_tween.tween_property(cooldown_label, "scale", Vector2.ONE * CD_FLASH_SCALE, CD_FLASH_TIME * 0.3)
	_flash_tween.tween_property(cooldown_label, "scale", Vector2.ONE, CD_FLASH_TIME * 0.7)
	_flash_tween.tween_callback(_clear_cd_label)


## Label 的缩放锚点在左上角，pivot 顶到中心才能原地呼吸而不偏移。
func _sync_cd_label_pivot() -> void:
	cooldown_label.pivot_offset = cooldown_label.size * 0.5


func _is_flashing() -> bool:
	return _flash_tween != null and _flash_tween.is_valid()


func _stop_flash() -> void:
	if _is_flashing():
		_flash_tween.kill()
	_flash_tween = null


func _clear_cd_label() -> void:
	cooldown_label.text = ""
	cooldown_label.visible = false
	cooldown_label.scale = Vector2.ONE
	_cd_text_key = -1


## 能量不足时图标变黑 + 失去原色，与冷却遮罩互不干扰。
func _set_grayed(grayed: bool) -> void:
	if _grayed == grayed:
		return
	_grayed = grayed
	icon_rect.material.set_shader_parameter("amount", 1.0 if grayed else 0.0)


func _can_drop_data(_position: Vector2, data: Variant) -> bool:
	var ok := false
	if data is Dictionary:
		var skill_id: StringName = (data as Dictionary).get(DRAG_KEY_SKILL_ID, &"")
		if skill_id != &"":
			var source: int = (data as Dictionary).get(DRAG_KEY_SOURCE_SLOT, -1)
			# 除来源槽外，技能栏里已存在该技能则拒绝，避免拖入两个相同技能
			ok = Settings.skill_bar.find_skill(skill_id, source) < 0
	# 记录本槽是否可放，供 SkillBar 决定红/绿高亮
	_drop_acceptable = ok
	# 只要拖着合法技能就激活高亮循环（可放=绿、不可放=红都要给反馈）
	if data is Dictionary and (data as Dictionary).get(DRAG_KEY_SKILL_ID, &"") != &"":
		if bar != null:
			bar.on_slot_drag_active()
	return ok


func _drop_data(_position: Vector2, data: Variant) -> void:
	var skill_id: StringName = (data as Dictionary).get(DRAG_KEY_SKILL_ID, &"")
	var source: int = (data as Dictionary).get(DRAG_KEY_SOURCE_SLOT, -1)
	var dest := slot_index
	var dest_skill := Settings.skill_bar.get_skill(dest)
	if source >= 0 and source != dest:
		# 技能栏内槽间拖动：执行"互换"而非"移动"——把来源技能放到目标槽，
		# 同时把目标槽原技能放回来源槽，避免覆盖目标处已有的技能导致丢失。
		Settings.skill_bar.set_skill(dest, skill_id)
		Settings.skill_bar.set_skill(source, dest_skill)
	else:
		# 来自技能面板（source == -1）或直接落到自身（source == dest）：直接覆盖目标槽。
		Settings.skill_bar.set_skill(dest, skill_id)
	if bar != null:
		bar.on_slot_dropped()


## 从已绑定槽位拖出：携带技能 id 与来源槽位下标，供删除按钮定位要解绑的槽。
## 仅技能面板打开时才允许（避免游戏中误操作）；空槽不可拖。
func _get_drag_data(_at_position: Vector2) -> Variant:
	if bar == null or not bar.is_panel_open():
		return null
	var skill_id := get_skill_id()
	if skill_id == &"":
		return null
	set_drag_preview(_make_drag_preview())
	return {DRAG_KEY_SKILL_ID: skill_id, DRAG_KEY_SOURCE_SLOT: slot_index}


func _make_drag_preview() -> Control:
	var preview := TextureRect.new()
	preview.texture = icon_rect.texture
	preview.custom_minimum_size = slot_size
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview.modulate = Color(1.0, 1.0, 1.0, 0.7)
	return preview
