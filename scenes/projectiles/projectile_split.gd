extends Projectile
class_name ProjectileSplit


## 延迟分裂弹（空爆弹）：母弹本体先飞一段，到点炸成 N 颗扇形子弹，母弹随即消失。
## 与 ProjectileSpread 的区别：Spread 出膛即散，Split 先飞 —— 适合做"抛物线炸弹""贴脸前摇"这类弹幕。
##
## 母弹直接继承 Projectile，所以飞行速度 / 存活时长 / 穿透 / 出生保护期全部沿用，
## 下面这些是"分裂"专属参数；子弹同样默认复用 Projectile。

@export_group("子弹")
## 子弹场景：换掉它即可组合出不同弹幕（默认就是单发直射弹 Projectile）。
@export var bullet_scene: PackedScene = preload("res://scenes/projectiles/projectile.tscn")
## 伤害系数：1.0 = 每颗各打全额；想让分裂后总量守恒就设为 1.0 / count。
## 注意：母弹自身命中玩家时不造成伤害（见 split_on_hit），伤害全在分裂后的子弹上。
@export var damage_scale: float = 1.0

@export_group("分裂时机")
## 出膛后多久分裂（秒）：<= 0 表示出膛即分裂（此时行为等同 ProjectileSpread）。
@export var split_delay: float = 0.6
## 命中玩家或地形时提前分裂：true = 炸弹手感（贴到什么炸什么，母弹不再单独结算伤害）。
@export var split_on_hit: bool = false
## 存活时间耗尽时也分裂：true = 兜底空爆，保证母弹不会白飞一趟。
@export var split_on_expire: bool = false

@export_group("扇形")
## 一次分裂出的子弹数量。
@export var count: int = 3
## 扇形总角度（度）：count=3、30° 时三颗分别为 -15° / 0° / +15°。
@export var spread_angle: float = 30.0
## 每颗子弹的随机角度抖动（度）：0 = 严格均匀。
@export var random_angle: float = 0.0
## 分裂点沿母弹飞行方向的偏移（像素）：避免子弹生成在母弹体内。
@export var forward_offset: float = 8.0

var _split_done := false
var _split_damage: int = 1

## 统一弹药接口（见 Ammo）：起飞，并按 split_delay 排好分裂。
func fire(dir: Vector2, damage: int) -> void:
	super.fire(dir, damage)
	_split_done = false
	_split_damage = maxi(1, int(round(damage * damage_scale)))
	if split_delay <= 0.0:
		_split_now()
		queue_free()
		return
	var timer := get_node_or_null("SplitTimer") as Timer
	if timer == null:
		push_warning("%s: 缺少 SplitTimer 节点，无法延迟分裂，退化为普通直射弹" % name)
		return
	timer.start(split_delay)

## 命中：开启 split_on_hit 时提前炸开，母弹不单独结算伤害（伤害转移到子弹上）。
func _on_body_entered(body: Node2D) -> void:
	if split_on_hit and not _split_done and _grace <= 0.0:
		# 命中谁由阵营决定（见 Ammo.faction / is_target），不再写死 group。
		if is_target(body) or (body.collision_layer & Globals.LAYER_OBJECTS) != 0:
			_split_now()
			queue_free()
			return
	super._on_body_entered(body)

## 存活时间耗尽：开启 split_on_expire 时兜底空爆。
func _on_life_timer_timeout() -> void:
	if split_on_expire and not _split_done:
		_split_now()
	super._on_life_timer_timeout()

func _on_split_timer_timeout() -> void:
	_split_now()
	queue_free()

## 分裂：沿母弹当前飞行方向吐出扇形子弹，母弹由调用方决定是否继续存在（默认消失）。
func _split_now() -> void:
	if _split_done:
		return
	_split_done = true
	var timer := get_node_or_null("SplitTimer") as Timer
	if timer != null:
		timer.stop()
	var origin := global_position + _dir * forward_offset
	spawn_spread(bullet_scene, origin, _dir, _split_damage, count, spread_angle, random_angle)

## 检查器减负：与 ProjectileSpread 同规则。
func _validate_property(property: Dictionary) -> void:
	super._validate_property(property)
	match property.name:
		"spread_angle", "random_angle":
			if count <= 1:
				property.usage = Ammo.HIDDEN_BUT_SAVED
		"count", "spread_angle", "random_angle", "damage_scale", "forward_offset":
			if bullet_scene == null:
				property.usage = Ammo.HIDDEN_BUT_SAVED
