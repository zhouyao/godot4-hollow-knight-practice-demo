extends CanvasLayer
class_name Hud

## 顶部左侧状态栏（空之骑士风格）：
##   灵魂球 = 玩家能量，用遮罩着色器从球底往上"灌液"；
##   血量   = 面具格，按 max_health 生成，掉血破格 / 回血补格；
##   钱币   = Inventory 里的 coin 数量，左侧是旋转的 geo 图标。
##
## 能量为 0 时球体完全隐去，只剩边框；满能量时切到静态的满球贴图，
## 免去遮罩逐帧动画的开销，也避免满液位被液面起伏切出缺口。

const HEALTH_INDICATOR_SCENE := preload("res://scenes/ui/health_indicator.tscn")

## 出场动画延迟（秒）：留给关卡转场 / 玩家落地，避免动画被转场盖掉。
const FRAME_INTRO_DELAY := 0.5

@onready var frame_sprite: AnimatedSprite2D = $TopLeft/VBoxContainer/StatusDetails/Frame/FrameAnimatedSprite
@onready var filling_soul: TextureRect = $TopLeft/VBoxContainer/StatusDetails/Frame/SoulMargin/FillingSoul
@onready var full_soul: TextureRect = $TopLeft/VBoxContainer/StatusDetails/Frame/SoulMargin/FullSoul
@onready var health_grid: GridContainer = $TopLeft/VBoxContainer/StatusDetails/HealthIndicators
@onready var geo_label: Label = $TopLeft/VBoxContainer/MarginContainer/GeoIndicator/Label

## 当前接管的玩家：HUD 与 Player 同属 WorldTemplate，_ready 时自动绑定同级节点。
var _player: PlayerInitial
## 已生成的面具格（下标 0 = 第 1 格）。用 Node 存以避免 HUD 与格脚本强耦合。
var _indicators: Array[Node] = []
## 上一次血量：和当前值一起决定每格播出现还是破碎。
var _last_health := 0


func _ready() -> void:
	Inventory.changed.connect(_on_inventory_changed)
	_on_inventory_changed(&"coin", Inventory.count(&"coin"))
	_play_frame_intro()
	bind_player(get_parent().get_node_or_null(^"Player") as PlayerInitial)


## 显式注入玩家（换关卡 / 玩家节点名字不同时用）：重复传入同一引用不会重复连信号。
func bind_player(p: PlayerInitial) -> void:
	if p == _player:
		return
	if _player != null:
		if _player.energy_changed.is_connected(_on_energy_changed):
			_player.energy_changed.disconnect(_on_energy_changed)
		if _player.health_changed.is_connected(_on_health_changed):
			_player.health_changed.disconnect(_on_health_changed)
	_player = p
	_last_health = 0
	if _player == null:
		_set_soul_ratio(0.0)
		_rebuild_health_indicators()
		return
	_player.energy_changed.connect(_on_energy_changed)
	_player.health_changed.connect(_on_health_changed)
	_on_energy_changed(_player.energy)
	_rebuild_health_indicators()
	_on_health_changed(_player.health)


func _on_energy_changed(energy: int) -> void:
	var maximum := _player.max_energy if _player != null else 0
	_set_soul_ratio(0.0 if maximum <= 0 else float(energy) / float(maximum))


func _set_soul_ratio(ratio: float) -> void:
	ratio = clampf(ratio, 0.0, 1.0)
	full_soul.visible = ratio >= 1.0
	filling_soul.visible = not full_soul.visible
	if full_soul.visible:
		return
	# mask_translation 与能量反向：1 = 空（遮罩沉到球外），0 = 满（遮罩与球对齐）。
	var soul_material := filling_soul.material as ShaderMaterial
	if soul_material != null:
		soul_material.set_shader_parameter(&"mask_translation", 1.0 - ratio)


## 血量变化：把旧值 / 新值广播给每一格，由格子自己决定出现、破碎还是不动。
## max_health 若在运行中变化（读档回填），先重建格数，再从 0 补齐。
func _on_health_changed(health: int) -> void:
	var maximum := _player.max_health if _player != null else 0
	if _indicators.size() != maximum:
		_rebuild_health_indicators()
	var old_health := _last_health
	_last_health = health
	for indicator in _indicators:
		indicator.call(&"update_health", old_health, health)


func _rebuild_health_indicators() -> void:
	for indicator in _indicators:
		if is_instance_valid(indicator):
			health_grid.remove_child(indicator)
			indicator.queue_free()
	_indicators.clear()
	_last_health = 0
	if _player == null:
		return
	for i in _player.max_health:
		var indicator := HEALTH_INDICATOR_SCENE.instantiate()
		indicator.set(&"index", i + 1)
		health_grid.add_child(indicator)
		_indicators.append(indicator)


func _on_inventory_changed(item_id: StringName, total: int) -> void:
	if item_id != &"coin":
		return
	geo_label.text = str(total)


## 边框出场动画：延迟一秒后播 appear，播完停在 idle。
## 只延迟边框这一层，灵魂球 / 血量 / 钱币照常显示。
func _play_frame_intro() -> void:
	var frames := frame_sprite.sprite_frames
	if frames == null or not frames.has_animation(&"appear"):
		return
	# 先藏起边框：否则 autoplay 的 idle 会先露出完整边框，一秒后再倒回 appear 第一帧。
	frame_sprite.visible = false
	await get_tree().create_timer(FRAME_INTRO_DELAY).timeout
	if not is_instance_valid(frame_sprite):
		return
	frame_sprite.visible = true
	frame_sprite.play(&"appear")
	await frame_sprite.animation_finished
	if is_instance_valid(frame_sprite):
		frame_sprite.play(&"idle")
