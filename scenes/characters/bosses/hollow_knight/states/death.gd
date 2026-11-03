extends BossState
class_name HollowKnightDeathState

## 击败演出：先播 ActionAnimationPlayer/death（精灵逐帧定格死亡姿态），
## 随后 boss 缓慢向上升起、渐渐变淡，完全消失后于原死亡位置撒落钱币。
## 尸体不销毁（Boss._start_corpse_fade 为空），整场击败由本状态收尾。

## 向上升起的总位移（像素，向上为负）与持续时间（秒）。
const RISE_DISTANCE := -300.0
const RISE_TIME := 2.2
## 升空多久后开始变淡，以及从全亮到全透明所需的时长（秒）。
const FADE_DELAY := 0.9
const FADE_TIME := 1.4

var _elapsed := 0.0
var _risen := 0.0
var _dropped := false
var _spawn_at := Vector2.ZERO

func enter(_from: StringName) -> void:
	if boss == null:
		return
	# 击败期间不可再被攻击、不再走运动结算。
	boss.invincible = true
	boss.velocity = Vector2.ZERO
	# 精灵帧交给 ActionAnimationPlayer/death 轨道驱动（与 dormant_end 同款处理）。
	if boss.animated_sprite != null:
		boss.animated_sprite.stop()
		boss.animated_sprite.animation = &"death"
		boss.animated_sprite.frame = 0
	play_action(&"death")
	# 死亡音效：Audio/death。
	var sfx := boss.get_node_or_null("Audio/death") as AudioStreamPlayer2D
	if sfx != null:
		sfx.play()
	# 停止背景音乐（FightAudio 下的循环 BGM 与各 Chain 轨），避免击败后还在响。
	_stop_bgm()
	# 记录原死亡落点（升空前），掉落钱币用，避免钱币从半空冒出。
	_spawn_at = boss.drop_marker.global_position if boss.drop_marker != null else boss.global_position
	_elapsed = 0.0
	_risen = 0.0
	_dropped = false

func update(delta: float) -> void:
	if boss == null:
		return
	# 缓慢向上升起（匀速，封顶 RISE_DISTANCE）。
	if _elapsed < RISE_TIME:
		var step := (RISE_DISTANCE / RISE_TIME) * delta
		if absf(_risen + step) <= absf(RISE_DISTANCE):
			boss.global_position.y += step
			_risen += step
	# 升空一段时间后渐渐变淡。
	if _elapsed >= FADE_DELAY:
		var t := clampf((_elapsed - FADE_DELAY) / FADE_TIME, 0.0, 1.0)
		boss.modulate.a = 1.0 - t
	_elapsed += delta
	# 完全消失后：撒落钱币（仅一次），并关停碰撞体，避免隐形 boss 挡路。
	if not _dropped and _elapsed >= FADE_DELAY + FADE_TIME:
		_dropped = true
		_spawn_coins()
		_disable_collision()

func _spawn_coins() -> void:
	if boss == null:
		return
	boss.drop_loot(_spawn_at)

func _disable_collision() -> void:
	if boss == null:
		return
	var shape := boss.get_node_or_null("BodyCollisionShape2D") as CollisionShape2D
	if shape != null:
		shape.disabled = true

## 停止 Boss 背景音乐：FightAudio 下所有正在播放的音轨（boss_bg_loop / ChainX …）。
## 死亡音效在 Audio/death（不在 FightAudio 下），不受影响。
func _stop_bgm() -> void:
	if boss == null:
		return
	var fight_audio := boss.get_node_or_null("FightAudio") as Node2D
	if fight_audio == null:
		return
	for child in fight_audio.get_children():
		if child is AudioStreamPlayer2D and child.playing:
			child.stop()
