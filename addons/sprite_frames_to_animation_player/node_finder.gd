class_name NodeFinder
extends RefCounted


static func collect(root: Node, type: Variant) -> Array:
	var out: Array = []
	if is_instance_valid(root):
		_collect(root, type, out)
	return out


static func _collect(node: Node, type: Variant, out: Array) -> void:
	if is_instance_of(node, type):
		out.append(node)
	for child in node.get_children():
		_collect(child, type, out)


static func typed_sprites(raw: Array) -> Array[AnimatedSprite2D]:
	var out: Array[AnimatedSprite2D] = []
	for n in raw:
		if n is AnimatedSprite2D:
			out.append(n)
	return out


static func typed_players(raw: Array) -> Array[AnimationPlayer]:
	var out: Array[AnimationPlayer] = []
	for n in raw:
		if n is AnimationPlayer:
			out.append(n)
	return out
