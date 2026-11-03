extends WorldTemplate

@onready var light: DirectionalLight2D = $Lights/DirectionalLight2D

# 缓存单个灯光 Tween，enter/exit 反复进出锁区时不叠加多个 create_tween()，
# 每次切换目标能量前先 kill 上一个还在跑的 tween。
var _light_tween: Tween = null

func _set_light_energy(target: float, duration := 2.0) -> void:
	if _light_tween != null and _light_tween.is_valid():
		_light_tween.kill()
	_light_tween = create_tween()
	_light_tween.tween_property(light, "energy", target, duration)

func _on_zoom_camera_lock_body_entered(_body: Node2D) -> void:
	_set_light_energy(3, 2.0)
	AuCameraDirector.shake_heavy()

func _on_zoom_camera_lock_body_exited(_body: Node2D) -> void:
	_set_light_energy(2, 2.0)

func _on_boss_camera_lock_body_entered(_body: Node2D) -> void:
	_set_light_energy(0, 2.0)

func _on_boss_camera_lock_body_exited(_body: Node2D) -> void:
	_set_light_energy(2, 2.0)
