extends WorldArea

## MossHole 关卡：环境音循环。其余（相机、换关、玩家）交给 GameSession 与模板。

@onready var _ambience: Array[AudioStreamPlayer] = [
	$Ambience/Stream,
	$Ambience/CicadaChirp,
]

var _standalone_rig: Node = null
var _standalone_player: Node2D = null


func _ready() -> void:
	super._ready()
	for player in _ambience:
		if player.stream is AudioStreamOggVorbis:
			(player.stream as AudioStreamOggVorbis).loop = true
		player.play()

	# F6 直接运行本场景时，GameSession 不在流程里，需要手动套相机边界并驱动相机跟随。
	if get_tree().current_scene == self:
		_apply_camera_bounds_for_standalone()
		_standalone_rig = get_node_or_null(^"AuCameraRig")
		_standalone_player = get_node_or_null(^"Player")


func _process(_delta: float) -> void:
	if _standalone_rig != null and is_instance_valid(_standalone_player):
		_standalone_rig.set_target_pos(_standalone_player.global_position)


func _apply_camera_bounds_for_standalone() -> void:
	var rig := get_node_or_null(^"AuCameraRig")
	var bounds := get_node_or_null(^"CameraBounds")
	if rig == null or bounds == null or not bounds.has_method(&"get_camera_limits"):
		return
	var limits: Rect2 = bounds.call(&"get_camera_limits", rig.zoom, get_viewport().get_visible_rect().size)
	if limits.size.x > 0.0 and limits.size.y > 0.0:
		rig.set_limits(int(limits.position.x), int(limits.position.y), int(limits.end.x), int(limits.end.y))
