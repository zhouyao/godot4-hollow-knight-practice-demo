extends RefCounted
class_name Tr

# 场景文件里写死的 text 在 Godot 4.7 实测不会被自动翻译（实例化时没有走 auto_translate），
# 所以菜单场景在 _ready() 末尾统一调一次 Tr.apply() 把当前语言套上。
# 语言可以在菜单里随时切换，因此同一棵树会被重复套用：
# 第一次调用时把场景里的原始文案（也就是翻译表的 key）存进 meta，
# 之后每次都从 key 出发重新翻译——否则「Controls」这类译文会被当成 key，切回中文就翻不回来了。

const SOURCE_META := &"tr_source"
const SOURCE_META_TOOLTIP := &"tr_source_tooltip"


static func apply(root: Node) -> void:
	_apply_node(root)
	for child in root.get_children():
		apply(child)


static func _apply_node(node: Node) -> void:
	# 静态函数调不到 tr()，统一走 TranslationServer
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


# 以 meta 里存下来的原始文案为 key 翻译；第一次调用时当前文案就是原始文案，直接登记
static func _translated(node: Node, text: String, meta: StringName) -> String:
	if text == "":
		return text
	var source: String = node.get_meta(meta, text) as String
	node.set_meta(meta, source)
	return TranslationServer.translate(source)
