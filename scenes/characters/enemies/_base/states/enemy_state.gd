extends State
class_name EnemyState


var _enemy: Enemy

var enemy: Enemy:
	get:
		if _enemy == null or not is_instance_valid(_enemy):
			_enemy = machine.host as Enemy if machine != null else null
		return _enemy

func update(delta: float) -> void:
	enemy._apply_vertical_motion(delta)
	enemy._apply_movement()

	enemy.try_hit_player()

## 播放动作动画：动画不存在（如未在 AnimationPlayer 里建 attack）时静默跳过，不刷错误。
func _play_action(anim_name: StringName) -> void:
	var player := enemy.action_animation_player
	if player == null or not player.has_animation(anim_name):
		return
	player.play(anim_name)

## 朝向迟滞（像素）：目标与自身的横向距离小于该值时保持当前朝向，不翻面。
## 不用 @export 是为了不给每个状态节点都塞一条多半用不上的检查器项；
## 需要改时在本文件或子类里直接改这个默认值即可。
var face_deadzone: float = 8.0

## 三级取值：tuning 预设 > 敌人根节点同名导出（逐只微调） > 状态自身的默认值。
## -1 或该属性不存在都表示"不覆盖，往下层要值"，所以不填任何字段的 tuning 等价于没配。
## 根节点代理之所以还需要保留：世界场景里改不了实例内部子节点，逐只微调只能落在根节点上。
func _tuning(property: StringName, fallback: float) -> float:
	if enemy == null:
		return fallback
	if enemy.tuning != null:
		var t: Variant = enemy.tuning.get(property)
		if t is float and t >= 0.0:
			return t
	var v: Variant = enemy.get(property)
	return float(v) if v is float and v >= 0.0 else fallback

## 基础移动速度（像素 / 秒）：tuning > 敌人根节点 move_speed。
## 各状态的 _patrol_speed / _chase_speed / _return_speed 一律乘它，
## 不要再直接读 enemy.move_speed —— 那会绕开 tuning，导致整类怪的预设失效。
func _move_speed() -> float:
	if enemy == null:
		return 0.0
	return _tuning(&"move_speed", enemy.move_speed)

## 站定：统一委托给运动介质（贴地只清 x，全向整体归零），见 EnemyLocomotion.apply_stop。
## 没有配 locomotion 时退化为"只清水平分量"，与地面怪一致。
func _stop() -> void:
	if enemy == null:
		return
	if enemy.locomotion != null:
		enemy.locomotion.apply_stop(enemy)
	else:
		enemy.velocity.x = 0.0

## 播放音效：先过"是否听得见"这一关 —— 屏幕外的敌人（隔着大半张地图追击、远远吐弹）
## 不该把攻击 / 受击 / 死亡声送进耳朵；屏幕内的声音仍由 AudioStreamPlayer2D 按距离衰减。
func _play_audio(key: StringName) -> void:
	if enemy == null or not enemy.is_audible():
		return
	var stream := enemy.audio_nodes.get(key) as AudioStreamPlayer2D
	if stream != null and stream.stream != null:
		stream.play()

func _flash_white(duration: float = -1.0) -> void:
	if enemy == null or not is_instance_valid(enemy.animated_sprite):
		return
	var d := enemy.invincible_time if duration <= 0.0 else duration
	enemy.animated_sprite.modulate = Color(4.0, 4.0, 4.0)
	var tween := enemy.animated_sprite.create_tween()
	tween.tween_property(enemy.animated_sprite, "modulate", Color.WHITE, d)

## 按左右方向（-1 / +1）设置朝向；只有方向真的改变时才翻面。
## 请优先用它，而不是"拿自身 x ± 1 当哨兵"的旧写法：后者把方向塞进距离里，
## 一旦迟滞/死区介入就会失效。
func _face_dir(dir_x: float) -> void:
	var desired := 1 if dir_x > 0.0 else -1
	if desired != enemy.move_direction:
		enemy._flip_direction()

## 面朝世界坐标 world_x：横向差小于 face_deadzone 时保持原朝向。
## 迟滞是必须的 —— 目标一旦与自己水平重合（例如站在正上方的平台上够不到），
## 直接取符号会在 ±1 之间逐帧抖动，敌人就会原地疯狂左右翻面。
func _face_target_x(world_x: float, deadzone: float = -1.0) -> void:
	var limit := face_deadzone if deadzone <= 0.0 else deadzone
	var dx := world_x - enemy.global_position.x
	if absf(dx) <= limit:
		return
	_face_dir(dx)
