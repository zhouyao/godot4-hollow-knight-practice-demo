## 直接往场景树右键菜单里塞一个条目。
##
## 为什么不用 EditorContextMenuPlugin.add_context_menu_item()：
## 那条路径下引擎不一定会真的调用我们的 Callable（条目显示得出来，点了没反应），
## 且实测它调用时会额外带参数、把 bind 的实参整体挤到后面。
## 这里改成钩住场景树 PopupMenu 自身的 about_to_popup / id_pressed 信号，
## 这两个是普通控件信号，行为确定，且经过 headless 实测。
class_name SceneTreeMenuHook
extends RefCounted

const MENU_ID := 32760

var _bound: Dictionary = {}
var _host


func _init(host) -> void:
	_host = host


func bind() -> int:
	var menus := find_menus()
	for m in menus:
		var menu := m as PopupMenu
		if menu == null or _bound.has(menu.get_instance_id()):
			continue
		_bound[menu.get_instance_id()] = true
		menu.about_to_popup.connect(_on_popup.bind(menu))
		menu.id_pressed.connect(_on_id_pressed.bind(menu))
	return menus.size()


## 场景树面板那几个 PopupMenu（右键菜单本体）
static func find_menus() -> Array:
	var base := EditorInterface.get_base_control()
	var out: Array = []
	if base == null:
		return out
	var stack: Array = [base]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is PopupMenu and _in_scene_tree_dock(node):
			out.append(node)
		for c in node.get_children():
			stack.append(c)
	return out


static func _in_scene_tree_dock(node: Node) -> bool:
	var cur := node
	while cur != null:
		if "SceneTreeDock" in cur.name or "SceneTreeDock" in cur.get_class():
			return true
		cur = cur.get_parent()
	return false


func _on_popup(menu: PopupMenu) -> void:
	var players := _selected_players()
	if players.is_empty():
		return
	if menu.get_item_index(MENU_ID) >= 0:
		return
	# 选中多个时只给一个入口，真正目标在对话框里挑（不写死）
	var label := SpriteFramesI18n.t("menu.import_to", [players[0].name]) if players.size() == 1 \
		else SpriteFramesI18n.t("menu.import_multi", [players.size()])
	menu.add_separator()
	menu.add_item(label, MENU_ID)


func _on_id_pressed(id: int, menu: PopupMenu) -> void:
	if id != MENU_ID:
		return
	if menu.get_item_index(MENU_ID) < 0:
		return
	var players := _selected_players()
	if players.is_empty():
		print(SpriteFramesI18n.log_text("log.menu_no_player"))
		return
	# 只作为对话框里的默认目标，真正目标在对话框里选
	var player := players[0]
	print(SpriteFramesI18n.log_text("log.menu_clicked", [player.name]))
	var root := EditorInterface.get_edited_scene_root()
	_host.open_import_dialog(player, NodeFinder.typed_sprites(NodeFinder.collect(root, AnimatedSprite2D)))


static func _selected_players() -> Array[AnimationPlayer]:
	var out: Array[AnimationPlayer] = []
	for n in EditorInterface.get_selection().get_selected_nodes():
		if n is AnimationPlayer:
			out.append(n)
	return out
