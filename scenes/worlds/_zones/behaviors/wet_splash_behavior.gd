extends AuZoneBehavior
class_name AuWetSplashBehavior

## 涉水区踩水水花挂件。
##
## 挂在 AuZone 下面，复用与 AuFootstepBehavior 相同的"涉水判定"：
## 只有当宿主区域是当前 surface 通道的胜者（surface == water）时，
## 才在玩家脚下生成 wet_walk_effect 水花精灵（横向 5 帧精灵表），播一遍后自毁。
##
## 三种触发源共用同一套帧构建与生成逻辑，差别只在缩放倍率与生成点偏移：
##   · 行走 —— 在地面横向移动时按 step_interval 出脚，与 FootstepBehavior 音画同步；
##   · 起跳 —— is_on_floor 由真变假且带向上速度，在离地点溅一朵小的；
##   · 落地 —— 由假变真，强度按空中最大下落速度插值，小跳小水花、满跳大水花。
##
## 不要为跳跃 / 落地另起一个挂件：那会把 _build_frames() 与生成位置逻辑抄第二遍，
## 且两处 step_interval 一多就会音画不同步。
##
## 贴图是单张 PNG 内横排的 5 个小图，本脚本在运行时用 AtlasTexture 按 宽度/5 切成
## 5 帧拼成 SpriteFrames（无需改 .import 的导入方式）。


@export_group("水花 Splash")
## 踩水水花贴图：横向排列的 5 帧精灵表（单张 PNG 内 5 个小图）。
@export var effect_sheet: Texture2D
## 精灵表横向帧数（wet_walk_effect.png 为 5）。
@export var frame_count: int = 5
## 玩家脚下相对身体原点的偏移（胶囊高 150，脚约在 +75，留微调）。
@export var foot_offset: Vector2 = Vector2(0, 70)
## 水花 z 层级：默认压在玩家之下，可按观感调成正数盖在脚上。
@export var splash_z_index: int = -1
## 左右脚随机抖动（像素），避免每次都踩在同一个点。
@export var jitter_x: float = 6.0

@export_group("步点 Step")
## 步点间隔（秒），必须与 FootstepBehavior2 的 step_interval 一致。
@export var step_interval: float = 0.3
## 判定"在移动"的横向速度阈值（像素/秒）。
@export var move_epsilon: float = 1.0

@export_group("起跳 Jump")
## 起跳水花的缩放（相对走路水花）。1.0 = 同尺寸，调大要谨慎：起跳本身位移很快，
## 水花太大会在画面上糊成一片。
@export var jump_splash_scale: float = 0.9
## 判定"真的起跳了"的最小向上速度（像素/秒）。
## 玩家满跳初速约 1152，从平台边缘走下去时 velocity.y 接近 0，这个阈值把两者分开。
@export var jump_min_velocity: float = 120.0

@export_group("落地 Land")
## 落地水花的最小缩放（浅落）。
@export var land_splash_scale_min: float = 0.8
## 落地水花的最大缩放（满跳落地，下落速度约 1152 像素/秒）。
@export var land_splash_scale_max: float = 1.6
## 低于该下落速度不溅水花：过滤走下小台阶时 is_on_floor 的逐帧抖动，
## 否则平地上走路会莫名其妙一路冒水花。
@export var land_min_fall_speed: float = 200.0
## 达到该下落速度即视为"满强度落地"。
@export var land_max_fall_speed: float = 1152.0


var _timer := 0.0
var _frames: SpriteFrames = null

## 上一帧是否在地面：起跳 / 落地的边沿检测靠它。
var _was_on_floor := false
## 本次离地过程中记录的最大下落速度（像素/秒，向下为正）。
var _peak_fall_speed := 0.0
## 本次离地是否发生在"水面胜出"的那一刻。
## 空中即使区域仲裁翻转（跳出检测框）也必须保住它，否则落地水花会丢。
var _air_wet := false
## 当前追踪的 body：换人（复活 / 传送 / 多角色）时重置以上状态，避免状态串味。
var _tracked_body: Node = null


func _ready() -> void:
	super._ready()
	_frames = _build_frames()


## 运行时把 effect_sheet 按 frame_count 横向等分，拼成名为 "splash" 的 SpriteFrames。
## 帧率 = 帧数 / 步点间隔，使整段水花动画时长 ≈ 一次脚步的间隔，与涉水音同节奏。
func _build_frames() -> SpriteFrames:
	if effect_sheet == null or frame_count <= 0:
		return null
	var sf := SpriteFrames.new()
	sf.add_animation(&"splash")
	# SpriteFrames 动画默认 loop=true，循环动画永远不会发出 animation_finished，
	# 水花就会赖在原地不消失。显式关掉循环，播完 5 帧即结束并自毁。
	sf.set_animation_loop(&"splash", false)
	var w := effect_sheet.get_width()
	var cw := float(w) / float(frame_count)
	var h := effect_sheet.get_height()
	for i in frame_count:
		var at := AtlasTexture.new()
		at.atlas = effect_sheet
		at.region = Rect2(cw * float(i), 0.0, cw, h)
		sf.add_frame(&"splash", at)
	sf.set_animation_speed(&"splash", float(frame_count) / maxf(step_interval, 0.05))
	return sf


func on_entered(_body: Node2D) -> void:
	_timer = 0.0
	_reset_vertical_state()


func on_gained(channel: StringName) -> void:
	if channel == &"surface":
		_timer = 0.0
		_reset_vertical_state()


func on_lost(channel: StringName) -> void:
	if channel == &"surface":
		_timer = 0.0
		_reset_vertical_state()


func _physics_process(delta: float) -> void:
	var zone := get_zone()
	if zone == null:
		_timer = 0.0
		_reset_vertical_state()
		return
	var body := zone.last_body() as CharacterBody2D
	if body == null or not is_instance_valid(body):
		_timer = 0.0
		_reset_vertical_state()
		return

	var effective := zone.is_effective(&"surface")
	var on_floor := body.is_on_floor()

	# 垂直状态追踪必须无条件跑：玩家跳起来后可能先离开检测框，
	# 那时 effective 已为 false，若在它之后才追踪就再也观测不到落地。
	_track_vertical(body, on_floor, effective)

	if not effective or not on_floor:
		_timer = 0.0
		return
	if absf(body.velocity.x) <= move_epsilon:
		return
	_timer += delta
	if _timer >= step_interval:
		_timer -= step_interval
		_spawn_splash(body, 1.0)


## 起跳 / 落地边沿检测：只在状态跳变的那一帧生成水花。
func _track_vertical(body: CharacterBody2D, on_floor: bool, effective: bool) -> void:
	if body != _tracked_body:
		# 换人：把上一帧状态直接对齐当前值，避免拿别人的空中状态误判落地。
		_tracked_body = body
		_was_on_floor = on_floor
		_peak_fall_speed = 0.0
		_air_wet = false
		return

	if _was_on_floor and not on_floor:
		# 离地
		if effective and body.velocity.y < -jump_min_velocity:
			# 不做"倒推一帧"的位置补偿：本挂件与玩家状态机的 _physics_process
			# 谁先执行并不确定，补偿方向可能正好相反，把水花推进地面。
			# 一帧 ≈ 19px 的偏差交给 foot_offset 统一吸收。
			_spawn_splash(body, jump_splash_scale)
			_air_wet = true
		else:
			# 走下平台 / 被挤出检测框：不算起跳，本次离地不该溅水。
			_air_wet = false
		_peak_fall_speed = 0.0
	elif not _was_on_floor and on_floor:
		# 落地。_air_wet 兜住"起跳后在空中离开检测框"的情况：
		# 起跳时踩在水里，落地时哪怕区域已不生效也该溅。
		if (_air_wet or effective) and _peak_fall_speed >= land_min_fall_speed:
			var t := clampf(
					inverse_lerp(land_min_fall_speed, land_max_fall_speed, _peak_fall_speed),
					0.0, 1.0)
			_spawn_splash(body, lerpf(land_splash_scale_min, land_splash_scale_max, t))
		_air_wet = false
		_peak_fall_speed = 0.0
		# 落地那一脚已经溅过，别让走路计时器在同一帧再来一发。
		_timer = 0.0

	# 只记下落段：上升时 velocity.y 为负，maxf 会把它挡掉。
	if not on_floor:
		_peak_fall_speed = maxf(_peak_fall_speed, body.velocity.y)
	_was_on_floor = on_floor


func _reset_vertical_state() -> void:
	_tracked_body = null
	_was_on_floor = false
	_peak_fall_speed = 0.0
	_air_wet = false


## 在玩家脚下生成一次性水花：留在落点（不跟随玩家），播完 5 帧自动销毁。
## strength：整体缩放倍率（走 1.0 / 起跳 <1 / 落地按速度插值）。
func _spawn_splash(body: Node2D, strength: float = 1.0) -> void:
	if _frames == null:
		return
	var spr := AnimatedSprite2D.new()
	spr.sprite_frames = _frames
	spr.animation = &"splash"
	spr.centered = true
	spr.scale = Vector2.ONE * strength
	spr.z_index = splash_z_index
	# 挂在关卡根/特效容器上（变换近似恒等），而不是宿主区域的父节点（RainZone）。
	# 雨区根节点常被摆在离落点很远的位置（level_1 里 RainZone 在 (-2800,0)、
	# RainZone2 在 (5965,0)，而地面在 y≈500），父节点离落点越远，
	# 入树时的插值基准就越偏 —— 见下面的 reset_physics_interpolation()。
	var parent := _splash_parent()
	parent.add_child(spr)
	# 必须先入树、再设 global_position：否则父节点（如 RainZone 在关卡里的 -2800,0）
	# 的全局变换会被二次叠加，水花被甩到屏幕外（表现为"节点生成了却看不见"）。
	spr.global_position = body.global_position + foot_offset \
		+ Vector2(randf_range(-jitter_x, jitter_x), 0.0)
	# 项目开了 physics/common/physics_interpolation：新节点入树时记录的插值基准
	# 是它当时的变换（父节点下的原点），而坐标是入树之后才写进去的。
	# 不重置的话，首帧会从"父节点原点"插值到"脚下"，表现为水花在玩家头顶闪一下
	# （雨区根节点 y=0，玩家脚下 y≈500，差 500px 正好越过角色）。
	# 顺序不能反：必须在写入新坐标之后调用。
	spr.reset_physics_interpolation()
	spr.play(&"splash")
	spr.animation_finished.connect(spr.queue_free)


## 水花挂载点：优先关卡根（变换近似恒等，离落点最近，插值基准不会跑偏）；
## 关卡根不可用时退回宿主区域的父节点，最后退回场景树根，保证任何关卡下都能工作。
## 水花是 5 帧后自毁的一次性特效，挂到关卡根不会残留在雨区之外。
func _splash_parent() -> Node:
	if is_inside_tree():
		var scene := GameSession.content_root()
		if scene != null and scene != self:
			return scene
	var host := get_zone()
	if host != null and host.get_parent() != null:
		return host.get_parent()
	return get_tree().root
