class_name HitEffect

## 命中特效统一分发器。
## 特效场景由"被命中的目标"自己决定（目标可配置），并支持按"来源种类"细分：
##   - 目标配置 hit_effect_by_source（来源 kind -> 场景）：命中来源种类时优先用它；
##   - 否则回落到约定键 &"slash"（默认受击表现）；
##   - 都没有则回落 _NAIL（通用刀光，兼容未配置的目标 / 旧调用）。
## 用法（目标侧）：在 take_damage 里调用
##   HitEffect.spawn(self, global_position, parent, count_min, count_max, scatter, from)

const _NAIL := preload("res://scenes/effects/nail_hit_spark.tscn")
## 默认受击表现对应的来源种类键：玩家挥砍 get_damage_kind() 返回 &"slash"，
## 因此把它同时作为"查不到具体来源时的默认特效"键。
const _DEFAULT_KEY := &"slash"

## target：被命中的目标节点，用于读取其 hit_effect_by_source；为 null 时回落 _NAIL。
## at：生成位置（世界坐标）；parent：特效的父节点（需已入树）。
## count_min / count_max：本次生成数量的闭区间随机范围（会自动取小/大，min>max 也安全）。
## scatter：多份特效在 at 周围的随机散布半径（像素），避免完全重叠；0 表示全部叠在同一点。
## source：伤害来源节点（如攻击者），用于按来源种类选特效；为 null 或不实现 get_damage_kind() 时按默认处理。
## 注意：必须先用 add_child 再赋 global_position，否则 at 会被当成父节点的局部坐标，
## 若 parent 自身带位移/缩放，特效就会偏离受击点（与 nail_hit_spark.spawn 同规范）。
static func spawn(target: Node, at: Vector2, parent: Node,
		count_min: int = 1, count_max: int = 1, scatter: float = 0.0,
		source: Node = null) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var scene := _resolve_scene(target, source)
	var lo := mini(count_min, count_max)
	var hi := maxi(count_min, count_max)
	var n := clampi(randi_range(lo, hi), 0, 64)
	for i in n:
		var eff := scene.instantiate()
		# 关键：必须在 add_child（会立即触发 _ready）之前写入击退方向，
		# 否则 _ready 运行时方向仍是默认 ZERO，特效会按"无方向"定位。
		# 这里用 at（被击点）而不是 eff.global_position：此刻 eff 还没入树、位置尚未设置。
		if source is Node2D and eff.has_method("set_hit_direction"):
			var d := at - (source as Node2D).global_position
			if d.length_squared() > 0.0:
				eff.set_hit_direction(d.normalized())
		parent.add_child(eff)
		eff.global_position = at
		if scatter > 0.0:
			eff.global_position += Vector2(
				randf_range(-scatter, scatter),
				randf_range(-scatter, scatter))
		# 位置定下来之后再统一处理层级与插值：
		# 1) 部分关卡（如 MossHole）给被击目标单独配了 z_index，特效默认 z=0 会被
		#    前景苔藓层穿插遮挡、只露出零碎一角，看起来像"刀光位置不对"。
		# 2) 本项目开启 2D 物理插值，瞬移后不重置会让首帧从旧位置（世界原点）插值过来，
		#    而刀光只有 0.15s，这一帧几乎占掉整个寿命（与 chest.gd / wet_splash 同规范）。
		if eff is Node2D:
			var fx := eff as Node2D
			if target is Node2D:
				fx.z_index = (target as Node2D).z_index + 1
			fx.reset_physics_interpolation()

## 解析该用的特效场景：来源具体种类 -> &"slash" 默认 -> 通用刀光。
static func _resolve_scene(target: Node, source: Node) -> PackedScene:
	if target == null:
		return _NAIL
	var by_src: Variant = target.get("hit_effect_by_source")
	if by_src is Dictionary:
		var kind := _source_kind(source)
		if kind != &"" and by_src.has(kind):
			var s: Variant = by_src[kind]
			if s is PackedScene:
				return s
		var d: Variant = by_src.get(_DEFAULT_KEY)
		if d is PackedScene:
			return d
	return _NAIL

## 从来源节点取伤害种类；来源未实现 get_damage_kind() 时返回空。
static func _source_kind(source: Node) -> StringName:
	if source != null and source.has_method("get_damage_kind"):
		return source.get_damage_kind()
	return &""
