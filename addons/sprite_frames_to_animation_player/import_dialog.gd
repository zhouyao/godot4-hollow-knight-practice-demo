## 从场景里的 AnimatedSprite2D 选动画，导入到某个 AnimationPlayer。
## 目标不写死：右键进来的那个只是默认值，对话框里可以切到场景里任意 AnimationPlayer；
## 批量模式下还能给每个精灵各指定一个目标。
@tool
extends ConfirmationDialog

var _plugin
var _player: AnimationPlayer
var _sprites: Array[AnimatedSprite2D] = []
var _players: Array[AnimationPlayer] = []

var _target_option: OptionButton
var _sprite_option: OptionButton
var _library_tree: Tree
var _anim_box: VBoxContainer
var _anim_checks: Dictionary = {}
var _anim_total := 0

## Tree 的 get_combined_minimum_size() 跟行数无关（实测恒为 16x17），
## 只靠它表格会塌成几十像素、所有库都缩在里面得拖。量不到行高时的兜底值。
const FALLBACK_ROW_HEIGHT := 24.0
var _batch_targets_box: VBoxContainer
var _batch_targets: Array[OptionButton] = []
var _overwrite: CheckBox
var _stop_playback: CheckBox
var _batch_all: CheckBox
var _library_detail: Label
var _hint: Label
var _select_all: Button
var _select_none: Button

## 静态文案的 key 存在节点 meta 上，切语言时照 key 重新查表
const I18N_META := &"i18n_key"


func setup(player: AnimationPlayer, sprites: Array[AnimatedSprite2D], plugin) -> void:
	_player = player
	_sprites = sprites
	_plugin = plugin
	_players = NodeFinder.typed_players(NodeFinder.collect(_scene_root(), AnimationPlayer))
	if _anim_box == null:
		_build_ui()
	_refresh()


## 弹出来之后再量一次行高：没弹出来之前表格没排版，量不到真实行高
func fit_library_table() -> void:
	_fit_library_table()


## 编辑器语言切了：静态文案按 key 重查，动态文案交给 _refresh() 重算
func retranslate() -> void:
	if _anim_box == null:  # 还没建 UI（对话框没打开过）
		return
	title = SpriteFramesI18n.t("dialog.title")
	get_ok_button().text = SpriteFramesI18n.t("dialog.ok")
	get_cancel_button().text = SpriteFramesI18n.t("dialog.cancel")
	_batch_all.text = SpriteFramesI18n.t("check.batch_all")
	_select_all.text = SpriteFramesI18n.t("button.select_all")
	_select_none.text = SpriteFramesI18n.t("button.select_none")
	_overwrite.text = SpriteFramesI18n.t("check.overwrite")
	_stop_playback.text = SpriteFramesI18n.t("check.stop_playback")
	_stop_playback.tooltip_text = SpriteFramesI18n.t("tip.stop_playback")
	_library_tree.set_column_title(0, SpriteFramesI18n.t("col.pick"))
	_library_tree.set_column_title(1, SpriteFramesI18n.t("col.library"))
	_library_tree.set_column_title(2, SpriteFramesI18n.t("col.count"))
	_library_tree.set_column_title(3, SpriteFramesI18n.t("col.content"))
	_apply_meta_texts(self)
	_refresh()


func _refresh() -> void:
	_refresh_players()
	_refresh_sprites()
	_refresh_batch_targets()
	_refresh_libraries()
	_refresh_animations()


# --- UI ---

func _build_ui() -> void:
	title = SpriteFramesI18n.t("dialog.title")
	min_size = Vector2i(460, 0)
	get_ok_button().text = SpriteFramesI18n.t("dialog.ok")
	get_cancel_button().text = SpriteFramesI18n.t("dialog.cancel")

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	add_child(vbox)

	_target_option = OptionButton.new()
	_target_option.item_selected.connect(func(_i: int) -> void:
		_player = _selected_player()
		_refresh_batch_targets()
		_refresh_libraries()
		_update_anim_hint())
	_form_row(vbox, "row.target_player", _target_option)

	_sprite_option = OptionButton.new()
	_sprite_option.item_selected.connect(func(_i: int) -> void:
		_refresh_animations())
	_form_row(vbox, "row.source_sprite", _sprite_option)

	_batch_all = CheckBox.new()
	_batch_all.text = SpriteFramesI18n.t("check.batch_all")
	_batch_all.toggled.connect(func(on: bool) -> void:
		_sprite_option.disabled = on
		_refresh_batch_targets()
		_refresh_animations())
	vbox.add_child(_batch_all)

	_batch_targets_box = VBoxContainer.new()
	_batch_targets_box.add_theme_constant_override("separation", 2)
	vbox.add_child(_batch_targets_box)

	_anim_box = VBoxContainer.new()
	_anim_box.add_theme_constant_override("separation", 2)
	vbox.add_child(_label("label.animations"))
	vbox.add_child(_anim_box)

	var anim_buttons := HBoxContainer.new()
	_select_all = Button.new()
	_select_all.text = SpriteFramesI18n.t("button.select_all")
	_select_all.pressed.connect(func() -> void:
		_set_all_checks(true))
	_select_none = Button.new()
	_select_none.text = SpriteFramesI18n.t("button.select_none")
	_select_none.pressed.connect(func() -> void:
		_set_all_checks(false))
	anim_buttons.add_child(_select_all)
	anim_buttons.add_child(_select_none)
	vbox.add_child(anim_buttons)

	vbox.add_child(_label("label.library"))
	_build_library_table(vbox)

	_library_detail = Label.new()
	_library_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_library_detail.add_theme_color_override("font_color", Color(0.62, 0.68, 0.78))
	vbox.add_child(_library_detail)

	_overwrite = CheckBox.new()
	_overwrite.text = SpriteFramesI18n.t("check.overwrite")
	_overwrite.button_pressed = true
	_overwrite.toggled.connect(func(_on: bool) -> void:
		_update_library_detail())
	vbox.add_child(_overwrite)

	_stop_playback = CheckBox.new()
	_stop_playback.text = SpriteFramesI18n.t("check.stop_playback")
	_stop_playback.tooltip_text = SpriteFramesI18n.t("tip.stop_playback")
	_stop_playback.button_pressed = true
	vbox.add_child(_stop_playback)

	_hint = Label.new()
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_hint)

	confirmed.connect(_on_confirmed)


## text 传的是 i18n 的 key，不是最终文案
func _form_row(parent: Control, key: String, control: Control) -> void:
	parent.add_child(_label(key))
	parent.add_child(control)


## 目标动画库用表格显示，最前面一列是单选框（4.7 的 TreeItem 没有 CELL_MODE_RADIO，
## 用 CELL_MODE_CHECK + 手动互斥实现）。高度自适应，内容列不裁剪可横向滚动。
func _build_library_table(parent: Control) -> void:
	_library_tree = Tree.new()
	_library_tree.columns = 4
	_library_tree.hide_root = true
	_library_tree.select_mode = Tree.SELECT_SINGLE
	_library_tree.column_titles_visible = true
	_library_tree.set_column_title(0, SpriteFramesI18n.t("col.pick"))
	_library_tree.set_column_title(1, SpriteFramesI18n.t("col.library"))
	_library_tree.set_column_title(2, SpriteFramesI18n.t("col.count"))
	_library_tree.set_column_title(3, SpriteFramesI18n.t("col.content"))
	_library_tree.set_column_expand(0, false)
	_library_tree.set_column_custom_minimum_width(0, 48)
	_library_tree.set_column_expand(1, false)
	_library_tree.set_column_custom_minimum_width(1, 110)
	_library_tree.set_column_expand(2, false)
	_library_tree.set_column_custom_minimum_width(2, 48)
	_library_tree.set_column_expand(3, true)
	_library_tree.set_column_clip_content(3, false)
	_library_tree.item_edited.connect(_on_library_edited)
	_library_tree.cell_selected.connect(func() -> void:
		_on_library_edited())
	_library_tree.item_selected.connect(func() -> void:
		_update_library_detail())
	parent.add_child(_library_tree)


## 静态文案统一从这里出：key 存进 meta，切语言时按 key 重查
func _label(key: String) -> Label:
	var l := Label.new()
	l.set_meta(I18N_META, key)
	l.text = SpriteFramesI18n.t(key)
	return l


## 把树里所有带 i18n meta 的 Label 重新翻译一遍
func _apply_meta_texts(node: Node) -> void:
	for child in node.get_children():
		var key := String(child.get_meta(I18N_META, ""))
		if key != "" and child is Label:
			(child as Label).text = SpriteFramesI18n.t(key)
		_apply_meta_texts(child)


# --- 数据 ---

func _refresh_players() -> void:
	# 右键进来的那个可能不在收集范围里（比如来自另一个场景），一定得保进候选列表，
	# 否则目标下拉和动画库下拉会一起变空
	if _player != null and not _players.has(_player):
		_players.append(_player)
	_target_option.clear()
	for i in _players.size():
		_target_option.add_item(_path_of(_players[i]))
		_target_option.set_item_metadata(i, _players[i])
	var idx := 0
	if _player != null:
		var found := _players.find(_player)
		if found >= 0:
			idx = found
	if not _players.is_empty():
		_target_option.select(idx)
		_player = _players[idx]


func _refresh_sprites() -> void:
	_sprite_option.clear()
	for i in _sprites.size():
		_sprite_option.add_item(_path_of(_sprites[i]))
		_sprite_option.set_item_metadata(i, _sprites[i])
	if _sprites.is_empty():
		_sprite_option.add_item(SpriteFramesI18n.t("option.no_sprite"))
		_sprite_option.disabled = true
		_batch_all.disabled = true
	else:
		_sprite_option.select(0)
	_batch_all.visible = _sprites.size() > 1


## 批量模式下给每个精灵一行「目标」下拉，默认都是当前选的目标
func _refresh_batch_targets() -> void:
	for child in _batch_targets_box.get_children():
		child.queue_free()
	_batch_targets.clear()
	_batch_targets_box.visible = _batch_all.button_pressed and not _sprites.is_empty()
	if not _batch_targets_box.visible:
		return
	for sprite in _sprites:
		var row := HBoxContainer.new()
		var label := Label.new()
		label.text = sprite.name
		label.custom_minimum_size = Vector2(120.0, 0.0)
		var option := OptionButton.new()
		option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		for i in _players.size():
			option.add_item(_players[i].name)
			option.set_item_metadata(i, _players[i])
		var idx := _players.find(_player) if _player != null else -1
		if idx < 0:
			idx = 0
		if not _players.is_empty():
			option.select(idx)
		row.add_child(label)
		row.add_child(option)
		_batch_targets_box.add_child(row)
		_batch_targets.append(option)


## 表格至少要有行可点：目标没解析出来、或目标压根没建库时，给一行 <global>（导入时新建）
func _refresh_libraries() -> void:
	var keep: Variant = _selected_library()
	_library_tree.clear()
	var tree_root := _library_tree.create_item()
	var player := _selected_player()
	if player == null:
		print(SpriteFramesI18n.log_text("log.lib_fallback"))

	var rows: Array[Dictionary] = []
	if player != null:
		for raw in player.get_animation_library_list():
			var lib_name := StringName(raw)
			var lib := player.get_animation_library(lib_name)
			rows.append({
				"name": lib_name,
				"names": lib.get_animation_list() if lib != null else [],
				"exists": player.has_animation_library(lib_name),
			})
	if rows.is_empty():
		rows.append({"name": &"", "names": [], "exists": false})

	var pick := 0
	for i in rows.size():
		var row := rows[i]
		var item := _library_tree.create_item(tree_root)
		var lib_name: StringName = row["name"] as StringName
		var names := row["names"] as Array
		item.set_cell_mode(0, TreeItem.CELL_MODE_CHECK)
		item.set_checked(0, false)
		item.set_editable(0, true)
		item.set_text(1, SpriteFramesI18n.t("lib.global") if String(lib_name) == "" else String(lib_name))
		item.set_text(2, str(names.size()))
		item.set_text(3, _library_content_text(names, not (row["exists"] as bool)))
		item.set_metadata(0, lib_name)
		if keep != null and lib_name == keep:
			pick = i
	# TreeItem 只有 get_child(idx)，没有 get_child_by_index
	var target: TreeItem = tree_root.get_child(pick)
	if target == null:
		target = tree_root.get_first_child()
	if target != null:
		target.select(0)
		_exclusive_check(target)
	_update_library_detail()
	# 表格要按行数撑开，但刚建好时还没排版、量不到行高，所以延后再量一次
	_fit_library_table.call_deferred()


## 按实际行高 × 行数撑开表格，让所有动画库都能直接看到，不用拖滚动条。
## 没排版好时量不到行高（rect.size.y ≈ 0），这时用兜底值，等下一帧再量。
func _fit_library_table() -> void:
	if _library_tree == null or not _library_tree.is_inside_tree():
		return
	var tree_root := _library_tree.get_root()
	if tree_root == null:
		return
	var first := tree_root.get_first_child()
	if first == null:
		return
	var rows := tree_root.get_child_count()
	var rect := _library_tree.get_item_area_rect(first, 0)
	var row_height := rect.size.y
	var top := rect.position.y
	if row_height <= 1.0:
		row_height = FALLBACK_ROW_HEIGHT
		top = FALLBACK_ROW_HEIGHT
	_library_tree.custom_minimum_size = Vector2(0.0, top + rows * row_height + 8.0)


## 单选：把这一行勾上，其余全部取消
func _exclusive_check(keep: TreeItem) -> void:
	var tree_root := _library_tree.get_root()
	if tree_root == null or keep == null:
		return
	for i in tree_root.get_child_count():
		var child := tree_root.get_child(i)
		if child == null:
			continue
		child.set_checked(0, child == keep)


## 勾了单选框、或点了行里任意一格，都当选中这一行
func _on_library_edited() -> void:
	var keep := _library_tree.get_selected()
	if keep != null and keep.is_checked(0):
		_exclusive_check(keep)
		_update_library_detail()
		_update_anim_hint()
		return
	# 兜底：找到刚被勾上的那一行
	var tree_root := _library_tree.get_root()
	if tree_root == null:
		return
	var checked: Array[TreeItem] = []
	for i in tree_root.get_child_count():
		var child := tree_root.get_child(i)
		if child != null and child.is_checked(0):
			checked.append(child)
	if not checked.is_empty():
		_exclusive_check(checked[checked.size() - 1])
		_update_library_detail()
		_update_anim_hint()


func _target_player_name() -> String:
	var player := _selected_player()
	return player.name if player != null else SpriteFramesI18n.t("value.unspecified")


## 目标库在提示里的显示名，跟着表格单选走
func _target_library_label() -> String:
	var lib_name: Variant = _selected_library()
	if lib_name == null:
		return SpriteFramesI18n.t("value.no_library")
	return SpriteFramesI18n.t("lib.global") if String(lib_name) == "" else String(lib_name)


func _checked_library_item() -> TreeItem:
	var tree_root := _library_tree.get_root()
	if tree_root == null:
		return null
	for i in tree_root.get_child_count():
		var child := tree_root.get_child(i)
		if child != null and child.is_checked(0):
			return child
	return null


func _library_content_text(names: Array, virtual_row: bool) -> String:
	if names.is_empty():
		return SpriteFramesI18n.t("content.empty_new" if virtual_row else "content.empty")
	var list: Array[String] = []
	for raw in names:
		list.append(String(raw))
	return "，".join(list)


## 目标库里现在有什么、哪些会被覆盖，写清楚
func _update_library_detail() -> void:
	if _library_detail == null:
		return
	var player := _selected_player()
	var lib_name: Variant = _selected_library()
	if player == null or lib_name == null:
		_library_detail.text = ""
		return
	if not player.has_animation_library(lib_name):
		_library_detail.text = SpriteFramesI18n.t("detail.lib_missing")
		return
	var lib := player.get_animation_library(lib_name)
	var existing := lib.get_animation_list() if lib != null else []
	if existing.is_empty():
		_library_detail.text = SpriteFramesI18n.t("detail.lib_empty")
		return
	var picked := _selected_animations()
	# get_animation_list() 返回 PackedStringArray，拿 StringName 去 has() 会比对不上
	var existing_strings: Array[String] = []
	for raw in existing:
		existing_strings.append(String(raw))
	var will_overwrite: Array[String] = []
	for name in picked:
		if existing_strings.has(String(name)):
			will_overwrite.append(String(name))
	var text := SpriteFramesI18n.t("detail.existing", ["，".join(existing)])
	if not will_overwrite.is_empty():
		text += "\n" + SpriteFramesI18n.t("detail.checked_exists", [
			"，".join(will_overwrite),
			SpriteFramesI18n.t("detail.will_overwrite" if _overwrite.button_pressed else "detail.will_skip"),
		])
	_library_detail.text = text


## 勾选列表跟随选中的精灵；批量模式下取所有精灵动画的并集
func _refresh_animations() -> void:
	for child in _anim_box.get_children():
		child.queue_free()
	_anim_checks.clear()

	var sources := _target_sprites()
	var names: Array[StringName] = []
	for sprite in sources:
		if sprite.sprite_frames == null:
			continue
		for raw in sprite.sprite_frames.get_animation_names():
			var n := StringName(raw)
			# SpriteFrames 自带一条 0 帧的 default，别列出来干扰选择
			if names.has(n) or _max_frames(n, sources) <= 0:
				continue
			names.append(n)

	for anim_name in names:
		var row := CheckBox.new()
		row.text = "%s   %s" % [anim_name, _describe(anim_name, sources)]
		row.button_pressed = true
		row.toggled.connect(func(_on: bool) -> void:
			_update_anim_hint()
			_update_library_detail())
		_anim_checks[anim_name] = row
		_anim_box.add_child(row)

	_update_anim_hint(names)
	_update_library_detail()


## 勾选状态一变就重算，别停在刷新那一刻的数字上。
## 分母用 _anim_total（刷新时记录的候选总数），否则取消勾选时分母会跟着变小。
func _update_anim_hint(available: Array = []) -> void:
	if _hint == null:
		return
	var picked := _selected_animations().size()
	if not available.is_empty():
		_anim_total = available.size()
	if _anim_total == 0:
		_hint.text = SpriteFramesI18n.t("hint.no_animation")
		return
	if picked == 0:
		_hint.text = SpriteFramesI18n.t("hint.none_picked", [_anim_total])
	else:
		_hint.text = SpriteFramesI18n.t("hint.picked", [
			picked, _anim_total, _target_player_name(), _target_library_label()])


static func _max_frames(anim_name: StringName, sources: Array[AnimatedSprite2D]) -> int:
	var best := 0
	for sprite in sources:
		if sprite.sprite_frames == null or not sprite.sprite_frames.has_animation(anim_name):
			continue
		best = maxi(best, sprite.sprite_frames.get_frame_count(anim_name))
	return best


func _describe(anim_name: StringName, sources: Array[AnimatedSprite2D]) -> String:
	var counts := []
	for sprite in sources:
		var frames := sprite.sprite_frames
		if frames == null or not frames.has_animation(anim_name):
			continue
		var fps := maxf(frames.get_animation_speed(anim_name), 0.01)
		var total := 0.0
		for i in frames.get_frame_count(anim_name):
			total += frames.get_frame_duration(anim_name, i) / fps
		counts.append(SpriteFramesI18n.t("describe.anim", [
			sprite.name, frames.get_frame_count(anim_name), total,
			"" if frames.get_animation_loop(anim_name) else SpriteFramesI18n.t("describe.non_loop"),
		]))
	return "   ".join(counts)


# --- 取值 ---

func _selected_player() -> AnimationPlayer:
	if _players.is_empty():
		return null
	return _target_option.get_item_metadata(_target_option.selected) as AnimationPlayer


## 当前表格里选中的库名；一行都没选时返回 null。
## 返回类型故意不标 StringName——它不允许 null。
func _selected_library():
	var item := _checked_library_item()
	if item == null:
		item = _library_tree.get_selected()
	if item == null:
		return null
	var raw := item.get_metadata(0)
	if raw == null:
		return &""
	return StringName(raw)


func _target_sprites() -> Array[AnimatedSprite2D]:
	if _batch_all.button_pressed:
		return _sprites
	if _sprite_option.selected < 0 or _sprites.is_empty():
		return []
	return [_sprite_option.get_item_metadata(_sprite_option.selected) as AnimatedSprite2D]


func _selected_animations() -> Array[StringName]:
	var out: Array[StringName] = []
	for anim_name in _anim_checks:
		var box := _anim_checks[anim_name] as CheckBox
		if box != null and box.button_pressed:
			out.append(anim_name)
	return out


func _set_all_checks(on: bool) -> void:
	for anim_name in _anim_checks:
		(_anim_checks[anim_name] as CheckBox).button_pressed = on


func _settings() -> Dictionary:
	var lib_name: Variant = _selected_library()
	if lib_name == null:
		lib_name = &""
	return {
		"animations": _selected_animations(),
		"library": lib_name,
		"overwrite": _overwrite.button_pressed,
		"stop_playback": _stop_playback.button_pressed,
	}


func _on_confirmed() -> void:
	var player := _selected_player()
	var sprites := _target_sprites()
	var anims := _selected_animations()
	if player == null or sprites.is_empty() or anims.is_empty():
		print(SpriteFramesI18n.log_text("log.nothing_picked"))
		return

	var msg := ""
	if sprites.size() == 1:
		msg = _plugin.export_frames(player, sprites[0], _settings())
	else:
		# 批量：每个精灵用自己的目标下拉
		var targets: Array[AnimationPlayer] = []
		for i in sprites.size():
			var option := _batch_targets[i] as OptionButton
			targets.append(option.get_item_metadata(option.selected) as AnimationPlayer)
		msg = _plugin.export_batch(sprites, targets, _settings())
	# exporter.gd 已经把结果打到 Output，这里避免重复输出
	_hint.text = msg


func _path_of(node: Node) -> String:
	var root := _scene_root()
	if is_instance_valid(root):
		return String(root.get_path_to(node))
	return node.name


## 候选 AnimationPlayer 要从「精灵所在的场景树」里找，
## 不能只认正在编辑的场景根——实例化子场景、非编辑器环境都会拿空。
func _scene_root() -> Node:
	var edited := _edited_root()
	var first: Node = _player if _player != null else (_sprites[0] if not _sprites.is_empty() else null)
	if first == null:
		return edited
	if is_instance_valid(edited) and _is_descendant(first, edited):
		return edited
	return _top_of(first)


static func _is_descendant(node: Node, ancestor: Node) -> bool:
	var cur := node
	while cur != null:
		if cur == ancestor:
			return true
		cur = cur.get_parent()
	return false


## 向上找到「场景级」的顶层节点：撞到窗口根就停，撞到有 scene_file_path 的（实例子场景根）也停。
## 注意别一路爬到窗口根——那里还挂着 autoload（Globals、TransitionLayer 之类），会被误收进来。
static func _top_of(node: Node) -> Node:
	var cur := node
	while true:
		var parent := cur.get_parent()
		# 用「父节点是不是 Window」判边界，不用 get_tree()：
		# 自定义 MainLoop（--script）下 get_tree() 会返回 null
		if parent == null or parent is Window:
			break
		if cur.scene_file_path != "":
			break
		cur = parent
	return cur


static func _edited_root() -> Node:
	if not Engine.is_editor_hint():
		return null
	return EditorInterface.get_edited_scene_root()
