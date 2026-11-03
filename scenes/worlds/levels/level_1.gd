extends WorldTemplate

@onready var light: DirectionalLight2D = $Lights/DirectionalLight2D

# 缓存单个灯光 Tween，enter/exit 反复进出锁区时不叠加多个 create_tween()，
# 每次切换目标能量前先 kill 上一个还在跑的 tween。
var _light_tween: Tween = null

## BOSS 是否已击败：击败后踏入 BossCameraLock 不再压暗灯光（领地无效果）。
var _boss_defeated := false

func _ready() -> void:
	super._ready()
	# 监听 BOSS 击败：击败即锁定领地灯光效果，玩家之后重入领地不再变暗。
	var boss := get_node_or_null("HollowKnightScene/HollowKnight")
	if boss != null and boss.has_signal("boss_defeated") \
			and not boss.boss_defeated.is_connected(_on_boss_defeated):
		boss.boss_defeated.connect(_on_boss_defeated)

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
	if _boss_defeated:
		return
	_set_light_energy(0, 2.0)

func _on_boss_camera_lock_body_exited(_body: Node2D) -> void:
	if _boss_defeated:
		return
	_set_light_energy(2, 2.0)

## BOSS 击败：锁定领地灯光，并把当前可能已被压暗的灯光恢复到常态。
func _on_boss_defeated() -> void:
	_boss_defeated = true
	_set_light_energy(2, 0.5)
