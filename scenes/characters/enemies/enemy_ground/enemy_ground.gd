extends Enemy
class_name EnemyGround


@onready var wall_detector: RayCast2D = $WallDetector
@onready var ledge_detector: RayCast2D = $LedgeDetector

func _flip_extra() -> void:
	super._flip_extra()  # 翻转 muzzle（吐弹口）
	if wall_detector != null:
		wall_detector.target_position.x *= -1
		wall_detector.reset_physics_interpolation()
	if ledge_detector != null:
		# 悬崖探测器必须跟着朝向左右换位（position.x），只翻 target_position.x 对垂直射线无效，
		# 会导致它永远只探测右侧、左侧悬崖探不到，敌人朝左走时会直接踏空。
		ledge_detector.position.x *= -1
		ledge_detector.target_position.x *= -1
		ledge_detector.reset_physics_interpolation()

## 站在地面且前方探测不到地面（悬崖 / 平台边缘）时返回 true。
## 巡逻与战斗陆地移动都用它来避免踏空；飞行怪无 ledge_detector，恒为 false。
func ledge_ahead() -> bool:
	if not is_on_floor():
		return false
	return ledge_detector != null and not ledge_detector.is_colliding()
