extends Ammo
class_name ProjectileSpread


## 散射弹药（霰弹）：一发吐出 N 颗子弹呈扇形散开，发射完自身立即消失。
## 用法：把 projectile_spread.tscn 拖到敌人的 projectile_scene 上即可，
## 不用改 Enemy 基类，也不用改状态机 —— 换场景即换弹药，用于做怪物的个性化弹幕。
##
## 子弹默认复用 Projectile（直接改 bullet_scene 就能变成"3 颗火球""3 颗穿透弹"），
## 因此 lifetime / pierce / spawn_grace / 命中结算全部继承。

@export_group("子弹")
## 子弹场景：换掉它即可组合出不同弹幕（默认就是单发直射弹 Projectile）。
@export var bullet_scene: PackedScene = preload("res://scenes/projectiles/projectile.tscn")
## 伤害系数：1.0 = 每颗各打全额（贴脸全中即 N 倍伤害，追求爽快感时用它，
## 把该敌人的 projectile_damage 调低即可平衡）；想让"总量守恒"就设为 1.0 / count。
@export var damage_scale: float = 1.0

@export_group("扇形")
## 一次发射的子弹数量。
@export var count: int = 3
## 扇形总角度（度）：count=3、30° 时三颗分别为 -15° / 0° / +15°。
@export var spread_angle: float = 30.0
## 每颗子弹的随机角度抖动（度）：0 = 严格均匀，给一点值手感更"散"。
@export var random_angle: float = 0.0
## 出生点沿发射方向的偏移（像素）：避免子弹紧贴怪的身体或地形生成。
@export var forward_offset: float = 12.0

func _ready() -> void:
	disable_detection()

## 统一弹药接口（见 Ammo）：发射 N 颗扇形子弹，然后自毁。
## Enemy.launch_projectile() 会先 add_child 再调 fire()，所以此刻已在场景树中。
func fire(dir: Vector2, damage: int) -> void:
	var origin := global_position + dir.normalized() * forward_offset
	var dmg := maxi(1, int(round(damage * damage_scale)))
	spawn_spread(bullet_scene, origin, dir, dmg, count, spread_angle, random_angle)
	queue_free()

## 检查器减负：count <= 1 时扇形角度无意义；没配 bullet_scene 时整组子弹参数都无意义。
func _validate_property(property: Dictionary) -> void:
	super._validate_property(property)
	match property.name:
		"spread_angle", "random_angle":
			if count <= 1:
				property.usage = Ammo.HIDDEN_BUT_SAVED
		"count", "spread_angle", "random_angle", "damage_scale", "forward_offset":
			if bullet_scene == null:
				property.usage = Ammo.HIDDEN_BUT_SAVED
