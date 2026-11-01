extends BossState
class_name HollowKnightDormantState

## 战前悬疑 BGM：按"剩余链条数"选轨。
##   剩 4 根（进入领地 / 未砍）→ PREFIGHT_TRACKS[0]（Suspence 1）
##   剩 3 根（砍 1）→ PREFIGHT_TRACKS[1]（Suspence 2）
##   剩 2 根（砍 2）→ PREFIGHT_TRACKS[2]（Suspence 3）
##   剩 1 根（砍 3）→ PREFIGHT_TRACKS[3]（Suspence 4）
##   剩 0 根（砍 4）→ 不播 PREFIGHT_TRACKS[4]，沿用上一轨进入苏醒演出。
const PREFIGHT_TRACKS: Array[AudioStream] = [
	preload("res://assets/sounds/characters/bosses/hollow_knight/background/Hollow Knight pre-fight - S61-161 Suspence 1.ogg"),
	preload("res://assets/sounds/characters/bosses/hollow_knight/background/Hollow Knight pre-fight - S61-161 Suspence 2.ogg"),
	preload("res://assets/sounds/characters/bosses/hollow_knight/background/Hollow Knight pre-fight - S61-161 Suspence 3.ogg"),
	preload("res://assets/sounds/characters/bosses/hollow_knight/background/Hollow Knight pre-fight - S61-161 Suspence 4.ogg"),
	preload("res://assets/sounds/characters/bosses/hollow_knight/background/Hollow Knight pre-fight - S61-161 Suspence 5.ogg"),
]

## 战前 BGM 播放器（hollow_knight.tscn 里 Boss 节点下的非定位 AudioStreamPlayer）。
var _music: AudioStreamPlayer
var _arena_connected := false

## 沉睡状态：玩家进入 BossArena 后，boss 的头会一直盯着玩家。
## 头动画在 EnemyAnimatedSprite 的 "dormant" 动画里，共 N 帧；
## 把竞技场的 x 方向按"动画实际帧数 N"均分成 N 段，玩家落在哪段就显示对应帧。
## 段数跟着素材走：以后给 dormant 动画加/减帧，这里无需改代码即自动适配。

## 帧序列方向：true = 帧 0 看最左、帧 N-1 看最右（素材 0.png~5.png 即此顺序）。
@export var frames_left_to_right: bool = true

var _arena: AuZone
var _sprite: AnimatedSprite2D
## dormant 动画的实际帧数，惰性从 SpriteFrames 读取（按动画帧数均分的关键）。
var _frame_count: int = 0


func enter(_from: StringName) -> void:
	_ensure_refs()
	_start_dormant_sprite()
	_track_head()
	_connect_chains()
	_connect_arena()
	_ensure_music()
	# 开战时停掉战前悬疑 BGM，避免与战斗 BGM 叠播（begin_fight → enter_combat）。
	if boss != null and not boss.enter_combat.is_connected(_on_boss_enter_combat):
		boss.enter_combat.connect(_on_boss_enter_combat)


func update(_delta: float) -> void:
	_track_head()


## 切到 dormant 动画并停住，由 _track_head 手动指定帧，避免自动循环播放。
func _start_dormant_sprite() -> void:
	if _sprite == null:
		return
	if _sprite.animation != &"dormant":
		_sprite.animation = &"dormant"
	_sprite.stop()


func _track_head() -> void:
	if _sprite == null or _arena == null:
		return
	var player := enemy.get_player()
	if player == null:
		return

	# 惰性取帧数：跟着动画素材走，不写死。
	if _frame_count <= 0 and _sprite.sprite_frames != null:
		_frame_count = _sprite.sprite_frames.get_frame_count(&"dormant")
	var count := _frame_count if _frame_count > 0 else 1

	var rect := _arena.global_rect()

	# 只按 x 方向判定（头左右转，与玩家高低无关）；竞技场 x 范围外则保持居中帧。
	if player.global_position.x < rect.position.x or player.global_position.x > rect.end.x:
		_sprite.frame = _neutral_frame(count)
		return

	# 把 [0,1] 的归一化位置按帧数 N 均分：每段等宽 1/N，floor 落帧。
	var t := clampf((player.global_position.x - rect.position.x) / rect.size.x, 0.0, 1.0)
	var frame := int(floorf(t * float(count)))
	frame = clampi(frame, 0, count - 1)
	if not frames_left_to_right:
		frame = count - 1 - frame
	_sprite.frame = frame


## 竞技场外的居中帧：count 为偶数时取中间偏右那帧（与 t=0.5 落在第 count/2 段一致）。
func _neutral_frame(count: int) -> int:
	return int(count / 2.0)


func _ensure_refs() -> void:
	if _sprite == null:
		_sprite = enemy.animated_sprite
	if _arena == null:
		_arena = enemy.get_node_or_null("BossArena") as AuZone
	if _sprite != null and _sprite.sprite_frames != null:
		_frame_count = _sprite.sprite_frames.get_frame_count(&"dormant")


## ---- 锁链断裂 → 触发 dormant_end ----
## level_1.tscn 里四根 BossChain 的 broke 信号没有接，这里自包含在 dormant 内扫描父节点
## HollowKnightScene 完成计数，满 4 根即切到 DORMANT_END。不动 level_1.tscn。
const TOTAL_CHAINS := 4
var _broken_count := 0
var _chains_connected := false

func _connect_chains() -> void:
	if _chains_connected:
		return
	var scene := enemy.get_parent()          # HollowKnightScene 节点
	if scene == null:
		return
	for child in scene.get_children():
		if child == enemy or not child.has_signal("broke"):
			continue
		child.broke.connect(_on_chain_broke)
	_chains_connected = true


## ---- 玩家踏入领地 → 播战前悬疑 1 号，并接好切轨 / 停播 ----
func _connect_arena() -> void:
	if _arena_connected or _arena == null:
		return
	if not _arena.player_entered.is_connected(_on_player_entered_arena):
		_arena.player_entered.connect(_on_player_entered_arena)
	if not _arena.player_exited.is_connected(_on_player_exited_arena):
		_arena.player_exited.connect(_on_player_exited_arena)
	_arena_connected = true
	# 开局玩家已站在领地内（时序不可靠）时，按当时链条数补播对应轨。
	for b in _arena.get_overlapping_bodies():
		if b.is_in_group("player"):
			_play_for_current_chains()
			break


func _on_player_entered_arena(_zone: Node, _player: Node2D) -> void:
	# 进入领地也按"当前已砍断的链条数"选轨（与砍链同一套映射；含 4 根全断则不播）。
	_play_for_current_chains()


## 按当前已砍断的链条数选轨：砍 0/1/2/3 根 → PREFIGHT_TRACKS[0/1/2/3]；4 根全断不播。
func _play_for_current_chains() -> void:
	if _broken_count < TOTAL_CHAINS:
		_play_track(_broken_count)


func _on_player_exited_arena(_zone: Node, _player: Node2D) -> void:
	_stop_music()


func _on_chain_broke() -> void:
	_broken_count += 1
	# 按"剩余链条数"选轨：剩 4/3/2/1 根（即砍断 0/1/2/3 根）→ PREFIGHT_TRACKS[0/1/2/3]。
	# 4 根全断（剩 0 根）不切到第 5 轨 PREFIGHT_TRACKS[4]，沿用上一轨进入苏醒演出。
	# 等价：砍断第 1~3 根才切到对应轨，砍断第 4 根不切轨。
	if _broken_count < TOTAL_CHAINS:
		_play_track(_broken_count)
	if _broken_count >= TOTAL_CHAINS:
		machine.set_state(BossStateNames.DORMANT_END)


## ---- 战前 BGM 播放器 ----
func _ensure_music() -> void:
	if _music != null and is_instance_valid(_music):
		return
	if boss == null:
		return
	_music = boss.get_node_or_null("PreFightMusic") as AudioStreamPlayer


## 切到指定战前悬疑轨（index 对应 PREFIGHT_TRACKS）。
## OGG 循环写到流上：背景悬疑音持续铺底，直到下一事件切轨或开战停播。
func _play_track(index: int) -> void:
	if _music == null or index < 0 or index >= PREFIGHT_TRACKS.size():
		return
	var stream: AudioStream = PREFIGHT_TRACKS[index]
	if stream == null:
		return
	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true
	_music.stream = stream
	_music.stop()
	_music.play()


func _on_boss_enter_combat(_target: Node2D) -> void:
	_stop_music()


func _stop_music() -> void:
	if _music != null and _music.playing:
		_music.stop()
