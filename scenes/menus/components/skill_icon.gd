extends TextureRect
class_name SkillIcon

## 技能面板里可拖动的技能图标。
## 按住拖到下方技能条的槽位上松手即完成装配；拖动的落点判定在 SkillSlot 一侧。


const PREVIEW_SIZE := 64.0
const PREVIEW_ALPHA := 0.7

## 本图标代表的技能 id，由 SkillRow.setup 填入。
var skill_id: StringName = &""


func _get_drag_data(_at_position: Vector2) -> Variant:
	if skill_id == &"":
		return null
	set_drag_preview(_make_preview())
	# 来自技能面板，无来源槽，记 -1
	return {SkillSlot.DRAG_KEY_SKILL_ID: skill_id, SkillSlot.DRAG_KEY_SOURCE_SLOT: -1}


func _make_preview() -> TextureRect:
	var preview := TextureRect.new()
	preview.texture = texture
	preview.custom_minimum_size = Vector2(PREVIEW_SIZE, PREVIEW_SIZE)
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview.modulate = Color(1.0, 1.0, 1.0, PREVIEW_ALPHA)
	return preview
