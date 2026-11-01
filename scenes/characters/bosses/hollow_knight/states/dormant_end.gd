extends BossState
class_name HollowKnightDormantEndState

## 苏醒坠落：四根 BossChain 全被砍断后由 dormant 切进本状态。
## 播放 ActionAnimationPlayer 的 dormant_end 动画（挣脱锁链 → 下落 → 落地），
## 并在精灵第 9 帧（Rest Fall_001）起施加重力让本体下落，落到 Floor5 后停在落地姿态。
## 纯演出：落地后不做任何状态切换（见 BossStateNames.DORMANT_END 注释）。

## 第 9 帧开始下落（dormant_end 精灵帧序：0~7 Rest Break、8~9 Rest Fall、10~14 Rest Land）。
const FALL_FRAME := 9
## 落地姿态帧（Rest Land_004）。
const LAND_FRAME := 14
## 下落重力加速度（像素 / 秒²），与 GroundLocomotion 默认接近，可微调。
const GRAVITY := 2400.0

var _falling := false
var _landed := false
## 记录"开始下落那一刻是否已踩在地面"：出生即与 Floor5 重叠时 is_on_floor 起步为真，
## 不能拿它当落地判定（否则会瞬间判定已落地、看不到下落）；这种情况改由精灵播到落地帧再停。
var _on_floor_at_fall_start := false

func enter(_from: StringName) -> void:
	_falling = false
	_landed = false
	_on_floor_at_fall_start = false
	if boss == null or boss.animated_sprite == null:
		return
	# 让帧完全由 ActionAnimationPlayer 的轨道驱动，避免精灵自身播放与之打架。
	boss.animated_sprite.stop()
	boss.animated_sprite.animation = &"dormant_end"
	boss.animated_sprite.frame = 0
	if boss.action_animation_player != null:
		boss.action_animation_player.play("dormant_end")

func update(delta: float) -> void:
	if _landed:
		return

	# 第 9 帧才获得重力。
	if not _falling and boss.animated_sprite.frame >= FALL_FRAME:
		_falling = true
		_on_floor_at_fall_start = boss.is_on_floor()

	if _falling:
		boss.velocity.y += GRAVITY * delta
		boss._apply_movement()
		var landed := false
		if _on_floor_at_fall_start:
			landed = boss.animated_sprite.frame >= LAND_FRAME
		else:
			landed = boss.is_on_floor()
		if landed:
			_landed = true
			if boss.action_animation_player != null:
				boss.action_animation_player.stop()
			boss.animated_sprite.stop()
			boss.animated_sprite.frame = LAND_FRAME
			boss.velocity = Vector2.ZERO
	else:
		# 悬挂阶段：钉在原位，不调用 move_and_slide，避免被地形推走。
		boss.velocity = Vector2.ZERO
