extends StaticBody2D
class_name MossFloor

## 苔藓地面：玩家踩上去时视觉贴图轻微下压，并播放草脚步声。
## 视觉贴图放在 Foreground，通过 visual_path 指过来（本节点自身只负责碰撞与检测）。

@export var visual_path: NodePath
## 踩踏时 y 轴压到的比例（源项目 aim = 0.85）。
@export var squash_ratio: float = 0.85
## 每帧向目标缩放插值的系数（源项目 0.0875）。
@export var squash_lerp: float = 0.0875
## 脚步声池；留空时使用项目已导入的 grasswalk_0..2。
@export var step_streams: Array[AudioStream] = []

const DEFAULT_STEP_STREAMS: Array[AudioStream] = [
	preload("res://assets/sounds/plants/grasswalk_0.ogg"),
	preload("res://assets/sounds/plants/grasswalk_1.ogg"),
	preload("res://assets/sounds/plants/grasswalk_2.ogg"),
]

var _visual: Node2D
var _audio: AudioStreamPlayer2D
var _base_scale := Vector2.ONE
var _target_scale_y := 1.0


func _ready() -> void:
	_visual = get_node_or_null(visual_path) as Node2D
	if _visual != null:
		_base_scale = _visual.scale
		_target_scale_y = _base_scale.y

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
	if _visual == null:
		return
	var s := _visual.scale
	s.y = lerpf(s.y, _target_scale_y, squash_lerp)
	_visual.scale = s


func _on_step_area_body_entered(body: Node2D) -> void:
	if not body.is_in_group(&"player"):
		return
	_target_scale_y = _base_scale.y * squash_ratio
	if _audio != null and not step_streams.is_empty():
		_audio.stream = step_streams.pick_random()
		_audio.pitch_scale = randf_range(0.9, 1.1)
		_audio.play()


func _on_step_area_body_exited(body: Node2D) -> void:
	if body.is_in_group(&"player"):
		_target_scale_y = _base_scale.y
