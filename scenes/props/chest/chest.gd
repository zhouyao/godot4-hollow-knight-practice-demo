extends StaticBody2D
class_name Chest


## 可击破木箱：挡在路上的结实木箱，砍 3 刀炸开、碎片四溅、钱币迸落。
##
## 树结构见 chest.tscn：
##   Chest(StaticBody2D, 挡住玩家)
##   ├─ BodyCollisionShape2D   挡路的碰撞体，炸开后失效
##   ├─ Hitbox(Area2D)         受击盒，由本脚本监听它的 area_entered 后调自己的 take_damage()
##   └─ Visual(Node2D)         抖动只抖这里，碰撞体纹丝不动
##        ├─ IdleSprite        完好贴图
##        └─ DeathSprite       破损 / 掀盖贴图
##
## 为什么要 Hitbox：玩家攻击区的 body_entered 只认 Enemy，纯 StaticBody2D 走那条路不会掉血；
## 而 Area2D ↔ Area2D 的检测对每个方向独立生效，箱子只要在自己的 mask 里放行玩家攻击区所在层，
## 就能用"自己的受击盒 + 自己的 take_damage()"完成命中判定，无需给 Hitbox 挂任何脚本。
##
## 坐标约定：节点原点 = 箱子底边的触地线。两张贴图的"底边中心"锚点（centered=false + offset）、
## 两个碰撞形状的尺寸与位置、受击盒掩码与 area_entered 连接，全部烘焙在 chest.tscn 里 ——
## 编辑器所见即运行时所得，在关卡里拖动实例不会再与运行时错位。
## 换贴图时需同步改：两个 Sprite 的 offset 与两个碰撞形状；
## 箱体尺寸由本脚本直接读 IdleSprite 的贴图矩形，不再单独维护。
##
## 命中反馈严格分两步（方便以后复用到敌人 / 其它可破坏物）：
##   第一步 _settle_hit()          纯数值结算，不产生任何表现，只回答"这次打死了没"；
##   第二步 _play_hit_feedback()   纯表现播放，只读第一步的结果，不再改任何数值。
##
## 硬性要求：炸开之后 broken = true，take_damage 第一行就 return
## ——不掉钱、不冒烟、不抖动、不再生成任何东西，残骸永久留在场景里。

signal chest_broken

const COIN_SCENE := preload("res://scenes/drops/coin_pickup.tscn")
const BURST_SCENE := preload("res://scenes/effects/chest/chest_burst.tscn")

@export_group("生命")
## 最大血量：默认 3，玩家每刀 1 点 → 第 3 刀炸开。想改刀数只动这一项。
@export var max_health: int = 3

@export_group("受击反馈")
## 箱体抖动：强度（像素振幅）与衰减时长（秒），强度在 jitter_time 内线性衰减到 0。
@export var jitter_strength: float = 14.0
@export var jitter_time: float = 0.33
## 受击特效表（来源种类 -> 场景）：留空则回落通用刀光，见 scenes/effects/hit_effect.gd。
@export var hit_effect_by_source: Dictionary = {}
@export_range(0, 24, 1, "or_greater") var hit_effect_count_min: int = 1
@export_range(0, 24, 1, "or_greater") var hit_effect_count_max: int = 2
@export var hit_effect_scatter: float = 12.0

@export_group("屏震")
## 屏震总开关：关掉后本箱子的受击屏震与炸开屏震全部静默（强度照配，随时可开）。
## 只影响这个实例，方便在编辑器里给关卡里特定的箱子单独关掉。
@export var shake_enabled: bool = true
## 命中屏震：强度 = 像素振幅；衰减速度越大收得越快；方向非 ZERO 时抖动整体朝该方向偏。
@export var hit_shake_strength: float = 8.0
@export var hit_shake_fade: float = 1.5
@export var hit_shake_direction: Vector2 = Vector2.ZERO
## 炸开屏震：默认强度 16 = 命中 8 的两倍（即原"翻倍"需求），衰减与方向独立可调。
## 想要"向上顶一下"可以把 death_shake_direction 设成 (0, -1)。
@export var death_shake_strength: float = 16.0
@export var death_shake_fade: float = 1.5
@export var death_shake_direction: Vector2 = Vector2.ZERO

@export_group("掉落")
@export var coin_scene: PackedScene = COIN_SCENE
## 每一刀（含最后一刀）迸出的钱币数量闭区间。
@export_range(0, 24, 1) var coins_min: int = 3
@export_range(0, 24, 1) var coins_max: int = 6

@export_group("炸开")
@export var burst_scene: PackedScene = BURST_SCENE
## 碎石迸发中心相对"箱体中心"的额外偏移，用于微调起点高度。
@export var burst_origin_offset: Vector2 = Vector2.ZERO
## 各发射器在中心周围的随机散布（像素）：让碎石从箱体各处起飞。
@export var burst_origin_spread: Vector2 = Vector2(36.0, 24.0)

var health: int
## 是否已炸开：唯一的"再砍没反应"守卫。
var broken: bool = false

@onready var _body_shape: CollisionShape2D = $BodyCollisionShape2D
@onready var _hitbox: Area2D = $Hitbox
@onready var _visual: Node2D = $Visual
@onready var _idle_sprite: Sprite2D = $Visual/IdleSprite
@onready var _death_sprite: Sprite2D = $Visual/DeathSprite

var _jitter_tween: Tween = null


func _ready() -> void:
	health = max_health


## 受击盒接线：Hitbox 就是个裸 Area2D（不含脚本）。它的掩码（LAYER_DETECTION_AND_ATTACK = 32）
## 与 area_entered → _on_hitbox_area_entered 的连接都烘焙在 chest.tscn 里，本脚本不再干预。
## 玩家的攻击区（前劈 / 上劈 / 下劈）扫进受击盒 → 走本节点的 take_damage()。
## 攻击区的碰撞形状只在挥砍动画期间启用（状态退出时 player.end_attack() 关闭），
## 所以这里不需要再判断玩家是不是在挥砍。
func _on_hitbox_area_entered(area: Area2D) -> void:
	if area == null:
		return
	# 攻击区的父节点就是攻击者（玩家）。只认能给出伤害种类的来源，
	# 顺带把其它 Area2D（KillBox、领地等）挡在门外。
	var attacker := area.get_parent() as Node2D
	if attacker == null or not attacker.has_method("get_damage_kind"):
		return
	take_damage(_slash_damage_of(attacker), attacker)


## 攻击者没有 melee/slash 伤害属性时退回 1 点（需求：每刀 1 点）。
## 先查 melee_damage（Boss 基类），回退 slash_damage（玩家），两者兼容。
func _slash_damage_of(attacker: Node) -> int:
	var v: Variant = attacker.get("melee_damage")
	if v == null:
		v = attacker.get("slash_damage")
	return int(v) if v is int else 1


# ---- 内部工具 -------------------------------------------------------------

## 贴图的"底边中心"锚点、两个碰撞形状的尺寸与位置、受击盒掩码与信号连接
## 全部烘焙在 chest.tscn 里，这里只留一个运行时还要用的取形状助手。
func _hitbox_shape() -> CollisionShape2D:
	return _hitbox.get_node_or_null("CollisionShape2D") as CollisionShape2D


## 箱体像素尺寸：直接取 IdleSprite 的贴图矩形（已含 scale / flip）。
## 钱币与碎石的出生高度按它算，换贴图只改 chest.tscn 即可，无需再同步脚本里的数值。
## 贴图缺失时返回 ZERO，调用方拿到的出生高度就是节点原点，不会崩。
func _body_size() -> Vector2:
	if _idle_sprite == null or _idle_sprite.texture == null:
		return Vector2.ZERO
	return _idle_sprite.get_rect().size


# ---- 受损入口 -------------------------------------------------------------

func take_damage(amount: int = 1, from: Node2D = null) -> void:
	if broken:
		return
	var killed := _settle_hit(amount)
	_play_hit_feedback(killed, from)


## 第一步：纯数值结算。不生成任何节点、不播任何动画、不动任何表现，
## 只回答一个问题：这一刀打完之后血量归零了吗。
func _settle_hit(amount: int) -> bool:
	health = maxi(health - maxi(amount, 1), 0)
	return health <= 0


## 第二步：纯表现播放。只读第一步的结果，不再改任何数值。
## 以后敌人 / 木桶 / 石碑要复用，只要能给出同样的 killed 结果就能直接接这一段。
func _play_hit_feedback(killed: bool, from: Node2D) -> void:
	var host := _effect_host()
	# 1. 受击刀光 / 烟：特效场景由本节点 hit_effect_by_source 决定，留空回落通用刀光。
	HitEffect.spawn(self, global_position, host,
			hit_effect_count_min, hit_effect_count_max, hit_effect_scatter, from)
	# 2. 箱体朝随机方向高频抖动，强度在 jitter_time 内衰减到 0。
	_jitter()
	# 3. 屏幕震动。
	_shake(hit_shake_strength, hit_shake_fade, hit_shake_direction)
	# 4. 迸出 min~max 枚钱币，随机向上的初速抛飞（抛飞逻辑在 DropSpawner 里）。
	_spawn_coins()
	if killed:
		_explode(host)


# ---- 表现细节 -------------------------------------------------------------

## 高频抖动：每一帧随机换方向，振幅随进度线性衰减到 0，结束后复位。
## 只抖 Visual，碰撞体不动 —— 箱子看着在震，挡路判定依然稳定。
func _jitter() -> void:
	if _visual == null:
		return
	# 连击时会叠出多个 tween 抢同一个 position，起新的之前先掐掉旧的。
	if _jitter_tween != null and _jitter_tween.is_valid():
		_jitter_tween.kill()
	var tw := _visual.create_tween()
	tw.tween_method(_jitter_step, 0.0, 1.0, jitter_time)
	tw.finished.connect(_reset_jitter)
	_jitter_tween = tw


func _jitter_step(t: float) -> void:
	_visual.position = Vector2.from_angle(randf() * TAU) * jitter_strength * (1.0 - t)


func _reset_jitter() -> void:
	if _visual != null:
		_visual.position = Vector2.ZERO


## 触发一次屏震：总开关 shake_enabled 关掉时一律不发；强度 <= 0 视为关闭。
## direction 非 ZERO 时带方向性偏置。
func _shake(strength: float, fade: float, direction: Vector2 = Vector2.ZERO) -> void:
	if not shake_enabled or strength <= 0.0:
		return
	AuCameraDirector.shake(strength, fade, direction)


func _spawn_coins() -> void:
	if coin_scene == null:
		return
	var n := randi_range(mini(coins_min, coins_max), maxi(coins_min, coins_max))
	if n <= 0:
		return
	# 从箱体中上部迸出：抬到 0.6 倍箱高，钱币才有下落的弧线可看。
	DropSpawner.spawn_pickups(coin_scene, n, global_position + Vector2(0.0, -_body_size().y * 0.6))


## 炸开：换破损贴图 + 碰撞失效 + 炸开屏震 + 碎石迸发。
## 残骸本身就是 DeathSprite，永久留在场景里，不做任何淡出或销毁。
func _explode(host: Node) -> void:
	broken = true
	# 1. 立刻换成破损 / 掀盖贴图；两张贴图共用底边锚点，换贴图绝不悬空。
	_idle_sprite.visible = false
	_death_sprite.visible = true
	# 2. 碰撞失效：挡路的碰撞体与受击盒一起关掉，玩家可以直接走过去。
	#    take_damage 是从 area_entered 回调里进来的，此刻物理服务器仍在派发信号，
	#    直接改 monitoring / disabled 会被拒绝，必须延迟到当前物理帧结束之后。
	_set_collision_enabled(false)
	# 3. 炸开屏震（默认强度 16 = 命中的两倍）。
	_shake(death_shake_strength, death_shake_fade, death_shake_direction)
	# 4. 一次性迸出 15 块碎石。
	_spawn_burst(host)
	chest_broken.emit()


func _set_collision_enabled(enabled: bool) -> void:
	_body_shape.set_deferred("disabled", not enabled)
	if _hitbox == null:
		return
	_hitbox.set_deferred("monitoring", enabled)
	_hitbox.set_deferred("monitorable", enabled)
	var shape := _hitbox_shape()
	if shape != null:
		shape.set_deferred("disabled", not enabled)


func _spawn_burst(host: Node) -> void:
	if burst_scene == null or not burst_scene.can_instantiate() or host == null:
		return
	var burst := burst_scene.instantiate()
	# 碎石从箱体中心起飞：抬高半箱高。这里在换贴图之后才取尺寸，
	# 照样读 IdleSprite —— 它被隐藏只是 visible = false，贴图矩形依然在。
	var size := _body_size()
	# 参数必须在入树前写入：ChestBurst._ready 里就按这些参数起爆。
	# 用属性探测而不是 `is ChestBurst` 强转：新脚本未被编辑器扫描进全局类缓存时，
	# 直接写类型名会报 "Could not find type"，而属性探测在任何时机都能用。
	if "origin_offset" in burst:
		burst.origin_offset = Vector2(0.0, -size.y * 0.5) + burst_origin_offset
	if "origin_spread" in burst:
		burst.origin_spread = burst_origin_spread
	host.add_child(burst)
	# 必须先 add_child 再赋 global_position：未入树时会被当成父节点的局部坐标，
	# 而父容器（关卡里的 Obstacles / Effects 分组）自身带位移，会导致特效整体偏移。
	burst.global_position = global_position
	# 本项目开了 2D 物理插值：位置改变后必须重置插值，否则第一帧会从世界原点飞过来
	# （与 DropSpawner 对 Pickup 的处理一致）。
	burst.reset_physics_interpolation()


func _effect_host() -> Node:
	return get_tree().current_scene
