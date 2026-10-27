extends Pickup
class_name CoinPickup


# 行为（下落 / 磁吸 / 累加进 Inventory）完全由 Pickup 基类承担，
# 保留子类只为了在 DropEntry 里按类型区分，以及后续扩展（如金币面额换贴图）。
#
# 这里负责表现层：按"是否在空中"切换动画，并把落到地上的金币抬出地面。

## 空中（抛出下落 / 弹跳 / 被吸附飞行）播 air，落地静止播 idle。
const ANIM_AIR := &"air"
const ANIM_IDLE := &"idle"

## 贴地后的微调（像素）：正数往下沉、负数往上抬。
## idle 帧画布若带透明边距，按帧高对齐后会显得悬空，用这个值手动找平。
@export var ground_offset_y: float = 0.0

@onready var _sprite: AnimatedSprite2D = $AnimatedSprite2D as AnimatedSprite2D


## 只重写这个虚钩子，不去碰 _ready() / _physics_process()：
## 基类在这两个回调里分别做了信号连接和运动积分，
## 子类一旦重写且忘了 super，基类的实现就永远不会执行（拾取与下落会直接失效）。
func _on_phase_changed(p: Phase) -> void:
	var want := _anim_of(p)
	var frames := _sprite.sprite_frames if _sprite != null else null
	if frames == null or not frames.has_animation(want):
		return
	# 已经在播这个动画就别再 play()，否则每次都会从头开始 = 永远停在第 0 帧。
	# 但对齐必须每次都做：IDLE → MAGNET → IDLE 时动画名没变，
	# 若在这里跟着一起 return，金币会停在半埋进地板的姿态。
	if _sprite.animation != want or not _sprite.is_playing():
		_sprite.play(want)
	_align_vertical(p, want)


## 阶段 → 动画名：只有落地静止（IDLE）才是 idle，
## SETTLE 下落与 MAGNET 吸附飞行都在动，一律算空中。
func _anim_of(p: Phase) -> StringName:
	return ANIM_IDLE if p == Phase.IDLE else ANIM_AIR


## 竖直对齐：基类把拾取原点（global_position.y）钉在探测到的地面高度上，
## 而 AnimatedSprite2D 默认以帧画布中心对齐原点 —— idle 帧的下半张必然埋进地板。
## 落地时把精灵上抬半个帧高，让画布底边正好贴住地面；
## 空中阶段恢复居中（下落 / 弹跳以中心触地更自然，吸附飞行时也不受地面约束）。
func _align_vertical(p: Phase, anim: StringName) -> void:
	if _sprite == null:
		return
	if p != Phase.IDLE:
		_sprite.position.y = 0.0
		return
	_sprite.position.y = -_frame_height(anim) * 0.5 + ground_offset_y


## 取动画首帧画布的像素高度：同一次导出的各帧尺寸一致，取第 0 帧即可。
## 运行时算而不是在场景里写死一个偏移量，换素材后不用回来改数字。
func _frame_height(anim: StringName) -> float:
	if _sprite == null:
		return 0.0
	var frames := _sprite.sprite_frames
	if frames == null or frames.get_frame_count(anim) <= 0:
		return 0.0
	var tex := frames.get_frame_texture(anim, 0)
	return float(tex.get_height()) if tex != null else 0.0
