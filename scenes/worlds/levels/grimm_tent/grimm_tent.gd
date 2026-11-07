extends WorldArea

## GrimmTent：马戏团帐篷，Boss 战场景。火把暖光 + grimmtent 环境音。

## 战斗 BGM：玩家进入 EnemyZones/AuZone 后才起播。
const BOSS_BGM_PATH := "res://assets/sounds/characters/bosses/accordion.ogg"
## 2D 声音的静音距离：引擎默认 2000 太远，按本关竞技场跨度收紧。
const BOSS_BGM_MAX_DISTANCE := 1500.0

@onready var _ambience: AudioStreamPlayer = $Ambience/GrimmTent
## 挂在 Forebackground/AnimatedSprite2D 下，用 2D 定位音频获得距离衰减。
var _boss_bgm: AudioStreamPlayer2D = null

@onready var _as1: AnimatedSprite2D = get_node_or_null(^"Forebackground/AnimatedSprite2D")
@onready var _as2: AnimatedSprite2D = get_node_or_null(^"Forebackground/AnimatedSprite2D2")
@onready var _as3: AnimatedSprite2D = get_node_or_null(^"Forebackground/AnimatedSprite2D3")
@onready var _as4: AnimatedSprite2D = get_node_or_null(^"Forebackground/AnimatedSprite2D4")
@onready var _as5: AnimatedSprite2D = get_node_or_null(^"Forebackground/AnimatedSprite2D5")

var _standalone_rig: Node = null
var _standalone_player: Node2D = null


func _ready() -> void:
	super._ready()
	if _ambience.stream is AudioStreamOggVorbis:
		(_ambience.stream as AudioStreamOggVorbis).loop = true
	_ambience.play()

	_boss_bgm = AudioStreamPlayer2D.new()
	_boss_bgm.name = "BossTheme"
	_boss_bgm.stream = load(BOSS_BGM_PATH)
	_boss_bgm.volume_db = 0
	_boss_bgm.bus = &"Music"
	# 2D 定位音频以相机为听者按距离衰减：挂到前景精灵下拿到稳定的世界声源坐标
	# （它不是视差层，不会随相机漂移）；默认 2000 太远，收紧后才听得出远近变化。
	_boss_bgm.max_distance = BOSS_BGM_MAX_DISTANCE
	_boss_bgm.attenuation = 1.0
	_boss_bgm.panning_strength = 0.0   # 循环 BGM 不随相机左右偏移声像
	var host: Node = self
	if _as1 != null:
		host = _as1
	host.add_child(_boss_bgm)
	# ogg 导入默认 loop=false，战斗 BGM 要循环（与环境音同一处理）。
	if _boss_bgm.stream is AudioStreamOggVorbis:
		(_boss_bgm.stream as AudioStreamOggVorbis).loop = true
	var boss_zone := get_node_or_null(^"EnemyZones/AuZone") as AuZone
	if boss_zone == null:
		push_warning("[GrimmTent] 找不到 EnemyZones/AuZone，战斗 BGM 不会触发")
	else:
		if not boss_zone.player_entered.is_connected(_on_boss_zone_entered):
			boss_zone.player_entered.connect(_on_boss_zone_entered)
		if not boss_zone.player_exited.is_connected(_on_boss_zone_exited):
			boss_zone.player_exited.connect(_on_boss_zone_exited)

	if get_tree().current_scene == self:
		_apply_camera_bounds_for_standalone()
		_standalone_rig = get_node_or_null(^"AuCameraRig")
		_standalone_player = get_node_or_null(^"Player")

	for as_node: AnimatedSprite2D in [_as1, _as2, _as3,_as4,_as5]:
		if as_node != null:
			as_node.play(&"default")


## 玩家踏入 EnemyZones/AuZone 时起播 / 恢复战斗 BGM；重复进出不叠播。
## AuZone 会在真实进入（含读档时开局已站在区域内）后补发本信号，无需再手动补查。
func _on_boss_zone_entered(_zone: Node, _player: Node2D) -> void:
	_boss_bgm.stream_paused = false
	if not _boss_bgm.playing:
		_boss_bgm.play()


## 离开区域：暂停播放（不停止），重新进入时恢复。
func _on_boss_zone_exited(_zone: Node, _player: Node2D) -> void:
	_boss_bgm.stream_paused = true


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
