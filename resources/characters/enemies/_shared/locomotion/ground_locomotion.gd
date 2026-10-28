class_name GroundLocomotion
extends EnemyLocomotion


## 重力加速度（像素 / 秒²），默认与玩家手感一致（2 * 3 * UNIT_SIZE / 0.5²）。
@export var gravity: float = 2304.0

func _init() -> void:
	nav_planar_only = true

## 站着不动时不叠加重力，避免 is_on_floor() 判定抖动导致速度累积。
func apply_vertical(enemy: Enemy, delta: float) -> void:
	if not enemy.is_on_floor():
		enemy.velocity.y += gravity * delta

## 地面怪本来就是 GROUNDED，无需切换。
func on_death(_enemy: Enemy) -> void:
	pass
