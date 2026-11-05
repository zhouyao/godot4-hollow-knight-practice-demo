@tool
extends Area2D
class_name Grass

## 草本体（Plant）。
## 反馈 A 惊扰：玩家身体碰撞体擦过/进入本 Area2D → idle 摆动突然加快，0.6s 后恢复。
## 反馈 B 被割死亡：受攻击（take_damage）→ 累计刀数，达到所需刀数才停止 idle、
##   播放枯死动画、迸发叶片、播放割草音效、生成受击刀光、关闭碰撞体。
##   所需刀数由 hits_to_die 决定：配 N 则在 1~N 之间随机（配 2 = 1 刀或 2 刀死）。

const GRASS_FRAMES := preload("res://resources/effects/plants/grass/grass.tres")
const GRASS_DEATH_FRAMES := preload("res://resources/effects/plants/grass/grass_death.tres")
const LEAF_BURST := preload("res://scenes/effects/plants/leaf_burst.tscn")
# 受击刀光改用 HitEffect 统一分发（hit_effect.gd）：特效由本节点 hit_effect_by_source 配置，
# 按来源种类（如玩家挥砍 &"slash"）选择场景；查不到则回落默认键，再否则回落通用 nail 刀光。

const _GRASSCUT_0 := preload("res://assets/sounds/plants/grass_cut_0.ogg")
const _GRASSCUT_1 := preload("res://assets/sounds/plants/grass_cut_1.ogg")

## 空闲摆动动画名（grass_0 ~ grass_3），每株可不同。
@export var idle_animation: StringName = &"grass_0":
	set(value):
		idle_animation = value
		_apply_idle_animation()
## 枯死动画名（grass_0 ~ grass_3），通常与 idle_animation 一一对应。
@export var death_animation: StringName = &"grass_0":
	set(value):
		death_animation = value
		_apply_death_animation()
## 惊扰触发区 / 受击命中区尺寸（复用同一个碰撞体，参考 75×100 ~ 150×100）。
@export var disturb_shape_size: Vector2 = Vector2(110.0, 100.0)
## 受击命中区尺寸；若非 (0,0) 则覆盖 disturb_shape_size。
@export var hitbox_size: Vector2 = Vector2.ZERO
## 砍几刀才死亡。实际所需刀数在 1 ~ hits_to_die 之间随机抽取：
## 配 1 → 必定 1 刀死；配 2 → 1 刀或 2 刀死（各 50%）；配 N → 1~N 随机。
@export_range(1, 10, 1, "or_greater") var hits_to_die: int = 1
## 受击刀光数量随机范围（闭区间）：每次受击按此范围摇一个数量。
@export_range(0, 24, 1, "or_greater") var hit_effect_count_min: int = 1
@export_range(0, 24, 1, "or_greater") var hit_effect_count_max: int = 1
## 多份刀光在受击点周围的散布半径（像素），0 = 全部叠在同一点。
@export var hit_effect_scatter: float = 6.0
## 受击特效表：键为来源 get_damage_kind() 返回的 StringName，值为场景。
## 约定键 &"slash" 为默认受击表现（玩家挥砍）；查不到来源种类时回落到 &"slash"；
## 仍无匹配则回落 _NAIL（通用刀光）。草默认用 nail 刀光。
@export var hit_effect_by_source: Dictionary = {}
## 割草音效池（留空则默认加载 grass_cut_0/1）。
@export var grasscut_streams: Array[AudioStream] = []
## 尸体纵向偏移（像素）：枯死后把枯死精灵沿 y 轴挪动这么多，
## 用于微调躺尸的纵向位置，让不同素材的枯死尸体贴合地面（正 = 向下，负 = 向上）。0 = 不偏移。
@export var corpse_y_offset: float = 0.0

@onready var _anim: AnimatedSprite2D = $IdleAnimatedSprite2D
@onready var _death_anim: AnimatedSprite2D = $DeathAnimatedSprite2D
@onready var _shape: CollisionShape2D = $CollisionShape2D
@onready var _audio: AudioStreamPlayer2D = $AudioStreamPlayer2D

var _is_dead: bool = false
var _restore_timer: SceneTreeTimer = null
var _hits_taken: int = 0
## 本株实际需要挨的刀数（1 ~ hits_to_die 随机），在 _ready 时摇一次。
var _hits_required: int = 1

func _ready() -> void:
	# idle 摆动：编辑器内实时预览，运行时再随机起始帧营造自然错落感
	_apply_idle_animation()
	if not Engine.is_editor_hint():
		var frames := GRASS_FRAMES.get_frame_count(idle_animation)
		if frames > 0:
			_anim.frame = randi_range(0, frames - 1)

	# 枯死动画：保持同步配置，运行时先隐藏，等 _die() 再显示
	_apply_death_animation()
	_death_anim.visible = false

	# 配置碰撞体尺寸（惊扰区与受击区共用）
	var size := disturb_shape_size
	if hitbox_size != Vector2.ZERO:
		size = hitbox_size
	if _shape.shape == null:
		_shape.shape = RectangleShape2D.new()
	(_shape.shape as RectangleShape2D).size = size

	_roll_hits_required()

	if grasscut_streams.is_empty():
		grasscut_streams = [_GRASSCUT_0, _GRASSCUT_1]

## 抽取本株需要挨几刀才死：1 ~ hits_to_die 之间均匀随机。
func _roll_hits_required() -> void:
	_hits_required = randi_range(1, maxi(1, hits_to_die))

# body_entered 已在 grass.tscn 中连线，这里不再手动连接。

## 把 idle_animation 同步到 IdleAnimatedSprite2D（编辑器改属性时即时预览）。
func _apply_idle_animation() -> void:
	# setter 可能在子节点就绪前触发，这里不能直接依赖 @onready 的 _anim
	var anim := get_node_or_null("IdleAnimatedSprite2D") as AnimatedSprite2D
	if anim == null or not GRASS_FRAMES.has_animation(idle_animation):
		return
	if anim.sprite_frames != GRASS_FRAMES:
		anim.sprite_frames = GRASS_FRAMES
	if anim.animation != idle_animation:
		anim.animation = idle_animation
	anim.play()

## 把 death_animation 同步到 DeathAnimatedSprite2D（编辑器改属性时即时预览）。
func _apply_death_animation() -> void:
	var anim := get_node_or_null("DeathAnimatedSprite2D") as AnimatedSprite2D
	if anim == null or not GRASS_DEATH_FRAMES.has_animation(death_animation):
		return
	if anim.sprite_frames != GRASS_DEATH_FRAMES:
		anim.sprite_frames = GRASS_DEATH_FRAMES
	if anim.animation != death_animation:
		anim.animation = death_animation
	anim.stop()
	anim.frame = 0

# ---- 反馈 A：惊扰 ----------------------------------------------------------
func _on_body_entered(body: Node) -> void:
	if _is_dead:
		return
	if body.is_in_group("player"):
		_disturb()

func _disturb() -> void:
	if _is_dead:
		return
	_anim.speed_scale = 5.0                     # 摆动间隔变为原来的 0.2 倍
	if _restore_timer != null and _restore_timer.timeout.is_connected(_on_restore_timeout):
		_restore_timer.timeout.disconnect(_on_restore_timeout)
	_restore_timer = get_tree().create_timer(0.6)
	_restore_timer.timeout.connect(_on_restore_timeout)

func _on_restore_timeout() -> void:
	if not _is_dead:
		_anim.speed_scale = 1.0

# ---- 反馈 B：被割死亡 ------------------------------------------------------
func take_damage(_amount: int = 1, _from: Node2D = null) -> void:
	if _is_dead:
		return
	if _hits_required == 0:
		_roll_hits_required()          # 极端情况下先于 _ready 被调用

	_hits_taken += 1
	if _hits_taken >= _hits_required:
		_die(_from)
	else:
		_hit(_from)

## 未致死的一次挥砍：割草音效 + 刀光，草还在。
func _hit(_from: Node2D = null) -> void:
	if not grasscut_streams.is_empty():
		_audio.stream = grasscut_streams.pick_random()
		_audio.pitch_scale = randf_range(0.9, 1.1)
		_audio.play()

	# 受击命中特效：谁被砍谁生成（场景由本节点 hit_effect_by_source 决定，可按来源细分）。
	HitEffect.spawn(self, global_position, get_parent(),
			hit_effect_count_min, hit_effect_count_max, hit_effect_scatter, _from)

func _die(_from: Node2D = null) -> void:
	_is_dead = true

	# 1. 播放枯死动画，停止 idle
	_anim.stop()
	_anim.visible = false
	_death_anim.frame = 0
	_death_anim.visible = true
	_death_anim.play()
	# 1.1 枯死尸体纵向偏移：贴合不同素材的躺尸位置。
	if not is_zero_approx(corpse_y_offset):
		_death_anim.position.y += corpse_y_offset

	# 2. 随机割草音效
	if not grasscut_streams.is_empty():
		_audio.stream = grasscut_streams.pick_random()
		_audio.pitch_scale = randf_range(0.9, 1.1)
		_audio.play()

	# 3. 叶片粒子迸发
	var host := get_parent()
	var burst := LEAF_BURST.instantiate() as Node2D
	host.add_child(burst)
	# 必须先 add_child 再赋 global_position：节点未入树时 global_position 会被当成局部坐标，
	# 而本体的父节点（关卡里的 G0/G1 等分组节点）自身带位移，会导致特效被二次偏移。
	burst.global_position = global_position
	# 叶片与草同层并盖在草前面：MossHole 等关卡给草单独配了 z_index（-2/-1/4），
	# 而粒子默认 z=0，会被前景苔藓层（z=2~13）整片盖住，看起来像"特效丢失"。
	burst.z_index = z_index + 1
	# 本项目开了 2D 物理插值：位置改变后必须重置，否则起爆首帧会从世界原点飞过来
	# （与 chest.gd 对 chest_burst 的处理一致）。
	burst.reset_physics_interpolation()

	# 4. 受击刀光：由本节点 hit_effect_by_source 决定（默认 &"slash" → nail 刀光），可按来源细分。
	HitEffect.spawn(self, global_position, host,
			hit_effect_count_min, hit_effect_count_max, hit_effect_scatter, _from)

	# 5. 关闭碰撞体，不再可交互
	# take_damage 是在 Area2D 的 area_entered 信号回调里被调用的，此时物理服务器仍在派发信号，
	# 直接改 monitoring/monitorable 会被拒绝，必须延迟到当前物理帧结束之后。
	set_deferred("monitoring", false)
	set_deferred("monitorable", false)
	set_deferred("input_pickable", false)
