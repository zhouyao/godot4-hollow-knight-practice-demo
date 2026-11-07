extends CanvasLayer

## 开场动画：播放 Ogg Theora 视频，结束或点击「跳过」进入 MossHole。
##
## 根节点必须是 CanvasLayer：本场景由 GameSession 挂到 WorldHost 下，若用 Control
## 会跟着 2D 相机平移（开场时玩家在自由下落，镜头一走画面就没了）。
## layer=127 盖住游戏内所有 CanvasLayer（HUD=0、技能条=110、提示=115、
## 关卡标题/死亡遮罩=120），但低于 TransitionLayer(128)，淡入淡出仍在最上层。

const NEXT_SCENE := "res://scenes/worlds/levels/moss_hole/moss_hole.tscn"

@onready var _video: VideoStreamPlayer = $VideoViewport/SubViewport/Video
@onready var _skip: Button = $SkipButton

var _leaving := false


func _ready() -> void:
	_video.finished.connect(_leave)
	_skip.pressed.connect(_leave)
	Tr.apply(self)
	_pin_skip_pointer()
	# game_root 是黑场加载的，此时整棵树还处于 paused=true。
	# VideoStreamPlayer 默认 PROCESS_MODE_INHERIT，暂停时 play() 不会推进解码，
	# 等 game_root 解除暂停后再播，否则会表现为"动画不播"。
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	while get_tree().paused:
		await get_tree().process_frame
	if not is_instance_valid(self) or _leaving:
		return
	_video.play()


## 进入场景后让左右指针各播放一次浮出动画，播完停在展开帧常显；
## 同时断开 hover / 焦点对指针的移入移出控制。
func _pin_skip_pointer() -> void:
	await get_tree().process_frame

	for sig in [&"focus_entered", &"focus_exited", &"mouse_entered", &"mouse_exited"]:
		for conn in _skip.get_signal_connection_list(sig):
			var cb: Callable = conn["callable"]
			if _skip.is_connected(sig, cb):
				_skip.disconnect(sig, cb)

	# FocusMenuButton 只在 item_rect_changed 时摆指针，先手动按文字宽度定位。
	_skip.call(&"_layout_icons")

	for path in [^"FocusIconLeft", ^"FocusIconRight"]:
		var icon := _skip.get_node_or_null(path) as AnimatedSprite2D
		if icon == null:
			continue

		# FocusMenuButton 会在动画结束时把指针重新隐藏，先断开这条连接。
		for conn in icon.animation_finished.get_connections():
			icon.animation_finished.disconnect(conn["callable"])

		icon.visible = true
		var frames := icon.sprite_frames
		if frames == null or not frames.has_animation(&"pointer up"):
			continue

		icon.animation = &"pointer up"
		icon.frame = 0
		icon.stop()

		# 手动逐帧推进，放慢到 0.6 秒，结束时停在最后一帧。
		var count := frames.get_frame_count(&"pointer up")
		var tween := create_tween()
		tween.tween_method(func(v: float) -> void: icon.frame = int(v), 0.0, float(count - 1), 0.6)
		tween.tween_callback(func() -> void: icon.frame = count - 1)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		# 本层是子节点，先于 game_root 收到 Esc：吞掉它，避免同时打开暂停菜单
		# （暂停菜单 layer=100 会被本层挡住，玩家会停在 paused=true 里出不来）。
		get_viewport().set_input_as_handled()
		_leave()


func _leave() -> void:
	if _leaving:
		return
	_leaving = true
	_video.stop()
	Input.set_mouse_mode(Input.MOUSE_MODE_CONFINED_HIDDEN)

	# 正常流程从 game_root 进来时 current_area 已挂载，走 GameSession 的换关；
	# F6 直接跑本场景时没有 game_root，直接换场景，避免新关卡叠在当前场景下。
	if GameSession.current_area == null:
		get_tree().change_scene_to_file(NEXT_SCENE)
	else:
		GameSession.travel_to(NEXT_SCENE)
