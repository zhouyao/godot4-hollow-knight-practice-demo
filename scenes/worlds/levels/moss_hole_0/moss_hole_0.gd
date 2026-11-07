extends WorldArea

## MossHole_0 关卡：环境音 + 进入湖泊区域后叠加 mossgrotto。
## 进入提示由 WorldArea 统一处理（本关场景里打开了 show_area_title）。

## 前景萤火虫（AnimatedSprite2D）：围着出生点乱飞 —— 随机冲刺 + 弹簧回拉 + 振翅抖动。
const DRIFT_RADIUS := 45.0 ## 允许乱飞的活动半径（像素），超出后被明显拉回
const DRIFT_STIFFNESS := 5.0 ## 回锚点的弹簧强度
const DRIFT_DAMPING := 3.6 ## 速度阻尼：越大每次冲刺衰减越快、飞得越近
const DRIFT_KICK_MIN := 50.0 ## 单次乱窜的初速度下限（像素/秒）
const DRIFT_KICK_MAX := 150.0 ## 单次乱窜的初速度上限（像素/秒）
const DRIFT_KICK_GAP_MIN := 0.2 ## 两次乱窜的最短间隔（秒）
const DRIFT_KICK_GAP_MAX := 0.5 ## 两次乱窜的最长间隔（秒）
const DRIFT_JITTER := 150.0 ## 悬停抖动加速度，模拟翅膀嗡嗡的细碎颤动
const DRIFT_MAX_SPEED := 160.0 ## 速度上限，防止多次冲刺叠加后失控


## 单只虫子的飞行状态：绕 origin 做带惯性的随机游走。
class DriftState:
	var sprite: AnimatedSprite2D
	var origin := Vector2.ZERO
	var velocity := Vector2.ZERO
	var kick_timer := 0.0
	var temper := 1.0 ## 个体差异：影响弹簧与抖动强度，让两只虫节奏不一样

@onready var _ambience: Array[AudioStreamPlayer] = [
	$Ambience/Stream,
	$Ambience/CicadaChirp,
]
@onready var _grotto: AudioStreamPlayer = $Ambience/MossGrotto

@onready var _as1: AnimatedSprite2D = $Forebackground/AnimatedSprite2D
@onready var _as2: AnimatedSprite2D = $Forebackground/AnimatedSprite2D2
@onready var _as3: AnimatedSprite2D = $Forebackground/AnimatedSprite2D3
@onready var _as4: AnimatedSprite2D = $Forebackground/AnimatedSprite2D4


var _grotto_started := false
var _standalone_rig: Node = null
var _standalone_player: Node2D = null
var _drifts: Array[DriftState] = []


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
	_as1.play()
	_as2.play()

	_setup_drift(_as1)
	_setup_drift(_as2)
	_setup_drift(_as3)
	_setup_drift(_as4)


func _process(delta: float) -> void:
	_update_drift(delta)

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


# ---------------------------------------------------------------- 前景萤火虫乱飞

## 让精灵以当前坐标为锚点，像小虫子一样在附近随机乱窜。
func _setup_drift(sprite: AnimatedSprite2D) -> void:
	if sprite == null:
		return
	var state := DriftState.new()
	state.sprite = sprite
	state.origin = sprite.position
	state.temper = randf_range(0.75, 1.35)
	state.kick_timer = randf_range(DRIFT_KICK_GAP_MIN, DRIFT_KICK_GAP_MAX)
	# 出生瞬间给一点初速度，两只虫不会同步起飞。
	state.velocity = _random_kick() * 0.6
	_drifts.append(state)


## 随机方向、随机力度的"猛蹿"一下。
func _random_kick() -> Vector2:
	var angle := randf() * TAU
	return Vector2(cos(angle), sin(angle)) * randf_range(DRIFT_KICK_MIN, DRIFT_KICK_MAX)


func _update_drift(delta: float) -> void:
	for state in _drifts:
		var sprite: AnimatedSprite2D = state.sprite
		if not is_instance_valid(sprite):
			continue

		# 每隔一小段随机时间就换个方向蹿一下：急停、急转、忽快忽慢都由它产生。
		state.kick_timer -= delta
		if state.kick_timer <= 0.0:
			state.kick_timer = randf_range(DRIFT_KICK_GAP_MIN, DRIFT_KICK_GAP_MAX)
			state.velocity = _random_kick()

		var offset := sprite.position - state.origin
		# 弹簧回拉；超出活动半径后额外加一股软墙拉力，虫子自己会拐回来。
		var pull := DRIFT_STIFFNESS + maxf(offset.length() - DRIFT_RADIUS, 0.0) * 30.0
		state.velocity -= offset * pull * state.temper * delta
		# 振翅抖动：悬停时也不完全静止，始终有细碎的颤动。
		state.velocity += Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * DRIFT_JITTER * state.temper * delta
		# 阻尼让每次冲刺自然衰减，形成"一下一下"的飞行节奏。
		state.velocity *= exp(-DRIFT_DAMPING * delta)
		state.velocity = state.velocity.limit_length(DRIFT_MAX_SPEED)
		sprite.position += state.velocity * delta
