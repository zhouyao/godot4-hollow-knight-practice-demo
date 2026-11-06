extends WorldArea

## TearCity：内外两条环境音叠加，F6 单关调试时套用相机边界并跟随玩家。
## 背景里 4 团鬼火循环播放火焰动画，并以编辑器摆位为锚点缓慢四处飘荡。

## 鬼火飘荡参数：范围与节奏都在这里调。
const FIRE_ROAM := Vector2(220.0, 130.0) ## 相对锚点的漫游半径（像素）
const FIRE_FOLLOW := 0.5 ## 追向新目标点的柔和程度，越小飘得越慢
const FIRE_TURN_GAP := Vector2(1.6, 3.4) ## 换一次飘动方向的间隔（秒）
const FIRE_BOB := 9.0 ## 叠加的上下浮动幅度（像素）
const FIRE_BOB_SPEED := 1.4 ## 上下浮动速度
const FIRE_FLICKER := 0.07 ## 缩放脉动幅度，模拟火焰忽大忽小

## 单团火焰的飘荡状态：随机换目标点 + 平滑追踪 + 正弦浮动。
class FireDrift:
	var sprite: AnimatedSprite2D
	var anchor := Vector2.ZERO
	var follow := Vector2.ZERO ## 追踪后的位置，浮动再叠在它上面
	var target := Vector2.ZERO
	var turn_left := 0.0
	var phase := 0.0
	var base_scale := Vector2.ONE

@onready var _ambience: Array[AudioStreamPlayer] = [
	$Ambience/TeaCityInner,
	$Ambience/TeaCityOuter,
]
@onready var _fires: Array[AnimatedSprite2D] = [
	$Background/fire2,
	$Background/fire,
	$Background/fire3,
	$Background/fire4,
]

var _standalone_rig: Node = null
var _standalone_player: Node2D = null
var _fire_drifts: Array[FireDrift] = []
var _fire_time := 0.0


func _ready() -> void:
	super._ready()
	for player in _ambience:
		if player.stream is AudioStreamOggVorbis:
			(player.stream as AudioStreamOggVorbis).loop = true
		player.play()

	_setup_fire_drifts()

	if get_tree().current_scene == self:
		_apply_camera_bounds_for_standalone()
		_standalone_rig = get_node_or_null(^"AuCameraRig")
		_standalone_player = get_node_or_null(^"Player")


func _process(delta: float) -> void:
	_update_fire_drifts(delta)
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


# ---------------------------------------------------------------- 背景鬼火飘荡

## 以编辑器里的坐标为锚点，给每团火焰独立的相位、动画速度与起始帧。
func _setup_fire_drifts() -> void:
	for sprite in _fires:
		var state := FireDrift.new()
		state.sprite = sprite
		state.anchor = sprite.position
		state.follow = sprite.position
		state.target = sprite.position
		state.turn_left = randf_range(FIRE_TURN_GAP.x, FIRE_TURN_GAP.y)
		state.phase = randf() * TAU
		state.base_scale = sprite.scale
		# 节奏与帧错开，避免 4 团火焰像复制粘贴一样同步。
		sprite.speed_scale = randf_range(0.85, 1.15)
		if not sprite.is_playing():
			sprite.play(&"default")
		var frames := sprite.sprite_frames
		if frames != null and frames.has_animation(&"default"):
			sprite.frame = randi_range(0, frames.get_frame_count(&"default") - 1)
		_fire_drifts.append(state)


func _update_fire_drifts(delta: float) -> void:
	_fire_time += delta
	for state in _fire_drifts:
		var sprite: AnimatedSprite2D = state.sprite
		if not is_instance_valid(sprite):
			continue
		# 每隔一小段随机时间换个落脚点，慢悠悠地四处游走。
		state.turn_left -= delta
		if state.turn_left <= 0.0:
			state.turn_left = randf_range(FIRE_TURN_GAP.x, FIRE_TURN_GAP.y)
			state.target = state.anchor + Vector2(
				randf_range(-FIRE_ROAM.x, FIRE_ROAM.x),
				randf_range(-FIRE_ROAM.y, FIRE_ROAM.y))
		# 指数平滑追踪：靠近目标时自然减速，不会硬拐弯。
		state.follow = state.follow.lerp(state.target, 1.0 - exp(-FIRE_FOLLOW * delta))
		var t := _fire_time + state.phase
		sprite.position = state.follow + Vector2(
			sin(t * 0.7) * FIRE_BOB * 0.35,
			sin(t * FIRE_BOB_SPEED) * FIRE_BOB)
		# 轻微忽大忽小，配合帧动画更像燃烧的火。
		sprite.scale = state.base_scale * (1.0 + sin(t * 5.1) * FIRE_FLICKER + sin(t * 8.3) * FIRE_FLICKER * 0.5)
