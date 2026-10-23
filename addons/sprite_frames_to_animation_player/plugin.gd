@tool
extends EditorPlugin

const CONTEXT_MENU := preload("res://addons/sprite_frames_to_animation_player/context_menu.gd")
const EXPORTER := preload("res://addons/sprite_frames_to_animation_player/exporter.gd")
const IMPORT_DIALOG := preload("res://addons/sprite_frames_to_animation_player/import_dialog.gd")

var _context_menu: EditorContextMenuPlugin
var _hook: SceneTreeMenuHook
var _dialog: ConfirmationDialog
var _exporter: RefCounted
var _tool_menu_name := ""
var _locale_cb: Callable


func _enter_tree() -> void:
	_exporter = EXPORTER.new()
	_hook = SceneTreeMenuHook.new(self)
	_locale_cb = Callable(self, "_on_locale_changed")
	SpriteFramesI18n.on_locale_changed(_locale_cb)
	_add_tool_menu()
	_ensure_dialog()
	print(SpriteFramesI18n.log_text("log.plugin_loaded"))
	_bind_scene_tree_menu()


func _exit_tree() -> void:
	_remove_tool_menu()
	if _locale_cb != Callable():
		SpriteFramesI18n.remove_listener(_locale_cb)
		_locale_cb = Callable()
	if _dialog != null:
		_dialog.queue_free()
		_dialog = null
	if _context_menu != null:
		remove_context_menu_plugin(_context_menu)
		_context_menu = null
	_hook = null
	_exporter = null


func _bind_scene_tree_menu() -> void:
	var tree := _editor_tree()
	if tree == null:
		_fallback_context_menu()
		return
	for _attempt in 10:
		await tree.process_frame
		if _hook == null:
			return
		if _hook.bind() > 0:
			print(SpriteFramesI18n.log_text("log.menu_bound"))
			return
	print(SpriteFramesI18n.log_text("log.menu_fallback"))
	_fallback_context_menu()


func _on_locale_changed() -> void:
	_remove_tool_menu()
	_add_tool_menu()
	if _dialog != null and is_instance_valid(_dialog):
		_dialog.retranslate()


func _add_tool_menu() -> void:
	_tool_menu_name = SpriteFramesI18n.t("tool.menu")
	add_tool_menu_item(_tool_menu_name, Callable(self, "_on_tool_menu"))


func _remove_tool_menu() -> void:
	if _tool_menu_name == "":
		return
	remove_tool_menu_item(_tool_menu_name)
	_tool_menu_name = ""


func _fallback_context_menu() -> void:
	_context_menu = CONTEXT_MENU.new(self)
	add_context_menu_plugin(EditorContextMenuPlugin.ContextMenuSlot.CONTEXT_SLOT_SCENE_TREE, _context_menu)


func open_import_dialog(player: AnimationPlayer, sprites: Array[AnimatedSprite2D]) -> void:
	print(SpriteFramesI18n.log_text("log.dialog_open", [player.name, sprites.size()]))
	_dialog = _ensure_dialog()
	_dialog.setup(player, sprites, self)
	_popup_after_menu_closed()


func _popup_after_menu_closed() -> void:
	var tree := _dialog.get_tree()
	if tree != null:
		await tree.process_frame
	if _dialog == null:
		return
	_dialog.popup_centered()
	if tree != null:
		await tree.process_frame
	if _dialog != null:
		_dialog.fit_library_table()



func _ensure_dialog() -> ConfirmationDialog:
	if _dialog != null and is_instance_valid(_dialog):
		return _dialog
	_dialog = IMPORT_DIALOG.new()
	var base := EditorInterface.get_base_control()
	if base != null:
		base.add_child(_dialog)
	return _dialog


func _editor_tree() -> SceneTree:
	var base := EditorInterface.get_base_control()
	return base.get_tree() if base != null else null


func _on_tool_menu() -> void:
	var root := EditorInterface.get_edited_scene_root()
	if root == null:
		print(SpriteFramesI18n.log_text("log.no_scene"))
		return
	var target: AnimationPlayer = null
	for n in EditorInterface.get_selection().get_selected_nodes():
		if n is AnimationPlayer:
			target = n
			break
	if target == null:
		for n in NodeFinder.collect(root, AnimationPlayer):
			target = n as AnimationPlayer
			break
	if target == null:
		print(SpriteFramesI18n.log_text("log.no_player"))
		return
	open_import_dialog(target, NodeFinder.typed_sprites(NodeFinder.collect(root, AnimatedSprite2D)))



func export_frames(player: AnimationPlayer, sprite: AnimatedSprite2D, settings: Dictionary) -> String:
	var ur := get_undo_redo()
	ur.create_action("SpriteFrames → AnimationPlayer")
	ur.add_do_method(_exporter, "do_export", player, sprite, settings.duplicate())
	ur.add_undo_method(_exporter, "undo_export")
	ur.commit_action()
	EditorInterface.mark_scene_as_unsaved()
	return _exporter.last_message


func export_batch(sprites: Array, targets: Array, settings: Dictionary) -> String:
	var ur := get_undo_redo()
	ur.create_action("SpriteFrames → AnimationPlayer")
	ur.add_do_method(_exporter, "do_export_batch", sprites, targets, settings.duplicate())
	ur.add_undo_method(_exporter, "undo_export")
	ur.commit_action()
	EditorInterface.mark_scene_as_unsaved()
	return _exporter.last_message
