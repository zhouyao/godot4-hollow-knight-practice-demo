class_name SettingsSection
extends RefCounted

# 设置项的统一抽象：每个子系统（音量 / 按键 / 语言，以及未来的画质、字幕…）
# 都继承本类，通过一致的 load / save / commit / reset / flush 接口接入 Settings 单例，
# 复用同一套去抖写盘调度，从而避免 Settings 单例随设置项增多而膨胀。
#
# _store 与 _request_save 由 Settings 在构造时注入：
# - _store：所有 section 共享的 SettingsStore，读写同一份 user://settings.cfg；
# - _request_save：请求 Settings 做一次去抖后的落盘，真正的写盘时机由 Settings 掌控。

var _store: SettingsStore
var _request_save: Callable


func _init(store: SettingsStore, request_save: Callable) -> void:
	_store = store
	_request_save = request_save


# 从存档加载并应用到运行时（AudioServer / InputMap / TranslationServer 等）
func load() -> void:
	pass


# 把当前内存状态写回 _store；真正落盘交给 _request_save 统一去抖调度
func save() -> void:
	_request_save.call()


# 一次“提交”结束（如滑条松手 / 静止超时）时收尾并落盘；默认等同 save()
func commit() -> void:
	save()


# 重置为默认值（写回 _store 并应用）
func reset() -> void:
	pass


# 退出前由 Settings 调用：取消本 section 内部仍在等待的提交计时器
func flush() -> void:
	pass
