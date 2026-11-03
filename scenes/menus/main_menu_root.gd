extends CanvasLayer

# 主菜单根层（main.tscn / main_menu.tscn 共用）：进入时确保鼠标可见。
# DefaultMenu 直接作为子节点实例化，脚本里不再 preload 别的场景。

func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	# 从游戏（鼠标受限/隐藏）返回时，鼠标模式切回“可见”后视口尚未就当前
	# 鼠标位置重建悬停状态；若鼠标正好停在“设置”上，不会触发 mouse_entered，
	# 首个点击就会被吞掉。延后一帧等 GUI 布局完成，再把鼠标 warp 到当前位置
	# 强制刷新悬停，确保首个点击正常命中按钮。
	await get_tree().process_frame
	Input.warp_mouse(get_viewport().get_mouse_position())
