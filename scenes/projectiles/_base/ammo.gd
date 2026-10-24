extends Area2D
class_name Ammo


## 弹药统一基类：一切可作为 projectile_scene 挂载的东西都继承它。
## 基类定在 Area2D 上，是为了让"要飞、要碰撞"的弹（Projectile / ProjectileSplit）
## 与"只是个发射器"的弹（ProjectileSpread）同属一棵继承树，
## 从而让发射侧能用 is Ammo 做统一校验；不需要碰撞的弹药请调 disable_detection()。
##
## 约定唯一入口 fire(dir, damage)：发射侧只认这一个签名，
## 命中结算 / 生命周期 / 自毁时机全部由具体弹药自己负责，基类不做任何假设。
##
## 新增一种弹药的步骤（不碰发射方、不碰状态机）：
##   1. extends Ammo（若要"先飞一段再分裂"可 extends Projectile，它本身也是 Ammo）
##   2. 重写 fire(dir, damage)
##   3. 存成 .tscn，拖到发射器的 projectile_scene 上
##
## 已知子类：
##   Projectile       单发直射弹，也是其它弹药复用的"子弹本体"
##   ProjectileSpread 一次吐出 N 颗呈扇形散开（发射即散）
##   ProjectileSplit  母弹先飞 split_delay 秒，再炸成 N 颗（延迟分裂 / 空爆弹）
##
## ── 阵营机制（faction）：决定本弹药打谁 ──────────────────────────────
## 命中掩码与目标 group 全部由 faction 推导，在 _enter_tree() 里统一套用，
## 因此同一枚弹药可以在敌我之间复用，不必为玩家和怪物各写一份 Projectile。
##   Faction.ENEMY   打玩家（现状默认：mask = Player | Objects）
##   Faction.PLAYER  打怪物（mask = Enemies | Objects）
##   Faction.NEUTRAL 通吃（boss 弹幕 / 被反弹的子弹）
## faction 由发射方写入（见 Enemy.launch_projectile()），并由 spawn_spread() 传播给子弹，
## 保证散射 / 分裂出的整轮弹幕与母弹同源 —— 否则玩家的散射弹会反手打自己。
##
## ── 权限机制（usable_by）：决定谁能装配本弹药 ────────────────────────
## 与 faction 解耦：前者是"打谁"，后者是"谁能用"。
##   默认敌我通用；只允许玩家装配填 BIT_PLAYER；禁止任何阵营直接装配填 0（纯内部件）。

## _validate_property() 用的"隐藏但仍序列化"标记：与 Enemy 的同名常量语义一致，
## 保证被隐藏的参数值依然写进 .tscn，不会因为切换配置而丢失。
const HIDDEN_BUT_SAVED := PROPERTY_USAGE_NO_EDITOR | PROPERTY_USAGE_STORAGE

enum Faction { PLAYER, ENEMY, NEUTRAL }

## usable_by 用的位标记：与 Faction 一一对应，可用 | 组合。
const BIT_PLAYER := 1 << 0
const BIT_ENEMY := 1 << 1
const BIT_NEUTRAL := 1 << 2

## 阵营 → 结算伤害用的 group 列表（NEUTRAL 两边都结算）。
## 用数组而不是单一 group，是为了让 NEUTRAL 能同时覆盖玩家与怪物。
const TARGET_GROUPS := {
	Faction.PLAYER: ["enemy"],
	Faction.ENEMY: ["player"],
	Faction.NEUTRAL: ["player", "enemy"],
}

## 本弹药所属阵营：由发射方写入，决定打谁（见类注释的"阵营机制"）。
@export var faction: Faction = Faction.ENEMY

## 允许装配本弹药的阵营（位掩码，见 BIT_*）：0 = 禁止任何阵营装配（纯内部件）。
@export var usable_by: int = BIT_PLAYER | BIT_ENEMY


## 入树时套用阵营对应的碰撞层与掩码。
## 用 _enter_tree() 而不是 _ready()，是因为 Projectile / ProjectileSpread 都重写了 _ready()
## 且不调用 super —— 挂在基类 _ready() 里的逻辑永远不会执行。
func _enter_tree() -> void:
	_apply_faction()


## 套用阵营对应的碰撞层与掩码。
func _apply_faction() -> void:
	collision_layer = Globals.LAYER_PROJECTILES
	collision_mask = _hit_mask(faction)


## 阵营 → 命中掩码：我能打到谁。
## 写成函数而不是 const 字典，是因为要引用 Globals 的图层常量
## （autoload 常量无法参与 const 初始化）。
func _hit_mask(f: Faction) -> int:
	match f:
		Faction.PLAYER:
			return Globals.LAYER_ENEMIES | Globals.LAYER_OBJECTS
		Faction.NEUTRAL:
			return Globals.LAYER_PLAYER | Globals.LAYER_ENEMIES | Globals.LAYER_OBJECTS
		_:
			return Globals.LAYER_PLAYER | Globals.LAYER_OBJECTS


## 指定阵营是否被允许装配本弹药。
func can_be_used_by(f: Faction) -> bool:
	return (usable_by & _faction_bit(f)) != 0


## body 是否属于本阵营的伤害结算目标。
func is_target(body: Node2D) -> bool:
	for g: String in TARGET_GROUPS.get(faction, []):
		if body.is_in_group(g):
			return true
	return false


## 发射入口：由发射侧调用，子类必须重写。
## dir 已为指向目标的方向（未归一化也可，内部会归一化），damage 来自发射方的 projectile_damage。
func fire(_dir: Vector2, _damage: int) -> void:
	push_warning("%s: Ammo.fire() 未实现，请子类重写" % name)

## 关掉本弹药的碰撞检测：给不需要飞、不需要碰撞的发射器型弹药（如 ProjectileSpread）用，
## 在 _ready() 里调用，避免空 Area2D 白白参与物理检测。
func disable_detection() -> void:
	monitoring = false
	monitorable = false
	collision_layer = 0
	collision_mask = 0

## 扇形发射：散射弹与延迟分裂弹共用，避免两处各写一遍角度计算。
## bullet_scene 每颗子弹的来源场景；origin 发射点（全局坐标）；base_dir 扇形中轴方向；
## spread_angle_deg 扇形总角度（度），count=3、30° 时即 -15° / 0° / +15°；
## random_angle_deg 每颗的随机抖动（度），0 = 严格均匀。
## 返回值：实际成功生成的子弹数（bullet_scene 无效时为 0）。
func spawn_spread(bullet_scene: PackedScene, origin: Vector2, base_dir: Vector2,
		damage: int, count: int, spread_angle_deg: float,
		random_angle_deg: float = 0.0) -> int:
	var parent := get_parent()
	if parent == null:
		push_warning("%s: 未加入场景树，无法发射子弹" % name)
		return 0
	if bullet_scene == null or count <= 0:
		push_warning("%s: bullet_scene 为空或 count <= 0，跳过发射" % name)
		return 0

	var dir := base_dir.normalized()
	var step := 0.0
	if count > 1:
		step = deg_to_rad(spread_angle_deg) / float(count - 1)
	var start := -step * (count - 1) * 0.5
	var spawned := 0

	for i in count:
		var b := bullet_scene.instantiate()
		if b == null:
			push_warning("%s: 子弹实例化失败" % name)
			continue
		if not (b is Ammo):
			push_warning("%s: bullet_scene 的根节点不是 Ammo，无法发射" % name)
			b.free()
			continue
		# 阵营传播：必须在 add_child 之前写入，子弹入树时才会套用正确的掩码，
		# 否则散射 / 分裂出的整轮弹幕会退回默认阵营。
		b.faction = faction
		# 挂在自己的父节点下（发射方把弹药加到 current_scene，父节点即 current_scene），
		# 而不是挂到自己身上 —— 否则本弹药自毁时会把刚发射的子弹一起带走。
		parent.add_child(b)
		b.global_position = origin
		var a := start + step * i
		if random_angle_deg > 0.0:
			a += deg_to_rad(randf_range(-random_angle_deg, random_angle_deg))
		b.fire(dir.rotated(a), damage)
		spawned += 1

	return spawned

## 检查器减负钩子：子类重写后先调用 super._validate_property(property)。
## 例：count <= 1 时不需要扇形角度；bullet_scene 为空时整组子弹参数都无意义。
func _validate_property(_property: Dictionary) -> void:
	pass


## Faction → usable_by 位标记。
func _faction_bit(f: Faction) -> int:
	match f:
		Faction.NEUTRAL:
			return BIT_NEUTRAL
		Faction.ENEMY:
			return BIT_ENEMY
		_:
			return BIT_PLAYER
