class_name FlyingLocomotion
extends EnemyLocomotion


## 悬停时的纵向阻尼（像素 / 秒²）：让残余纵向速度收敛到 0。
## 默认 0 = 不加阻尼 —— 旧版飞行怪的 velocity.y 完全由各状态直接写死（含巡逻的 bob），
## 加阻尼会跟 bob 打架，故默认保持原行为，需要"飘得更稳"时再开。
@export var hover_damping: float = 0.0
## 死亡后尸体的坠落加速度（像素 / 秒²）。飞行怪死后照常掉到地上。
@export var death_gravity: float = 2304.0

## 存活时：默认什么都不做（纵向由状态直接驱动）；可开 hover_damping 让它自己收敛。
## 死亡后：转为自由落体，配合 on_death() 切回 GROUNDED 才能真的落到地上。
func apply_vertical(enemy: Enemy, delta: float) -> void:
	if enemy.dead:
		enemy.velocity.y += death_gravity * delta
		return
	if hover_damping > 0.0:
		enemy.velocity.y = move_toward(enemy.velocity.y, 0.0, hover_damping * delta)

## 尸体要能落地：FLOATING 模式下 is_on_floor() 恒为 false，death 状态会等不到落地。
func on_death(enemy: Enemy) -> void:
	if enemy.motion_mode == CharacterBody2D.MOTION_MODE_FLOATING:
		enemy.motion_mode = CharacterBody2D.MOTION_MODE_GROUNDED
