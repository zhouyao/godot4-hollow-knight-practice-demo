extends AnimatedSprite2D

## 怪物受击特效（puff）。播完自动销毁，并带随机旋转/缩放。
## 可选随时间淡出：fade_out=true 时从 alpha 渐变到 0 再销毁。
## 淡出时长默认等于动画实际长度（可乘以 fade_duration_scale 微调）。

@export var rand_rot_min := -50.0
@export var rand_rot_max := 50.0
@export var rand_scale_min := 1
@export var rand_scale_max := 1.5
## 整体不透明度：1.0 = 完全不透明，0.0 = 完全透明（fade_out 开启时作为淡出起点）。
@export_range(0.0, 1.0) var alpha := 1.0
## 是否随时间淡出。true：从 alpha 渐变到 0 并随之销毁；false：播完动画直接销毁。
@export var fade_out := true
## 淡出时长 = 动画实际长度 × 此系数（1.0 表示淡出铺满整段动画）。
@export var fade_duration_scale := 1.0

## 按当前动画的帧时长与速度，算出播放一遍所需的实际秒数（已考虑 speed_scale）。
func _anim_length() -> float:
	var anim: StringName = animation
	if sprite_frames == null or not sprite_frames.has_animation(anim):
		return 0.0
	var total := 0.0
	var fc := sprite_frames.get_frame_count(anim)
	for i in fc:
		total += sprite_frames.get_frame_duration(anim, i)
	var fps := sprite_frames.get_animation_speed(anim)
	if fps <= 0.0:
		fps = 1.0
	return total / fps / maxf(0.0001, speed_scale)

func _ready() -> void:
	modulate.a = alpha
	rotation_degrees = randf_range(rand_rot_min, rand_rot_max)
	var s := randf_range(rand_scale_min, rand_scale_max)
	scale = Vector2(s, s)
	play("orange_pull_hit")
	if fade_out:
		var dur := maxf(0.01, _anim_length() * fade_duration_scale)
		var tw := create_tween()
		tw.tween_property(self, "modulate:a", 0.0, dur)
		tw.finished.connect(queue_free)
	else:
		animation_finished.connect(queue_free)
