## 行本身是 PanelContainer：内层 Row（HBoxContainer）负责内容排布，外层提供半透明黑底。
extends PanelContainer
class_name SkillRow

@onready var icon_rect: SkillIcon = $Row/IconContainer/Icon
@onready var preview_container: Control = $Row/PreviewContainer
@onready var preview: AnimatedSprite2D = $Row/PreviewContainer/Preview

## dash 预览时，精灵横向冲刺的终点 x。
const DASH_TRAVEL := 350.0

## 悬停提示里的冷却行：def.cooldown 带一位小数填入。
const COOLDOWN_HINT := &"冷却：%.1f 秒"
## 悬停提示里的消耗行：def.energy_cost 整数填入。
const ENERGY_COST_HINT := &"消耗能量：%d 点"

var _motion_tween: Tween


func setup(def: SkillDefinition) -> void:

	# 拖动时以 id 作为装配标识（存档与施放都认 id，不认显示名）
	icon_rect.skill_id = def.id

	if def.icon != null:
		icon_rect.texture = def.icon

	# 悬停提示 = 技能名 + 描述 + 冷却时长 + 能量消耗；空描述 / 0 值维度不显示。
	var tooltip_lines := PackedStringArray([tr(def.display_name)])
	if not def.description.is_empty():
		tooltip_lines.append(tr(def.description))
	if def.cooldown > 0.0:
		tooltip_lines.append(tr(COOLDOWN_HINT) % def.cooldown)
	if def.energy_cost > 0:
		tooltip_lines.append(tr(ENERGY_COST_HINT) % def.energy_cost)
	icon_rect.tooltip_text = "\n".join(tooltip_lines)

	if def.preview_frames != null:
		preview.sprite_frames = def.preview_frames
		var names := preview.sprite_frames.get_animation_names()
		if not names.is_empty():
			var anim := def.preview_animation
			if not names.has(anim):
				anim = names[0]
			preview.play(anim)
			if anim == &"dash":
				_play_dash_motion(anim)
			elif anim == &"block":
				preview.position.x = preview_container.size.x /2 -  150
			elif anim == &"cure":
				preview.scale = Vector2(0.5, 0.5)
				preview.position.y = -30
				preview.position.x = 70


## dash：精灵 x 从 0 快速冲到 DASH_TRAVEL，随动画循环反复冲刺。
func _play_dash_motion(anim: StringName) -> void:
	if _motion_tween != null and _motion_tween.is_valid():
		_motion_tween.kill()

	var frames := preview.sprite_frames
	var duration := frames.get_frame_count(anim) / maxf(frames.get_animation_speed(anim), 1.0)

	preview.position.x = 0.0
	_motion_tween = create_tween().set_loops()
	_motion_tween.tween_property(preview, "position:x", DASH_TRAVEL, duration).from(0.0)
