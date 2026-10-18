## 真正执行导出 / 回滚的对象。被 plugin.gd 挂到 EditorUndoRedoManager 的 do/undo 上，
## 所以导出（含批量）可以在编辑器里 Ctrl+Z 一次撤销。
extends RefCounted

## 每个精灵一次导出留一张快照，批量时按数组顺序回滚
var _snapshots: Array[Dictionary] = []

## 返回给调用方显示的状态文本
var last_message := ""

## 上次导出的 SpriteFrames 动画总数
var last_count := 0

## 上一批处理涉及了多少个精灵
var last_sprites := 0


# --- do 方法（由 UndoRedo 调用）---

func do_export(player: AnimationPlayer, sprite: AnimatedSprite2D, settings: Dictionary) -> void:
	_begin()
	_export_one(player, sprite, settings)
	_finish()


func do_export_batch(sprites: Array, players: Array, settings: Dictionary) -> void:
	_begin()
	# 同一个 AnimationPlayer 被多个精灵共享时，重名的 idle/walk 会互相覆盖，
	# 给这些精灵加节点名前缀，例如 PlayerAnimatedSprite_walk；独占的不加。
	var shared := _count_per_player(players)
	for i in sprites.size():
		var player: AnimationPlayer = players[i] if i < players.size() else null
		var sprite: AnimatedSprite2D = sprites[i]
		var one := settings.duplicate()
		if sprite != null and _count_for(shared, player) > 1:
			one["prefix"] = sprite.name
		else:
			one["prefix"] = ""
		_export_one(player, sprite, one)
	_finish()


static func _count_per_player(players: Array) -> Dictionary:
	var counts: Dictionary = {}
	for p in players:
		if p == null:
			continue
		counts[p.get_instance_id()] = int(counts.get(p.get_instance_id(), 0)) + 1
	return counts


static func _count_for(counts: Dictionary, player: AnimationPlayer) -> int:
	if player == null:
		return 0
	return int(counts.get(player.get_instance_id(), 0))


func undo_export() -> void:
	for i in range(_snapshots.size() - 1, -1, -1):
		_restore_one(_snapshots[i])
	_snapshots.clear()


# --- 内部实现 ---

func _begin() -> void:
	_snapshots.clear()
	last_message = ""
	last_count = 0
	last_sprites = 0


func _export_one(player: AnimationPlayer, sprite: AnimatedSprite2D, settings: Dictionary) -> void:
	if player == null or sprite == null:
		return
	if sprite.sprite_frames == null:
		return

	var include := _filter_from(settings)
	var lib := SpriteFramesConverter.build_library(player, sprite, include)
	if lib == null or lib.get_animation_list().is_empty():
		return

	var prefix := String(settings.get("prefix", ""))
	var lib_name := StringName(settings.get("library", ""))
	var overwrite := bool(settings.get("overwrite", true))
	var stop_playback := bool(settings.get("stop_playback", true))

	var created_lib := not player.has_animation_library(lib_name)
	if created_lib:
		player.add_animation_library(lib_name, AnimationLibrary.new())
	var target := player.get_animation_library(lib_name)

	var snapshot := {
		"player": player,
		"sprite": sprite,
		"lib_name": lib_name,
		"created_lib": created_lib,
		"replaced": {},
		"added": [] as Array[StringName],
		"stopped": stop_playback,
		"autoplay": sprite.autoplay,
		# 4.7 起 AnimatedSprite2D 没有 playing 属性，播放状态只能读 is_playing() / 改 stop()
		"was_playing": sprite.is_playing(),
		"animation": sprite.animation,
		"frame": sprite.frame,
	}

	var added: Array[StringName] = []
	for raw_name in lib.get_animation_list():
		var anime := lib.get_animation(StringName(raw_name))
		var final_name := StringName(prefix + "_" + String(raw_name)) if prefix != "" else StringName(raw_name)
		if target.has_animation(final_name):
			if not overwrite:
				continue
			snapshot["replaced"][final_name] = target.get_animation(final_name)
			target.remove_animation(final_name)
		anime.resource_name = final_name
		target.add_animation(final_name, anime)
		added.append(final_name)
	snapshot["added"] = added

	if stop_playback:
		# 只在值真的变了才写，避免编辑器里刷 Setting-autoplay 告警
		if String(sprite.autoplay) != "":
			sprite.autoplay = ""
		if sprite.is_playing():
			sprite.stop()
		sprite.set_frame_and_progress(0, 0.0)

	last_count += added.size()
	last_sprites += 1
	_snapshots.append(snapshot)


func _restore_one(snapshot: Dictionary) -> void:
	var player := snapshot.get("player") as AnimationPlayer
	var sprite := snapshot.get("sprite") as AnimatedSprite2D
	if player == null:
		return

	var lib_name := snapshot.get("lib_name") as StringName
	if bool(snapshot.get("created_lib", false)):
		player.remove_animation_library(lib_name)
	elif player.has_animation_library(lib_name):
		var target := player.get_animation_library(lib_name)
		for anim_name in snapshot.get("added", []) as Array:
			if target.has_animation(anim_name):
				target.remove_animation(anim_name)
		for anim_name in (snapshot.get("replaced", {}) as Dictionary).keys():
			target.add_animation(anim_name, snapshot["replaced"][anim_name])

	if sprite != null and bool(snapshot.get("stopped", false)):
		var old_autoplay := StringName(snapshot.get("autoplay", &""))
		if old_autoplay != StringName(sprite.autoplay):
			sprite.autoplay = old_autoplay
		sprite.set_frame_and_progress(int(snapshot.get("frame", 0)), 0.0)
		if bool(snapshot.get("was_playing", false)):
			sprite.play(snapshot.get("animation", &"idle"))


func _finish() -> void:
	if _snapshots.is_empty():
		last_message = SpriteFramesI18n.t("export.nothing")
		return
	if last_sprites > 1:
		last_message = SpriteFramesI18n.t("export.batch", [last_sprites, last_count])
	else:
		last_message = SpriteFramesI18n.t("export.single", [last_count])
	print(SpriteFramesI18n.log_line(last_message))


func _filter_from(settings: Dictionary) -> Array[StringName]:
	if settings.has("animations"):
		var picked: Array[StringName] = []
		for raw in settings["animations"] as Array:
			picked.append(StringName(raw))
		return picked
	var single := StringName(settings.get("animation", ""))
	if single == StringName(""):
		return []
	return [single]
