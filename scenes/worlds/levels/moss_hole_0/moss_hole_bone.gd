extends StaticBody2D
class_name MossHoleBone

## 骨头堆：玩家踩上去时视觉下沉 5px，并播放骨头脚步声。
## 视觉贴图放在 Foreground，通过 visual_path 指过来。

@export var visual_path: NodePath
@export var sink_distance: float = 5.0
@export var sink_lerp: float = 0.1
@export var step_streams: Array[AudioStream] = []

const DEFAULT_STEP_STREAMS: Array[AudioStream] = [
	preload("res://assets/sounds/props/bonewalk_0.ogg"),
	preload("res://assets/sounds/props/bonewalk_1.ogg"),
	preload("res://assets/sounds/props/bonewalk_2.ogg"),
]

var _visual: Node2D
var _audio: AudioStreamPlayer2D
var _base_pos := Vector2.ZERO
var _target_pos := Vector2.ZERO


func _ready() -> void:
	_visual = get_node_or_null(visual_path) as Node2D
	if _visual != null:
		_base_pos = _visual.position
		_target_pos = _base_pos

	var area := get_node_or_null(^"StepArea") as Area2D
	if area != null:
		area.body_entered.connect(_on_step_area_body_entered)
		area.body_exited.connect(_on_step_area_body_exited)

	_audio = get_node_or_null(^"StepAudio") as AudioStreamPlayer2D
	if _audio == null:
		_audio = AudioStreamPlayer2D.new()
		_audio.name = "StepAudio"
		_audio.bus = &"Sound"
		add_child(_audio)

	if step_streams.is_empty():
		step_streams = DEFAULT_STEP_STREAMS


func _process(_delta: float) -> void:
	if _visual != null:
		_visual.position = _visual.position.lerp(_target_pos, sink_lerp)


func _on_step_area_body_entered(body: Node2D) -> void:
	if not body.is_in_group(&"player"):
		return
	_target_pos = _base_pos + Vector2(0.0, sink_distance)
	if _audio != null and not step_streams.is_empty():
		_audio.stream = step_streams.pick_random()
		_audio.pitch_scale = randf_range(0.9, 1.1)
		_audio.play()


func _on_step_area_body_exited(body: Node2D) -> void:
	if body.is_in_group(&"player"):
		_target_pos = _base_pos
