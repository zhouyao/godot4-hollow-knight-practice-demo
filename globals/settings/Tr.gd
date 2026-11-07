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
	var has_source := node.has_meta(meta)
	var source: String = node.get_meta(meta, text) as String
	var translated := TranslationServer.translate(source)
	# 数字、键名等脚本动态生成的文本不是翻译 key：别把它记成 source，
	# 否则切换语言时会拿旧译文 / 旧数值当 key，把刚刷新过的文本覆盖回去。
	# 已显式写入 source 的动态文本（HintLabel 等）仍按 source 翻译。
	if not has_source and translated == source:
		return text
	node.set_meta(meta, source)
	return translated
