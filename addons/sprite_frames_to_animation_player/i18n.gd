## 插件文案的多语言字典，跟随「编辑器设置 → 界面 → 编辑器语言」切换。
##
## 为什么自己带字典、不用 tr()/TranslationServer：
## 项目自带的 translations.*.translation 是给游戏运行时用的，加载与否由项目设置决定；
## 而插件跑在编辑器里，要求的是「跟着编辑器界面语言走」，
## 所以这里直接读 interface/editor/editor_language，再在自己的字典里查表。
##
## 只支持简体中文与英文：locale 以 zh 开头算中文，其余一律回落英文。
@tool
class_name SpriteFramesI18n
extends RefCounted

const EN := "en"
const ZH := "zh_CN"

## 4.7 里这个设置项在界面上叫「编辑器语言」，新旧两个路径都存在（实测值相同），都试一遍。
## 值为 "auto" 时表示跟随系统，得继续往下走兜底。
const LANGUAGE_SETTINGS: Array[String] = [
	"interface/editor/editor_language",
	"interface/editor/localization/editor_language",
]

## "auto" / 空串都表示「没指定」，交给工具语言兜底
const AUTO_VALUES: Array[String] = ["", "auto"]

## 文案表：key -> { "en": …, "zh_CN": … }。
## 缺 key 时原样返回 key，缺语言时回落英文，不会把界面翻成空串。
const TEXTS: Dictionary = {
	# --- 菜单 / 工具入口 ---
	"tool.menu": {
		"en": "Import SpriteFrames to AnimationPlayer",
		"zh_CN": "导入 SpriteFrames 到 AnimationPlayer",
	},
	"menu.import_to": {
		"en": "Import SpriteFrames → %s",
		"zh_CN": "导入 SpriteFrames → %s",
	},
	"menu.import_multi": {
		"en": "Import SpriteFrames…（%d selected, pick target in dialog）",
		"zh_CN": "导入 SpriteFrames…（多选 %d 个，目标在对话框里选）",
	},
	"menu.no_sprite": {
		"en": "Import SpriteFrames（no AnimatedSprite2D in scene）",
		"zh_CN": "导入 SpriteFrames（场景里没有 AnimatedSprite2D）",
	},

	# --- 对话框 ---
	"dialog.title": {
		"en": "SpriteFrames → AnimationPlayer",
		"zh_CN": "SpriteFrames → AnimationPlayer",
	},
	"dialog.ok": {"en": "Import", "zh_CN": "导入"},
	"dialog.cancel": {"en": "Cancel", "zh_CN": "取消"},
	"row.target_player": {
		"en": "Target AnimationPlayer",
		"zh_CN": "目标 AnimationPlayer",
	},
	"row.source_sprite": {
		"en": "Source AnimatedSprite2D",
		"zh_CN": "来源 AnimatedSprite2D",
	},
	"check.batch_all": {
		"en": "Apply to every AnimatedSprite2D in the scene (one target each)",
		"zh_CN": "对场景里所有 AnimatedSprite2D 同样处理（可各指定目标）",
	},
	"label.animations": {"en": "Animations to import", "zh_CN": "要导入的动画"},
	"button.select_all": {"en": "Select all", "zh_CN": "全选"},
	"button.select_none": {"en": "Select none", "zh_CN": "全不选"},
	"label.library": {"en": "Target animation library", "zh_CN": "目标动画库"},
	"col.pick": {"en": "Pick", "zh_CN": "选择"},
	"col.library": {"en": "Library", "zh_CN": "动画库"},
	"col.count": {"en": "Count", "zh_CN": "条数"},
	"col.content": {"en": "Content", "zh_CN": "内容"},
	"check.overwrite": {
		"en": "Overwrite animations with the same name",
		"zh_CN": "覆盖同名动画",
	},
	"check.stop_playback": {
		"en": "Stop the sprite's own playback (clear autoplay)",
		"zh_CN": "停掉精灵自身播放（清掉 autoplay）",
	},
	"tip.stop_playback": {
		"en": "Required once the AnimationPlayer takes over, otherwise both fight over frame",
		"zh_CN": "交给 AnimationPlayer 后必须关掉，否则两边会抢 frame",
	},
	"option.no_sprite": {
		"en": "（no AnimatedSprite2D in the scene）",
		"zh_CN": "（场景里没有 AnimatedSprite2D）",
	},
	"lib.global": {"en": "<global>", "zh_CN": "<global>"},
	"content.empty_new": {
		"en": "（empty, created on import）",
		"zh_CN": "（空，导入时新建）",
	},
	"content.empty": {"en": "（empty）", "zh_CN": "（空）"},
	"detail.lib_missing": {
		"en": "This library does not exist yet, it will be created on import.",
		"zh_CN": "这个库还不存在，导入时会新建。",
	},
	"detail.lib_empty": {
		"en": "This library is empty, import will add animations to it.",
		"zh_CN": "这个库是空的，导入会往里加动画。",
	},
	"detail.existing": {
		"en": "Existing animations: %s",
		"zh_CN": "现有动画：%s",
	},
	"detail.checked_exists": {
		"en": "Checked %s already exist%s",
		"zh_CN": "勾选的 %s 已存在%s",
	},
	"detail.will_overwrite": {"en": ", will be overwritten", "zh_CN": "，会被覆盖"},
	"detail.will_skip": {
		"en": ", will be skipped because overwrite is off",
		"zh_CN": "，未勾覆盖所以会被跳过",
	},
	"hint.no_animation": {
		"en": "No animations to import.",
		"zh_CN": "没有可导入的动画。",
	},
	"hint.none_picked": {
		"en": "%d candidates, none checked.",
		"zh_CN": "候选 %d 条，当前未勾选任何动画。",
	},
	"hint.picked": {
		"en": "%d / %d animations checked \n Import writes them into %s's library 「%s」",
		"zh_CN": "已勾选 %d / %d 条动画 \n 点击导入后写入 %s 的「%s」库",
	},
	"value.unspecified": {"en": "unspecified", "zh_CN": "未指定"},
	"value.no_library": {"en": "no library picked", "zh_CN": "未选库"},
	"describe.anim": {"en": "%s: %d frames / %.2fs%s", "zh_CN": "%s：%d 帧 / %.2fs%s"},
	"describe.non_loop": {"en": "（non-looping）", "zh_CN": "（非循环）"},

	# --- 报错 ---
	"err.no_frames": {
		"en": "SpriteFramesConverter: sprite or sprite_frames is null",
		"zh_CN": "SpriteFramesConverter: sprite 或 sprite_frames 为空",
	},
	"err.no_root": {
		"en": "SpriteFramesConverter: root_node of the AnimationPlayer not found",
		"zh_CN": "SpriteFramesConverter: 找不到 AnimationPlayer 的 root_node",
	},

	# --- 导出结果 ---
	"export.nothing": {
		"en": "No SpriteFrames animations to export",
		"zh_CN": "没有可导出的 SpriteFrames 动画",
	},
	"export.batch": {
		"en": "%d sprites handled, %d animations exported",
		"zh_CN": "已导出 %d 个精灵的 %d 条动画",
	},
	"export.single": {"en": "Exported %d animations", "zh_CN": "已导出 %d 条动画"},

	# --- Output 日志 ---
	"log.prefix": {"en": "[SpriteFrames→AnimationPlayer]", "zh_CN": "[SpriteFrames→AnimationPlayer]"},
	"log.plugin_loaded": {"en": "plugin loaded", "zh_CN": "插件已加载"},
	"log.menu_bound": {"en": "hooked into the scene tree context menu", "zh_CN": "已挂上场景树右键菜单"},
	"log.menu_fallback": {
		"en": "scene tree context menu not found, falling back to EditorContextMenuPlugin",
		"zh_CN": "没找到场景树右键菜单，回退到 EditorContextMenuPlugin",
	},
	"log.no_scene": {"en": "no scene is being edited", "zh_CN": "没有正在编辑的场景"},
	"log.no_player": {"en": "no AnimationPlayer in the scene", "zh_CN": "场景里没有 AnimationPlayer"},
	"log.no_sprite": {
		"en": "no AnimatedSprite2D in the scene, nothing to import",
		"zh_CN": "场景里没有 AnimatedSprite2D，无从导入。",
	},
	"log.nothing_picked": {
		"en": "target, sprite or animations are empty, nothing imported",
		"zh_CN": "目标、精灵或动画为空，未导入",
	},
	"log.dialog_open": {"en": "dialog opened: %s, %d candidate sprites", "zh_CN": "打开对话框：%s，候选精灵 %d 个"},
	"log.lib_fallback": {
		"en": "target AnimationPlayer unresolved, library list falls back to <global>",
		"zh_CN": "目标 AnimationPlayer 没解析出来，动画库列表回落为 <global>",
	},
	"log.menu_clicked": {
		"en": "menu item clicked: default target %s (can be changed in the dialog)",
		"zh_CN": "菜单条目被点击：默认目标 %s（可在对话框改）",
	},
	"log.menu_callback": {
		"en": "menu callback fired: player=%s sprites=%d args=%s",
		"zh_CN": "菜单回调触发：player=%s sprites=%d 收到参数=%s",
	},
	"log.menu_no_player": {
		"en": "menu clicked, but no AnimationPlayer in the selection",
		"zh_CN": "菜单被点，但选区里没有 AnimationPlayer",
	},
	"log.no_player_give_up": {
		"en": "no AnimationPlayer available, aborting",
		"zh_CN": "拿不到 AnimationPlayer，放弃",
	},
}

static var _locale := ""
static var _listeners: Array[Callable] = []
static var _watcher: SpriteFramesI18n = null
static var _watching := false


## 当前语言：zh_CN 或 en
static func locale() -> String:
	if _locale == "":
		_locale = _detect()
	return _locale


static func is_chinese() -> bool:
	return locale() == ZH


## 查表取文案；args 非空时按 %s/%d 依次填入（顺序与中文一致，别在译文里换位置）
static func t(key: String, args: Array = []) -> String:
	var entry: Dictionary = TEXTS.get(key, {}) as Dictionary
	if entry.is_empty():
		return key
	var text := String(entry.get(locale(), ""))
	if text == "":
		text = String(entry.get(EN, key))
	if args.is_empty():
		return text
	return text % args


## 带插件前缀的日志文案，省得每个调用点都拼前缀
static func log_text(key: String, args: Array = []) -> String:
	return "%s %s" % [t("log.prefix"), t(key, args)]


## 文案已经拼好了、只想补个前缀时走这个
static func log_line(text: String) -> String:
	return "%s %s" % [t("log.prefix"), text]


## 注册语言切换回调（编辑器语言改了会立刻重刷；改完要重启的情况下次启动自然生效）
static func on_locale_changed(cb: Callable) -> void:
	_watch()
	if not _listeners.has(cb):
		_listeners.append(cb)


static func remove_listener(cb: Callable) -> void:
	_listeners.erase(cb)


# --- 内部 ---

static func _watch() -> void:
	if _watching or not Engine.is_editor_hint():
		return
	# 返回值没法静态标注（EditorInterface 只在编辑器里存在），这里就不给类型
	var settings = _editor_settings()
	if settings == null:
		return
	# 编辑器设置里任何一项变动都会发，我们在回调里只认语言那一项
	settings.settings_changed.connect(_watcher_instance()._on_settings_changed)
	_watching = true


static func _watcher_instance() -> SpriteFramesI18n:
	if _watcher == null:
		_watcher = SpriteFramesI18n.new()
	return _watcher


func _on_settings_changed() -> void:
	var next := SpriteFramesI18n._detect()
	if next == SpriteFramesI18n._locale:
		return
	SpriteFramesI18n._locale = next
	for cb in SpriteFramesI18n._listeners.duplicate():
		if cb is Callable and (cb as Callable).is_valid():
			(cb as Callable).call()


static func _detect() -> String:
	var raw := _read_language_setting()
	if raw == "":
		# 编辑器之外（比如脱离编辑器跑验证脚本）拿不到设置，退到工具语言 / 系统语言
		raw = String(TranslationServer.get_tool_locale())
	if raw == "":
		raw = OS.get_locale()
	return _normalize(raw)


static func _read_language_setting() -> String:
	var settings = _editor_settings()
	if settings == null:
		return ""
	for path in LANGUAGE_SETTINGS:
		if not settings.has_setting(path):
			continue
		var value := String(settings.get_setting(path))
		if not AUTO_VALUES.has(value.to_lower()):
			return value
	return ""


static func _editor_settings():
	# EditorInterface 只在编辑器里存在，脱离编辑器时连调用都不能有
	if not Engine.is_editor_hint():
		return null
	var settings := EditorInterface.get_editor_settings()
	return settings if is_instance_valid(settings) else null


## 只区分中文与英文：zh / zh_CN / zh_Hans / zh_TW… 都算简体中文，其余回落英文
static func _normalize(raw: String) -> String:
	if raw.to_lower().begins_with("zh"):
		return ZH
	return EN
