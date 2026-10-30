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
## 走动中进入区域时是否立刻补一脚（沿用旧 MossFloor 的行为）。
## 出生 / 传送 / 空中掉入等"已重叠但没在走"的情况一律不补声。
@export var play_on_enter: bool = true
## 随机音高的上下限。
@export var pitch_min: float = 0.9
@export var pitch_max: float = 1.1
## 判定"在移动"的横向速度阈值（像素 / 秒）。
@export var move_epsilon: float = 1.0
## 音频总线名。
@export var bus: StringName = &"Sound"

@export_group("收声 Stop")
## 停步 / 离地 / 让出通道时是否立刻收掉当前这一步的音。
## 脚步音常常远长于 step_interval（如 player_waterwalk.ogg 长 1.5s，
## 而雨区 step_interval 只有 0.3s），任其播完就会出现
## "人都站住了，涉水声还继续响一秒钟"的拖尾。
@export var stop_when_idle: bool = true
## 收声时淡出的时长（秒）。0 = 立即硬切；短淡出可避免半途截断的爆音。
@export var idle_fade_time: float = 0.08


var _timer := 0.0
var _audio: AudioStreamPlayer2D
var _base_volume_db := 0.0
## 上一帧是否处于"在地面移动"状态：只在 移动 -> 静止 的跳变上收声，
## 这样站着进入区域时 play_on_enter 的那一脚（脚下溅水声）不会被立刻掐掉。
var _was_moving := false
var _fade: Tween


func _ready() -> void:
	super._ready()          # 基类在这里向宿主 AuZone 登记自己，别漏
	_audio = _get_or_create_audio()
	_audio.bus = bus
	_base_volume_db = _audio.volume_db


func on_entered(body: Node2D) -> void:
	_timer = 0.0
	if not play_on_enter:
		return
	# 只有"真的在地上迈着步"跨进来时才补这一脚。
	# 出生 / 传送 / 掉进区域时玩家往往悬空或站着不动，此时补声就会变成
	# "人还没动，先响一声脚步"（雨区出生即响涉水声）。
	if not _is_walking(body):
		return
	_play_step(body)


## 该 body 是否正处于"在地面且横向移动"的状态。
func _is_walking(body: Node2D) -> bool:
	var b := body as CharacterBody2D
	if b == null or not is_instance_valid(b):
		return false
	return b.is_on_floor() and absf(b.velocity.x) > move_epsilon


## 目标离开区域：直接把这最后一步的音收掉，否则会拖到音源播完。
func on_exited(_body: Node2D) -> void:
	_was_moving = false
	_stop_audio()


func on_gained(channel: StringName) -> void:
	if channel == &"surface":
		_timer = 0.0


func on_lost(channel: StringName) -> void:
	if channel != &"surface":
		return
	_timer = 0.0
	_was_moving = false
	_stop_audio()


func _physics_process(delta: float) -> void:
	var zone := get_zone()
	if zone == null or not zone.is_effective(&"surface"):
		_timer = 0.0
		_stop_after_move()
		return
	var body := zone.last_body() as CharacterBody2D
	if body == null or not is_instance_valid(body):
		return
	if not body.is_on_floor() or absf(body.velocity.x) <= move_epsilon:
		_stop_after_move()
		return
	_was_moving = true
	_timer += delta
	if _timer >= step_interval:
		_timer -= step_interval
		_play_step(body)


## 从"移动"掉到"静止/离地"时收声；一直没动过就不动它（保住 play_on_enter 那一脚）。
func _stop_after_move() -> void:
	if not _was_moving:
		return
	_was_moving = false
	_stop_audio()


## 收掉正在响的脚步音（带短淡出，避免半途硬切出爆音）。
func _stop_audio() -> void:
	if not stop_when_idle or _audio == null or not _audio.playing:
		return
	if _fade != null and _fade.is_valid():
		_fade.kill()
		_fade = null
	_audio.volume_db = _base_volume_db
	if idle_fade_time <= 0.0:
		_audio.stop()
		return
	_fade = create_tween()
	_fade.tween_property(_audio, "volume_db", _base_volume_db - 40.0, idle_fade_time)
	# 淡出结束后复位音量，否则下一脚会在 -40dB 起播（听不见）。
	_fade.tween_callback(func() -> void:
		_audio.stop()
		_audio.volume_db = _base_volume_db
	)


func _play_step(from_body: Node2D = null) -> void:
	if _audio == null or footstep_streams.is_empty():
		return
	if from_body != null and is_instance_valid(from_body):
		_audio.global_position = from_body.global_position
	# 若上一脚还在淡出，先掐掉淡出并把音量复位，否则新的一脚会从 -40dB 起播。
	if _fade != null and _fade.is_valid():
		_fade.kill()
	_fade = null
	_audio.volume_db = _base_volume_db
	_audio.stream = footstep_streams.pick_random()
	_audio.pitch_scale = randf_range(pitch_min, pitch_max)
	# 每个步点都重新起播：脚步音时长可能大于 step_interval。
	# 关键：对正在播放的 AudioStreamPlayer 直接 play() 不会重新开始（等于空操作），
	# 必须先 stop() 再 play()，否则长音频整段播完前会吞掉后续步点、跟不上脚步。
	_audio.stop()
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
