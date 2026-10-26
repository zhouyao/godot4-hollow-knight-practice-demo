extends Node


const SOUND_BUS := &"Sound"

const FOCUS_CHANGE_STREAM := preload("res://assets/sounds/menus/focus_change.ogg")
const CONFIRM_STREAM := preload("res://assets/sounds/menus/confirm.ogg")

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
