class_name BossHollowKnight
extends Boss

@onready var ledge_detector: RayCast2D = $LedgeDetector

## 招架中：为 true 时，正面来袭伤害不结算、不进受击硬直，改发 blocked 让 counter 状态接手反击；
## 但若伤害来自背后（背刺），则正常结算并改发 guard_broken，让 counter 状态立刻解除。
## 由 HollowKnightCounterState 在 READY 相位开关；正/背判定见 _is_front_damage。
var blocking: bool = false
## 格挡成功（正面伤害被挡下）时发出，参数为伤害来源。
signal blocked(from: Node2D)
## 招架中被背刺破招（伤害来自背后）时发出，参数为伤害来源；counter 据此立刻退出招架。
signal guard_broken(from: Node2D)

func take_damage(amount: int, from: Node2D = null) -> void:
	if not dead and not invincible and blocking:
		if _is_front_damage(from):
			blocked.emit(from)
			return
		# 背刺破招：正常结算伤害（受击特效 / 掉血 / 无敌帧），并通知 counter 立刻解除招架。
		super.take_damage(amount, from)
		guard_broken.emit(from)
		return
	super.take_damage(amount, from)

## 伤害是否来自 boss 正面（朝向一侧）。来源在朝向侧即视为正面，与玩家 _is_blocking 同判据。
func _is_front_damage(from: Node2D) -> bool:
	if from == null:
		return false
	var side := signf(from.global_position.x - global_position.x)
	return side == float(move_direction)

func _flip_extra() -> void:
	super._flip_extra()  # 翻转 muzzle（吐弹口），保留 Enemy 基类行为
	if ledge_detector != null:
		ledge_detector.position.x = absf(ledge_detector.position.x) * float(move_direction)
		ledge_detector.reset_physics_interpolation()
