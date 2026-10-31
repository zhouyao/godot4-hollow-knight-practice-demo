extends BossState
class_name HollowKnightDormantState

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
