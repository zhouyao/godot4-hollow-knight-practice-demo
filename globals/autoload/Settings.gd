extends Node


const SAVE_DEBOUNCE := 0.3

var _store := SettingsStore.new()

var volume: VolumeSection
var bindings: InputBindings
var localization: Localization
var skill_bar: SkillBarSection
var display: DisplaySection

var _sections: Array[SettingsSection] = []

var _save_timer: SceneTreeTimer = null


func _ready() -> void:
	var request_save := Callable(self, "request_save")
	volume = VolumeSection.new(_store, request_save)
	bindings = InputBindings.new(_store, request_save)
	localization = Localization.new(_store, request_save)
	skill_bar = SkillBarSection.new(_store, request_save)
	display = DisplaySection.new(_store, request_save)
	_sections = [volume, bindings, localization, skill_bar, display]

	if _store.load_config() != OK:
		volume.reset()

	for section in _sections:
		section.load()

	bindings.ensure_default_bindings()
	bindings.load()
	bindings.purge_reserved_bindings()

	TranslationServer.set_locale(localization.get_locale())

	get_tree().root.close_requested.connect(flush)


func request_save() -> void:
	if get_tree() == null:
		_flush_settings()
		return
	if _save_timer != null:
		_save_timer.time_left = SAVE_DEBOUNCE
		return
	_save_timer = get_tree().create_timer(SAVE_DEBOUNCE)
	_save_timer.timeout.connect(_flush_settings)


func flush() -> void:
	for section in _sections:
		section.flush()
	_flush_settings()


func _flush_settings() -> void:
	_save_timer = null
	var error := _store.save_config()
	if error != OK:
		push_warning("设置写入失败（%d）：%s" % [error, SettingsStore.SETTINGS_PATH])
