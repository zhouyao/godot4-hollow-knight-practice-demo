extends WorldArea

## GrimmTent：马戏团帐篷，Boss 战场景。火把暖光 + grimmtent 环境音。

@onready var _ambience: AudioStreamPlayer = $Ambience/GrimmTent

@onready var _as1: AnimatedSprite2D = get_node_or_null(^"Forebackground/AnimatedSprite2D")
@onready var _as2: AnimatedSprite2D = get_node_or_null(^"Forebackground/AnimatedSprite2D2")
@onready var _as3: AnimatedSprite2D = get_node_or_null(^"Forebackground/AnimatedSprite2D3")

var _standalone_rig: Node = null
var _standalone_player: Node2D = null


func _ready() -> void:
	super._ready()
	if _ambience.stream is AudioStreamOggVorbis:
		(_ambience.stream as AudioStreamOggVorbis).loop = true
	_ambience.play()

	if get_tree().current_scene == self:
		_apply_camera_bounds_for_standalone()
		_standalone_rig = get_node_or_null(^"AuCameraRig")
		_standalone_player = get_node_or_null(^"Player")

	for as_node: AnimatedSprite2D in [_as1, _as2, _as3]:
		if as_node != null:
			as_node.play(&"default")

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
