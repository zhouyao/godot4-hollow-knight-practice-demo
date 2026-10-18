## 把 AnimatedSprite2D 的 SpriteFrames 转成 AnimationPlayer 的 Animation。
## 每条 SpriteFrames 动画 → 一个同名 Animation，内含两条离散数值轨道：
##   <sprite>:animation  切到同名精灵动画（关键帧在 t=0）
##   <sprite>:frame      逐帧关键帧，时间轴按 duration / fps 铺开
class_name SpriteFramesConverter
extends RefCounted


## player: 目标 AnimationPlayer（轨道路径按它的 root_node 计算）
## sprite: 数据来源与目标 AnimatedSprite2D
## include: 留空表示全部精灵动画，否则只导出列出的那些
static func build_library(
	player: AnimationPlayer,
	sprite: AnimatedSprite2D,
	include: Array[StringName] = []
) -> AnimationLibrary:
	if sprite == null or sprite.sprite_frames == null:
		push_error(SpriteFramesI18n.t("err.no_frames"))
		return null

	var lib := AnimationLibrary.new()
	var sprite_path := _track_path(player, sprite)
	for raw_name in sprite.sprite_frames.get_animation_names():
		var anim_name := StringName(raw_name)
		if not include.is_empty() and not include.has(anim_name):
			continue
		var anime := build_animation(sprite.sprite_frames, anim_name, sprite_path)
		if anime != null:
			lib.add_animation(anim_name, anime)
	return lib


static func build_animation(frames: SpriteFrames, anim_name: StringName, sprite_path: NodePath) -> Animation:
	var count := frames.get_frame_count(anim_name)
	if count <= 0:
		return null

	var fps := maxf(frames.get_animation_speed(anim_name), 0.01)

	var anime := Animation.new()
	anime.resource_name = anim_name
	anime.loop_mode = Animation.LOOP_LINEAR if frames.get_animation_loop(anim_name) else Animation.LOOP_NONE

	var anim_track := anime.add_track(Animation.TYPE_VALUE)
	anime.track_set_path(anim_track, NodePath("%s:animation" % sprite_path))
	anime.value_track_set_update_mode(anim_track, Animation.UPDATE_DISCRETE)
	anime.track_insert_key(anim_track, 0.0, anim_name)

	var frame_track := anime.add_track(Animation.TYPE_VALUE)
	anime.track_set_path(frame_track, NodePath("%s:frame" % sprite_path))
	anime.value_track_set_update_mode(frame_track, Animation.UPDATE_DISCRETE)

	var time := 0.0
	for i in count:
		anime.track_insert_key(frame_track, time, i)
		time += frames.get_frame_duration(anim_name, i) / fps
	anime.length = time
	return anime


static func _track_path(player: AnimationPlayer, sprite: AnimatedSprite2D) -> NodePath:
	var root := player.get_node_or_null(player.root_node)
	if root == null:
		push_error(SpriteFramesI18n.t("err.no_root"))
		return NodePath("")
	return root.get_path_to(sprite)
