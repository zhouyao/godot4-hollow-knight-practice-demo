@tool
extends EditorContextMenuPlugin

var _plugin


func _init(plugin) -> void:
	_plugin = plugin


func _popup_menu(_paths: PackedStringArray) -> void:
	var items := plan_items(
		EditorInterface.get_edited_scene_root(),
		EditorInterface.get_selection().get_selected_nodes())
	for item in items:
		add_context_menu_item(String(item["label"]), item["callback"] as Callable)


func plan_items(root: Node, selection: Array) -> Array[Dictionary]:
	if root == null:
		return []

	var players := _players_of(selection)
	if players.is_empty():
		return []

	var sprites := NodeFinder.typed_sprites(NodeFinder.collect(root, AnimatedSprite2D))
	var items: Array[Dictionary] = []

	for player in players:
		items.append({
			"label": SpriteFramesI18n.t("menu.import_to", [player.name]),
			"callback": Callable(self, "_on_import").bind(player, sprites),
		})

	if sprites.is_empty():
		items.append({
			"label": SpriteFramesI18n.t("menu.no_sprite"),
			"callback": Callable(self, "_on_no_sprite"),
		})
	return items


func _on_import(_p1 = null, _p2 = null, _p3 = null, _p4 = null, _p5 = null) -> void:
	var args := [_p1, _p2, _p3, _p4, _p5]
	var player: AnimationPlayer = null
	var sprites: Array = []
	for a in args:
		if player == null and a is AnimationPlayer:
			player = a
		elif sprites.is_empty() and a is Array and not (a as Array).is_empty():
			sprites = a as Array
	if player == null:
		player = _first_selected_player()
	if sprites.is_empty():
		sprites = NodeFinder.typed_sprites(NodeFinder.collect(EditorInterface.get_edited_scene_root(), AnimatedSprite2D))
	print(SpriteFramesI18n.log_text("log.menu_callback", [
		player.name if player != null else "?", sprites.size(), args]))
	if player == null:
		print(SpriteFramesI18n.log_text("log.no_player_give_up"))
		return
	_plugin.open_import_dialog(player, sprites)


func _on_no_sprite(_a = null, _b = null, _c = null) -> void:
	print(SpriteFramesI18n.log_text("log.no_sprite"))


func _first_selected_player() -> AnimationPlayer:
	for n in EditorInterface.get_selection().get_selected_nodes():
		if n is AnimationPlayer:
			return n
	return null


func _players_of(selection: Array) -> Array[AnimationPlayer]:
	var out: Array[AnimationPlayer] = []
	for n in selection:
		if n is AnimationPlayer:
			out.append(n)
	return out
