extends BossState
class_name HollowKnightDormantEndState

## 苏醒坠落：四根 BossChain 全被砍断后由 dormant 切进本状态。
## 入场先上提 RISE_HEIGHT 像素（挣脱锁链的蓄力），再转入重力坠落并落到地面。

## 下落重力加速度（像素 / 秒²），与 GroundLocomotion 默认接近，可微调。
const GRAVITY := 2400.0
## 入场先抬升的高度（像素）与抬升速度（像素/秒）。
const RISE_HEIGHT := 200.0
const RISE_SPEED := 600.0
## 落地后停留时长（秒）：让落地音效 / 战斗 BGM 等收尾，再进入 scream。
const LAND_TO_SCREAM_DELAY := 2.0

enum _Phase { RISING, FALLING }

var _phase := _Phase.RISING
var _rise_remaining := 0.0
var _landed := false
var _land_timer := 0.0
var _falling: = false

func enter(_from: StringName) -> void:
	AuCameraDirector.shake_medium()
	# 苏醒坠落演出期间仍不可被玩家攻击，直到本状态结束进入 scream。
	if boss != null:
		boss.invincible = true
	_landed = false
	_falling = false
	_land_timer = 0.0
	_phase = _Phase.RISING
	_rise_remaining = RISE_HEIGHT
	if boss == null or boss.animated_sprite == null:
		return
	boss.velocity = Vector2.ZERO
	# 让帧完全由 ActionAnimationPlayer 的轨道驱动，避免精灵自身播放与之打架。
	boss.animated_sprite.stop()
	boss.animated_sprite.animation = &"dormant_end"
	boss.animated_sprite.frame = 0
	play_action(&"dormant_end")

func update(delta: float) -> void:
	if boss == null:
		return
	if _landed:
		# 落地后停留 2 秒（让落地音效 / 战斗 BGM 等收尾），再进入 scream。
		_land_timer += delta
		if _land_timer >= LAND_TO_SCREAM_DELAY and goto_if_current(BossStateNames.SCREAM):
			# 这里不解锁：scream 仍属于过场（见 Boss.is_cutscene_invulnerable），
			# 真正的解锁收口在 idle.enter() —— 过场全部播完才算"可以攻击"。
			var bg_loop := boss.get_node_or_null("FightAudio/boss_bg_loop") as AudioStreamPlayer2D
			if bg_loop != null and not bg_loop.playing:
				bg_loop.play()
		return
	match _phase:
		_Phase.RISING:
			# 先上提 RISE_HEIGHT 像素（蓄力），到位后转入下落。
			var step := RISE_SPEED * delta
			if step >= _rise_remaining:
				boss.global_position.y -= _rise_remaining
				_rise_remaining = 0.0
				_phase = _Phase.FALLING
			else:
				boss.global_position.y -= step
				_rise_remaining -= step
		_Phase.FALLING:
			if _falling :
				boss.velocity.y += GRAVITY * delta
				boss._apply_movement()
				# 落到地面即停（不依赖动画轨道的 landed() 时机，避免抬升后悬空）。
				if boss.is_on_floor():
					_landed = true

func falling() -> void:
	_falling = true
	AuCameraDirector.shake_heavy()
