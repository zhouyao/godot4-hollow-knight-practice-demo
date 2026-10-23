extends RefCounted
class_name Tr


const SOURCE_META := &"tr_source"
const SOURCE_META_TOOLTIP := &"tr_source_tooltip"


static func apply(root: Node) -> void:
	_apply_node(root)
	for child in root.get_children():
		apply(child)


static func _apply_node(node: Node) -> void:
	var label := node as Label
	if label != null:
		if label.text != "":
			label.text = _translated(node, label.text, SOURCE_META)
		return
	var button := node as Button
	if button != null:
		if button.text != "":
			button.text = _translated(node, button.text, SOURCE_META)
		if button.tooltip_text != "":
			button.tooltip_text = _translated(node, button.tooltip_text, SOURCE_META_TOOLTIP)
		return


static func _translated(node: Node, text: String, meta: StringName) -> String:
	if text == "":
		return text
	var source: String = node.get_meta(meta, text) as String
	node.set_meta(meta, source)
	return TranslationServer.translate(source)
