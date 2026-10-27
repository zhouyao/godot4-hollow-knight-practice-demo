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

## 探测器几何：偏移与射线长度直接沿用场景里 LedgeDetector 的摆位，
## 这样每只怪在 .tscn 里手工调过的位置（如 crawlid 的 (58, 61)）自动生效，代码里不用再抄一份常量。
func _probe_offset() -> Vector2:
	if ledge_detector == null:
		return Vector2(19.0, 3.0)
	return Vector2(absf(ledge_detector.position.x), ledge_detector.position.y)


func _probe_length() -> float:
	if ledge_detector == null:
		return 15.0
	var length := ledge_detector.target_position.length()
	return length if length > 0.0 else 15.0


## move_x（±1）方向的前方有没有落脚点。返回 true = 有地，可以走。
## 与"当前朝向"解耦（只用传入的方向），并且每次即时查询而非读 RayCast2D 的缓存：
## 探测器会随翻面立刻换边，而 RayCast2D.is_colliding() 是上一物理帧的结果，
## 两者叠加会让追击状态在同一帧里"看着悬崖掉头、下一帧又掉回来"，形成逐帧左右翻面。
func has_ground_ahead(move_x: float) -> bool:
	if move_x == 0.0 or not is_on_floor():
		return true  # 空中不做悬崖限制（沿用原 ledge_ahead 语义）
	var offset := _probe_offset()
	var from := global_position + Vector2(offset.x * signf(move_x), offset.y)
	var to := from + Vector2(0.0, _probe_length())
	var space := get_world_2d().direct_space_state
	if space == null:
		return true
	var query := PhysicsRayQueryParameters2D.create(from, to)
	query.collision_mask = ledge_detector.collision_mask if ledge_detector != null else 4
	query.exclude = [get_rid()]
	return not space.intersect_ray(query).is_empty()


## 挑一个"踩得实"的横向方向：优先 preferred_x，它踏空时退而用另一侧；两侧都踏空返回 0.0。
func safe_step_x(preferred_x: float) -> float:
	if has_ground_ahead(preferred_x):
		return preferred_x
	if has_ground_ahead(-preferred_x):
		return -preferred_x
	return 0.0


## 站在地面且当前朝向的前方探测不到地面（悬崖 / 平台边缘）时返回 true。
## 巡逻与战斗陆地移动都用它来避免踏空；飞行怪无 ledge_detector，恒为 false。
## 判定已改为按 move_direction 即时探测，语义不变，但不再受探测器换边时序影响。
func ledge_ahead() -> bool:
	if ledge_detector == null or not is_on_floor():
		return false
	return not has_ground_ahead(float(move_direction))
