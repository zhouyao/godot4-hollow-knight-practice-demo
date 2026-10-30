class_name EnemyAudio
extends RefCounted


## 敌人音效的收集、衰减参数与"此刻是否听得见"的判定。
##
## 原先散在 Enemy 里（约 40 行）。距离衰减两项（sfx_max_distance / sfx_attenuation）
## 是**配置**，留在 Enemy 的检查器面板上；这里只负责收集 Audio 子节点、套用参数、
## 以及"镜头可见性"这一条播放门禁。

## Audio 子节点表：键为节点名（attack / hurt / death / walk …），值为 AudioStreamPlayer2D。
var nodes: Dictionary = {}

var _enemy: Enemy


## 收集 Audio 子节点，并统一写入 2D 衰减参数（距离衰减由引擎做，音量随距离自然变轻）。
## 各敌人场景只需在 Audio 下挂 AudioStreamPlayer2D，距离参数在这里一次性接管。
func setup(enemy: Enemy) -> void:
	_enemy = enemy
	var audio_root := enemy.get_node_or_null("Audio")
	if audio_root == null:
		return
	for child in audio_root.get_children():
		nodes[child.name] = child
		if child is AudioStreamPlayer2D:
			child.max_distance = enemy.sfx_max_distance
			child.attenuation = enemy.sfx_attenuation


## 本敌人此刻是否"玩家该听得见"：以当前镜头的可视矩形（四周外扩 sfx_screen_margin）为准。
## 判定放在播放那一帧：屏幕外的敌人不发声，屏幕内的敌人照旧，且随距离自然衰减。
## 拿不到相机（还没进树 / 关卡没相机）时退化为"距玩家 sfx_max_distance 内可听"，避免整场静音。
func is_audible() -> bool:
	if not _enemy.sfx_only_on_screen:
		return true
	var rect := _audible_rect()
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return _within_sfx_distance()
	return rect.has_point(_enemy.global_position)


## 可听矩形：镜头中心 ± 半屏（按 zoom 折算）再外扩 sfx_screen_margin。
## 用 get_screen_center_position() 而不是 camera.global_position —— 相机被 limit 卡住时
## 两者不相等，前者才是真正的画面中心。
func _audible_rect() -> Rect2:
	var vp := _enemy.get_viewport()
	if vp == null:
		return Rect2()
	var cam := vp.get_camera_2d()
	if cam == null or cam.zoom.x <= 0.0 or cam.zoom.y <= 0.0:
		return Rect2()
	var half := vp.get_visible_rect().size * 0.5 / cam.zoom
	var screen_center := cam.get_screen_center_position()
	return Rect2(screen_center - half, half * 2.0).grow(_enemy.sfx_screen_margin)


## 无相机时的兜底判定：与玩家的距离在衰减半径内即可听。
func _within_sfx_distance() -> bool:
	var p := _enemy.get_player()
	if p == null:
		return true
	return _enemy.global_position.distance_to(p.global_position) <= _enemy.sfx_max_distance
