extends Enemy


@onready var wall_detector: RayCast2D = $WallDetector
@onready var ledge_detector: RayCast2D = $LedgeDetector

func _flip_extra() -> void:
	if wall_detector != null:
		wall_detector.target_position.x *= -1
		wall_detector.reset_physics_interpolation()
	if ledge_detector != null:
		ledge_detector.target_position.x *= -1
		ledge_detector.reset_physics_interpolation()
