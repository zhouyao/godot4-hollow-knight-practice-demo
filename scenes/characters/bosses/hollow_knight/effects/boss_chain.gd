extends StaticBody2D

signal breaking
signal broke

var health: int = 2
## 是否已断：唯一的"再砍没反应"守卫。断后不再扣血、不再重播断裂动画。
var _broken: bool = false
@onready var chain_base: AnimatedSprite2D = $ChainBase
@onready var chain1: Sprite2D = $Chain1
@onready var chain2: Sprite2D = $Chain2
@onready var chain3: Sprite2D = $Chain3
@onready var cut_audio: AudioStreamPlayer2D = $Audio/Cut
@onready var break_audio: AudioStreamPlayer2D = $Audio/Break
@onready var animation_player: AnimationPlayer = $AnimationPlayer


func hit(_direction, damage):
	if _broken:
		return
	health -= damage
	cut_audio.play()
	AuCameraDirector.shake_light()
	if health < 0:
		_broken = true
		break_audio.play()
		break_chain()


func break_chain():
	breaking.emit()
	animation_player.play("break")
	# 链子一断立刻发 broke，不再依赖断裂动画的方法轨道（轨道若不触发会导致信号漏发，
	# 4 根断完也累计不到 4、不切 dormant_end）。dormant 状态 enter 时已接好 broke 计数。
	broke.emit()


## ---- 受击盒（Area2D）接线：让玩家攻击区能命中本链子 ----
## 玩家攻击区的 body_entered 只认 Enemy，纯 StaticBody2D 走不到；而 area_entered 只会对
## "具有 take_damage 的节点"结算，且受击盒是 Area2D 子节点、take_damage 挂在 BossChain 根上，
## 所以玩家侧那条路不会重复结算。这里仿 chest 范式：本链挂一个 collision_layer=256 / mask=32
## 的 Area2D 受击盒，监听自己的 area_entered，从攻击者读出伤害后调 take_damage 自损。
func _on_hitbox_area_entered(area: Area2D) -> void:
	if area == null:
		return
	var attacker := area.get_parent() as Node2D
	if attacker == null or not attacker.has_method("get_damage_kind"):
		return
	take_damage(_slash_damage_of(attacker), attacker)


func _slash_damage_of(attacker: Node) -> int:
	var v: Variant = attacker.get("slash_damage")
	return int(v) if v is int else 1


## 受击入口：与 chest 同签名，供受击盒回调调用；内部转交已有的 hit() 结算。
func take_damage(amount: int = 1, _from: Variant = null) -> void:
	hit(Vector2.ZERO, amount)
