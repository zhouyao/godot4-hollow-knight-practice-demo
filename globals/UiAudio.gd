extends Node

# UI 音效统一播放：所有菜单控件共享一组播放器。
# 原先每个 FocusButton 各挂 2 个 AudioStreamPlayer，仅在按键设置一屏就有 24 个节点，
# 这里收拢成一对，既省节点也保证同一时刻只有一声在响。
# 注意：autoload 脚本不声明与 autoload 名同名的 class_name（Godot 会报 hides an autoload singleton）。

const SOUND_BUS := &"Sound"

const FOCUS_CHANGE_STREAM := preload("res://assets/sounds/menus/focus_change.wav")
const CONFIRM_STREAM := preload("res://assets/sounds/menus/confirm.wav")

var _focus_change: AudioStreamPlayer
var _confirm: AudioStreamPlayer


func _ready() -> void:
	_focus_change = _make_player(FOCUS_CHANGE_STREAM as AudioStream, "FocusChange")
	_confirm = _make_player(CONFIRM_STREAM as AudioStream, "Confirm")


func play_focus_change() -> void:
	_play(_focus_change)


func play_confirm() -> void:
	_play(_confirm)


func _play(player: AudioStreamPlayer) -> void:
	if player == null or player.stream == null:
		return
	if player.playing:
		player.stop()
	player.play()


func _make_player(stream: AudioStream, player_name: String) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.name = player_name
	player.stream = stream
	player.bus = SOUND_BUS
	add_child(player)
	return player
