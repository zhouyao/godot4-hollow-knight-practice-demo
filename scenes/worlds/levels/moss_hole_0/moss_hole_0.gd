extends WorldArea

## MossHole_0 关卡：环境音 + 进入湖泊区域后叠加 mossgrotto。

@onready var _ambience: Array[AudioStreamPlayer] = [
	$Ambience/Stream,
	$Ambience/CicadaChirp,
]
@onready var _grotto: AudioStreamPlayer = $Ambience/MossGrotto

var _grotto_started := false
var _standalone_rig: Node = null
var _standalone_player: Node2D = null


func _ready() -> void:
	super._ready()
	for player in _ambience:
		if player.stream is AudioStreamOggVorbis:
			(player.stream as AudioStreamOggVorbis).loop = true
		player.play()
	if _grotto.stream is AudioStreamOggVorbis:
		(_grotto.stream as AudioStreamOggVorbis).loop = true

	if get_tree().current_scene == self:
		_apply_camera_bounds_for_standalone()
		_standalone_rig = get_node_or_null(^"AuCameraRig")
		_standalone_player = get_node_or_null(^"Player")


func _process(_delta: float) -> void:
	var player := _standalone_player
	if player == null:
		player = get_tree().get_first_node_in_group(&"player") as Node2D

	if player != null and not _grotto_started and player.global_position.x < 1800.0:
		_grotto_started = true
		_grotto.play()

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
