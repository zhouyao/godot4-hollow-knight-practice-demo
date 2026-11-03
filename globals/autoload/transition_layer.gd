extends CanvasLayer

# 淡出期间冻结当前场景：否则退出关卡时，空中的角色会在黑场那 1 秒里继续下落、
# 甚至触发落地音。TransitionLayer 自身 process_mode = ALWAYS，暂停时过场照常播放。
var _busy := false

func change_scene(target: String) -> void:
	# 守卫：双击按钮 / 连按 Esc 会并发启动第二个协程，必须忽略重复触发
	if _busy:
		return
	_busy = true

	get_tree().paused = true

	$AnimationPlayer.play("fade_to_black")
	await $AnimationPlayer.animation_finished

	# 延迟切换场景；当前场景在下一帧才真正被替换
	get_tree().change_scene_to_file.bind(target).call_deferred()

	# 等待场景真正切换后再解除暂停，避免黑场期间暂停状态被提前还原
	await get_tree().scene_changed
	get_tree().paused = false

	# 场景已切换完成，立刻解除忙碌锁：否则锁会一直持续到淡出动画结束，
	# 导致返回主菜单后首次点击“设置”在黑场淡出期间被守卫丢弃、需再点一次。
	_busy = false

	$AnimationPlayer.play_backwards("fade_to_black")
	await $AnimationPlayer.animation_finished
