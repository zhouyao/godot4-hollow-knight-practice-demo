extends Enemy
class_name EnemyGround


## 巡逻总开关已上提到 Enemy 基类（地面怪与飞行怪共用），这里不再重复声明。

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
## 重写 Enemy 基类的默认实现（基类恒 true = 通行无阻，供飞行 / 水下怪沿用）。
## 与"当前朝向"解耦（只用传入的方向），并且每次即时查询而非读 RayCast2D 的缓存：
## 探测器会随翻面立刻换边，而 RayCast2D.is_colliding() 是上一物理帧的结果，
## 两者叠加会让追击状态在同一帧里"看着悬崖掉头、下一帧又掉回来"，形成逐帧左右翻面。
func has_ground_ahead(move_x: float) -> bool:
	if move_x == 0.0 or not is_on_floor():
		return true  # 空中不做悬崖限制
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


## 当前朝向前方是否撞墙（重写基类默认实现）。
## force_raycast_update()：RayCast2D 的碰撞结果是上一物理帧的缓存，查询前先按当前位置
## 刷新一次，免得读到"翻面前那一侧"的旧结果。探测器已由 _flip_extra() 跟着朝向换边。
func wall_ahead() -> bool:
	if wall_detector == null:
		return false
	wall_detector.force_raycast_update()
	return wall_detector.is_colliding()
