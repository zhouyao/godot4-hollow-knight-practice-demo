class_name SettingsSection
extends RefCounted


var _store: SettingsStore
var _request_save: Callable


func _init(store: SettingsStore, request_save: Callable) -> void:
	_store = store
	_request_save = request_save


func load() -> void:
	pass


func save() -> void:
	_request_save.call()


func commit() -> void:
	save()


func reset() -> void:
	pass


func flush() -> void:
	pass
