extends BossState
class_name HollowKnightDownSmashState

## 二阶段·跳跃下砸（Desolate Dive，朝玩家头顶跃击）。
## 三段相位（计时器 + is_on_floor 推进，不依赖 animation_finished，避免信号链路断掉卡死）：
##   1) ANTIC  前摇：原地播 dstab_anticipation（蹲伏 → 起跳预备），计时结束进入跃击；
##   2) AIR    起跳：记录"玩家此刻 x"为落点，朝落点做抛物线跃击（自管重力，不调 locomotion），
##                   跃击瞬间在落点地面施放一排 plume_antic（等距留缝、不伤人），播 Audio/jump，
##                   下落段切 dstab_land；
##   3) RECOVER 落地：播 Audio/land，引爆所有 plume（plume_burst 伤人），
##                   落点正下方（水平距内）玩家追加下砸伤害；随后短暂硬直回 idle。

@export var jump_speed: float = 2000.0        # 起跳初速（像素/秒，向上）
@export var gravity: float = 2400.0           # 重力加速度（与 dormant_end 同量级）
@export var antic_fallback_time: float = 1.0  # 无 dstab_anticipation 动画时的前摇兜底
@export var recover_time: float = 0.6         # 落地后硬直（秒）
@export var slam_radius: float = 180.0        # 落点正下方判定半径（水平，像素）
@export var plume_count: int = 5              # 施放 plume 数量
@export var plume_spacing_min: float = 200.0  # 相邻 plume 间距下限（像素，留缝供玩家躲避）
@export var plume_spacing_max: float = 300.0  # 相邻 plume 间距上限（像素）
@export var slam_damage: int = 1              # 下砸本体对落点下方玩家的伤害

enum _Phase { ANTIC, AIR, RECOVER }

var _phase := _Phase.ANTIC
var _timer := 0.0
var _antic_length := 1.0
var _recover_timer := 0.0
var _left_ground := false
var _landing_x := 0.0
var _fall_anim_played := false
var _plumes: Array = []
var _plume_spacing: float = 200.0    # 本次攻击实际采用的随机间距


func enter(_from: StringName) -> void:
	if boss == null:
		return
	boss.disable_melee_attack()
	_phase = _Phase.ANTIC
	_timer = 0.0
	_recover_timer = 0.0
	_left_ground = false
	_fall_anim_played = false
	_plumes = []
	_antic_length = anim_length(&"dstab_anticipation", antic_fallback_time)
	boss.velocity = Vector2.ZERO
	# 前摇期间看向玩家（落点会在起跳瞬间锁定）。
	var p := boss.get_player()
	if p != null:
		boss.face_toward(p.global_position.x)
	# 前摇动画（蹲伏 + 起跳预备）。
	play_action(&"dstab_anticipation")


func update(delta: float) -> void:
	if boss == null:
		return
	match _phase:
		_Phase.ANTIC:
			boss.velocity.x = 0.0
			boss._apply_vertical_motion(delta)
			boss._apply_movement()
			_timer += delta
			if _timer >= _antic_length:
				_begin_air()
		_Phase.AIR:
			_air_update(delta)
		_Phase.RECOVER:
			boss.velocity.x = 0.0
			boss._apply_vertical_motion(delta)
			boss._apply_movement()
			_recover_timer += delta
			if _recover_timer >= recover_time:
				go_idle()


## 起跳瞬间：锁定落点 = 玩家此刻 x；朝落点做抛物线初速；施放一排 plume；播起跳音效。
func _begin_air() -> void:
	if boss == null:
		return
	_phase = _Phase.AIR
	_left_ground = false
	var p := boss.get_player()
	_landing_x = boss.global_position.x if p == null else p.global_position.x
	# 朝落点跃击：水平速度按"升空 + 下落"总时长均摊，落点处刚好抵达。
	var dx := _landing_x - boss.global_position.x
	var total_air := 2.0 * jump_speed / gravity
	boss.velocity.y = -jump_speed
	boss.velocity.x = dx / total_air
	boss.face_toward(_landing_x)
	# 落点地面施放一排 plume（预警，等距留缝，不伤人）。
	# 群体按 BOSS 领地（BossArena）宽度动态铺开、居中于领地，根数 = 领地宽 / 间距，
	# 两端内缩半个 plume 宽，确保羽柱不越出领地。
	var territory := boss.arena_rect()
	var ground_x := territory.get_center().x if territory.size.x > 0.0 else _landing_x
	var ground_y := boss.ground_y_at(ground_x, boss.global_position.y)
	# 每次攻击在 [min, max] 内随机间距，使落点排布每次都有差异。
	_plume_spacing = randf_range(plume_spacing_min, plume_spacing_max)
	_plumes = boss.spawn_plume_field(Vector2(ground_x, ground_y), plume_count, _plume_spacing, slam_damage, territory)
	_play_audio(&"jump")


func _air_update(delta: float) -> void:
	if boss == null:
		return
	boss.velocity.y += gravity * delta
	boss._apply_movement()
	if not _left_ground and not boss.is_on_floor():
		_left_ground = true
	# 下落段切换为 dstab_land（一次性播放）。
	if boss.velocity.y >= 0.0 and not _fall_anim_played:
		_fall_anim_played = true
		play_action(&"dstab_land")
	# 离地后重新踩到地面 = 落地。
	if _left_ground and boss.is_on_floor():
		_land()


func _land() -> void:
	_phase = _Phase.RECOVER
	_recover_timer = 0.0
	if boss != null:
		boss.velocity = Vector2.ZERO
		_play_audio(&"land")
		# 引爆所有 plume（plume_burst 对范围内玩家造成伤害）。
		boss.burst_plumes(_plumes)
	# 落点正下方（水平距内）的玩家追加下砸伤害。
	boss.damage_in_radius(_landing_x, slam_radius, slam_damage)


func exit(_to: StringName) -> void:
	if boss != null:
		boss.velocity = Vector2.ZERO
	_plumes = []
