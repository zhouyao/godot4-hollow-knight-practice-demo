extends Node

# 场景冒烟测试：确认每个场景都能入树并完成 _ready（@onready 路径、脚本引用均有效）。
# 运行：godot --headless --path . --scene res://tests/smoke.tscn --quit-after 60
# 注意：必须用 --scene 而不是 --script，后者不注册 autoload，脚本里的 Settings / UiAudio 无法解析。

const SCENES: Array[String] = [
	"res://scenes/menus/main_menu.tscn",
	"res://scenes/menus/default_menu.tscn",
	"res://scenes/menus/system_settings_menu.tscn",
	"res://scenes/menus/components/buttons/focus_button.tscn",
	"res://scenes/menus/components/buttons/reset_button.tscn",
	"res://scenes/menus/components/rows/key_binding_row.tscn",
	"res://scenes/menus/components/rows/volume_row.tscn",
]

var _passed := 0
var _failed := 0


func _ready() -> void:
	for path in SCENES:
		var packed := load(path) as PackedScene
		if packed == null:
			_check(false, "无法加载场景 %s" % path)
			continue
		var instance := packed.instantiate()
		if instance == null:
			_check(false, "无法实例化场景 %s" % path)
			continue
		add_child(instance)
		_check(instance.is_node_ready(), "场景入树并完成 _ready：%s" % path)
		if path.ends_with("system_settings_menu.tscn"):
			_check_structure(instance)
		instance.free()

	_check_localization()
	_check_locale_switch()
	_check_immediate_navigation()
	print("通过 %d 项，失败 %d 项" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


# 场景里的 text 依赖 Godot 的自动翻译，这里切到英文验证文案确实来自 translation 表
func _check_localization() -> void:
	var previous := TranslationServer.get_locale()
	TranslationServer.set_locale("en")
	var menu: Node = load("res://scenes/menus/default_menu.tscn").instantiate()
	add_child(menu)
	_check(menu.get_node("LogoContainer/ButtonContainer/StartButton").text == "Start", "主菜单按钮文案取自翻译表")
	menu.free()
	TranslationServer.set_locale(previous)


# 回归：语言可以在菜单里来回切。Tr 若把已经翻译过的文案当 key，切回中文就翻不回来了
func _check_locale_switch() -> void:
	var previous := TranslationServer.get_locale()
	var menu: Node = load("res://scenes/menus/default_menu.tscn").instantiate()
	add_child(menu)
	var button := menu.get_node("LogoContainer/ButtonContainer/StartButton") as Button

	TranslationServer.set_locale("en")
	Tr.apply(menu)
	_check(button.text == "Start", "切到英文后文案变成英文")

	TranslationServer.set_locale("zh_CN")
	Tr.apply(menu)
	_check(button.text == "开始", "切回中文能把英文文案翻回中文")

	menu.free()
	TranslationServer.set_locale(previous)


# 校验关键子节点挂的是预期脚本：UID 冲突会让场景错挂到另一个脚本上
func _check_structure(instance: Node) -> void:
	_check_theme(instance)

	var content := instance.get_node("Margin/Columns/ContentPanel")
	_check(content != null, "设置菜单内容面板路径有效")
	if content == null:
		return
	var up_row := content.get_node("OperationsContent/UpRow")
	var master_row := content.get_node("AudioContent/MasterRow")
	_check_node_script(up_row, KeyBindingRow)
	_check_node_script(master_row, VolumeRow)
	_check(up_row is MenuRow, "按键行继承自 MenuRow")
	_check(master_row is MenuRow, "音量行继承自 MenuRow")
	_check_reset_icon(master_row.get_node("Reset") as Button)
	_check_reset_icon(up_row.get_node("KeyboardReset") as Button)
	_check_language_option(content)


# 语言下拉框由 Settings.LOCALE_OPTIONS 生成，选中项必须落在当前语言上
func _check_language_option(content: Node) -> void:
	var option := content.get_node("LanguageContent/OptionRow/LanguageOption") as OptionButton
	_check(option != null, "语言下拉框路径有效")
	if option == null:
		return
	_check(option.item_count == Settings.LOCALE_OPTIONS.size(), "下拉框选项按 LOCALE_OPTIONS 生成")

	var current := Settings.get_locale()
	var index := Settings.LOCALE_OPTIONS.find(current)
	_check(option.selected == index, "下拉框选中项是当前语言")
	_check(option.get_item_text(index) == Settings.locale_display_name(current), "选项用语言自己的写法")
	_check(option.get_theme_font_size("font_size") == MistedTheme.FONT_SIZE_ROW_BUTTON,
		"下拉框字号取自 RowButton 变体")


# 回归：图标曾被压成一条缝。开了 expand_icon 后按钮的 minimum size 不再计入图标尺寸，
# 必须两轴都给足，否则重置按钮只剩边框那么高，图标看着像丢了
func _check_reset_icon(reset: Button) -> void:
	_check(reset == null or reset.icon != null, "重置按钮挂上了图标")
	if reset == null:
		return
	_check(reset.custom_minimum_size.y >= ResetButton.SIZE, "%s 留出了足够高度" % reset.name)
	_check(reset.get_rect().size.y >= ResetButton.SIZE, "%s 实际高度可以显示图标" % reset.name)


# 主题由带脚本的 Theme 注册 variation，加载失败会静默退回默认字号，这里显式验证
func _check_theme(instance: Control) -> void:
	var theme := instance.theme as MistedTheme
	_check(theme != null, "设置菜单挂上了 MistedTheme")
	if theme == null:
		return
	_check(theme.is_type_variation(MistedTheme.VARIATION_TITLE, "Label"), "TitleLabel 变体已注册")
	_check(theme.get_font_size("font_size", MistedTheme.VARIATION_TITLE) == MistedTheme.FONT_SIZE_TITLE,
		"标题字号取自主题")
	_check(theme.is_type_variation(MistedTheme.VARIATION_ROW_BUTTON, "Button"), "RowButton 变体已注册")


func _check_node_script(node: Node, expected: Script) -> void:
	_check(node != null and node.get_script() == expected, "%s 挂接脚本正确" % node.name)


# 回归：菜单动作必须由 pressed 直接驱动。若改成等音效放完再触发，点击后会有明显停滞感
func _check_immediate_navigation() -> void:
	var menu: Node = load("res://scenes/menus/default_menu.tscn").instantiate()
	add_child(menu)
	for path in [
		"LogoContainer/ButtonContainer/StartButton",
		"LogoContainer/ButtonContainer/SystemButton",
		"LogoContainer/ButtonContainer/QuitButton",
	]:
		var button := menu.get_node(path) as Button
		_check(!button.get_signal_connection_list("pressed").is_empty(),
			"%s 的 pressed 直接连到菜单动作" % button.name)
	menu.free()


func _check(condition: bool, description: String) -> void:
	if condition:
		_passed += 1
	else:
		_failed += 1
		print("失败：%s" % description)
