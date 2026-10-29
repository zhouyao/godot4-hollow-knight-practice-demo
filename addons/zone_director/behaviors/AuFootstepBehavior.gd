extends AuZoneBehavior
class_name AuFootstepBehavior


## 地面脚步声挂件。
##
## 只在"宿主 AuZone 是当前 surface 通道的胜者"时发声 —— 这是嵌套互斥的关键：
## 雨区（surface=water）里套一片草区（surface=grass）时草地胜出；走出草区后
## 草区失去通道、雨区重新拿到，脚步声自动切回涉水声，全程无需任何特判。
##
## 本挂件不内置任何音频资源（插件不得引用 res://assets/**），
## 请在检查器里为 footstep_streams 赋值，或在所属场景里配好。


## 步点间隔（秒）。
@export var step_interval: float = 0.35
## 脚步音池：随机取一个 + 音高抖动，避免机械重复。
@export var footstep_streams: Array[AudioStream] = []
## 进入区域时是否立刻踩一脚（沿用旧 MossFloor 的行为）。
@export var play_on_enter: bool = true
## 随机音高的上下限。
@export var pitch_min: float = 0.9
@export var pitch_max: float = 1.1
## 判定"在移动"的横向速度阈值（像素 / 秒）。
@export var move_epsilon: float = 1.0
## 音频总线名。
@export var bus: StringName = &"Sound"


var _timer := 0.0
var _audio: AudioStreamPlayer2D


func _ready() -> void:
	super._ready()          # 基类在这里向宿主 AuZone 登记自己，别漏
	_audio = _get_or_create_audio()
	_audio.bus = bus


func on_entered(_body: Node2D) -> void:
	_timer = 0.0
	if play_on_enter:
		_play_step()


func on_gained(channel: StringName) -> void:
	if channel == &"surface":
		_timer = 0.0


func on_lost(channel: StringName) -> void:
	if channel != &"surface":
		return
	_timer = 0.0
	if _audio != null:
		_audio.stop()


func _physics_process(delta: float) -> void:
	var zone := get_zone()
	if zone == null or not zone.is_effective(&"surface"):
		_timer = 0.0
		return
	var body := zone.last_body() as CharacterBody2D
	if body == null or not is_instance_valid(body):
		return
	if not body.is_on_floor() or absf(body.velocity.x) <= move_epsilon:
		return
	_timer += delta
	if _timer >= step_interval:
		_timer -= step_interval
		_play_step()


func _play_step() -> void:
	if _audio == null or footstep_streams.is_empty():
		return
	_audio.stream = footstep_streams.pick_random()
	_audio.pitch_scale = randf_range(pitch_min, pitch_max)
	if not _audio.playing:
		_audio.play()


## 运行时自建播放器：挂件无需配套 .tscn 也能直接用（与 AuCameraLockArea
## 的 _get_or_create_collision() 同思路）。
func _get_or_create_audio() -> AudioStreamPlayer2D:
	for c in get_children():
		if c is AudioStreamPlayer2D:
			return c as AudioStreamPlayer2D
	var player := AudioStreamPlayer2D.new()
	player.name = "AudioStreamPlayer2D"
	add_child(player)
	return player
