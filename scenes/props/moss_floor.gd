extends Area2D
class_name MossFloor

## 草地 / 苔藓地面：玩家在本区域内移动 / 落地时，循环随机播放草地脚步音效。
## 音效由地面触发，与草本身无关（参考反馈 C）。

@export var step_interval: float = 0.35
@export var footstep_streams: Array[AudioStream] = []

var _player: CharacterBody2D = null

@onready var _timer: Timer = $StepTimer
@onready var _audio: AudioStreamPlayer2D = $AudioStreamPlayer2D

func _ready() -> void:
	if footstep_streams.is_empty():
		footstep_streams = [
			preload("res://assets/sounds/plants/grasswalk_0.ogg"),
			preload("res://assets/sounds/plants/grasswalk_1.ogg"),
			preload("res://assets/sounds/plants/grasswalk_2.ogg"),
		]
	_timer.wait_time = step_interval
	_timer.start()

func _on_body_entered(body: Node) -> void:
	if body.is_in_group("player"):
		_player = body
		_play_step()                       # 落地 / 进入即踩一脚

func _on_body_exited(body: Node) -> void:
	if body == _player:
		_player = null

func _on_step_timeout() -> void:
	if _player == null:
		return
	if _player.is_on_floor() and absf(_player.velocity.x) > 1.0:
		_play_step()

func _play_step() -> void:
	if footstep_streams.is_empty():
		return
	_audio.stream = footstep_streams.pick_random()
	_audio.pitch_scale = randf_range(0.9, 1.1)
	if not _audio.playing:
		_audio.play()
