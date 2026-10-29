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
## 转发到 Enemy._play_action() —— 播放逻辑只在那里写一份。
func _play_action(anim_name: StringName) -> void:
	if enemy == null:
		return
	enemy._play_action(anim_name)

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

## ---- 朝向 / 位移：一律委托给 Enemy，状态不要再自己算一遍 ----
## 以前每个状态各算一次"朝哪 / 往哪走"，chase 甚至用两套判据（朝向按死区、位移按导航），
## 目标在正上 / 正下方时给出相反答案 → "walk 动画朝向反了"。
## 现在判据只有一份（EnemySteering.step_x，有单测覆盖），状态只负责提供"目标 x"。

## 朝向死区取值：tuning > 敌人根节点 face_deadzone。返回 -1 = 交给敌人根节点的默认值。
func _deadzone() -> float:
	return _tuning(&"face_deadzone", -1.0)

## 朝目标走一步：翻面 + 横移由 Enemy 统一裁决（朝向与位移同源，不可能倒着走）。
## 返回本帧实际步向（±1，0 = 站定：目标在死区内，或贴地怪前方踏空）。
func _step_toward(target_x: float, speed: float) -> int:
	var step := enemy.decide_step_x(target_x, _deadzone())
	enemy.apply_step(step, speed)
	return step

## 只朝向目标、不移动（站定吐弹、够不到目标时的张望）。带死区，目标在正上方时不抖动翻面。
func _face_toward(target_x: float) -> void:
	enemy.face_toward(target_x, _deadzone())
