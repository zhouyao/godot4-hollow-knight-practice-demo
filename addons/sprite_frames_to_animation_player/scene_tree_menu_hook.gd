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
