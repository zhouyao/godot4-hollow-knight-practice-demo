extends FocusButton
class_name FocusMenuButton

## 复刻 HollowKnight 菜单按钮：文字左右各一枚花纹指针，获得焦点时浮出、失焦时收起。
## 焦点/音效沿用项目已有的 FocusButton（UiAudio），只补指针表现，不改共享组件。
## 指针横向位置按文字实际宽度算：HK 原版指针贴按钮边缘，换成中文短标签会离文字过远。

const ICON_GAP := 30.0        # 指针内侧到文字边缘的间隙（HK 原版实测约 30~35）
const ANIM_SHOW := &"pointer up"
const ANIM_HIDE := &"pointer down"

@onready var _icon_left: AnimatedSprite2D = $FocusIconLeft
@onready var _icon_right: AnimatedSprite2D = $FocusIconRight

var _icons_wanted := false


func _ready() -> void:
	_icon_left.visible = false
	_icon_right.visible = false
	_icon_left.animation_finished.connect(_on_icon_animation_finished)
	_icon_right.animation_finished.connect(_on_icon_animation_finished)
	item_rect_changed.connect(_layout_icons)


func focus(play_sound := true) -> void:
	super(play_sound)
	_show_icons(true)


func quiet_focus(play_sound := false) -> void:
	super(play_sound)
	_show_icons(true)


func _on_focus_exited() -> void:
	super._on_focus_exited()
	_show_icons(false)


func _show_icons(on: bool) -> void:
	_icons_wanted = on
	if on:
		_layout_icons()
	for pointer: AnimatedSprite2D in [_icon_left, _icon_right]:
		if on:
			pointer.visible = true
			pointer.play(ANIM_SHOW)
		elif pointer.visible:
			pointer.play(ANIM_HIDE)


func _on_icon_animation_finished() -> void:
	# 收起动画播完才隐藏；若期间又重新获得焦点则不隐藏
	if _icons_wanted:
		return
	_icon_left.visible = false
	_icon_right.visible = false


## 文案变化后（切语言）重算指针位置，否则指针还按旧文本宽度贴着
func refresh_pointer_layout() -> void:
	_layout_icons()


func _layout_icons() -> void:
	var font := get_theme_font(&"font")
	var font_size := get_theme_font_size(&"font_size")
	var text_width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var center := size * 0.5
	var reach := text_width * 0.5 + ICON_GAP
	var left_half := _icon_half_width(_icon_left)
	var right_half := _icon_half_width(_icon_right)
	# clamp 到按钮内：英文长标签时指针贴边（同 HK），中文短标签时紧贴文字
	_icon_left.position = Vector2(
		clampf(center.x - reach - left_half, left_half, center.x), center.y
	)
	_icon_right.position = Vector2(
		clampf(center.x + reach + right_half, center.x, size.x - right_half), center.y
	)


func _icon_half_width(pointer: AnimatedSprite2D) -> float:
	var frames := pointer.sprite_frames
	if frames == null:
		return 0.0
	var anim_names := frames.get_animation_names()
	if anim_names.is_empty():
		return 0.0
	var tex := frames.get_frame_texture(anim_names[0], 0)
	if tex == null:
		return 0.0
	return tex.get_size().x * pointer.scale.x * 0.5
