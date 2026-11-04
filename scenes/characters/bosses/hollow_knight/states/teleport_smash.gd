extends BossState
class_name HollowKnightTeleportSmashState

## 二阶段·瞬移下杀（Desolate Dive 的瞬移版）。
## 三段相位（计时器 + is_on_floor 推进，不依赖 animation_finished，避免信号链路断掉卡死）：
##   1) OUT    消失：原地播 teleport_out + 音效 Audio/teleport；瞬移开始瞬间在玩家落点地面
##                  施放一排 boss_plume（预警，不伤人，同 down_smash，横跨整个 BossArena）；
##   2) FALL   瞬移下杀：把 BOSS 瞬移到玩家头顶 teleport_height 像素处，给向下初速，纯重力
##                  快速下坠，播 dstab_land（俯冲姿态）；落地即停；
##   3) RECOVER 落地：播 Audio/land，引爆所有 plume（plume_burst 伤人），
##                  落点正下方（水平距内）玩家追加下杀伤害；随后短暂硬直回 idle。

@export var teleport_height: float = 1000.0       # 瞬移到玩家头顶上方的高度（像素，可配置）
@export var gravity: float = 2000.0              # 重力加速度（与 down_smash 同量级）
@export var fall_initial_speed: float = 600.0    # 下坠初始向下速度（让"快速下杀"更跟手）
@export var out_fallback_time: float = 1.2       # 无 teleport_out 动画时的消失兜底时长
@export var max_fall_time: float = 2.5           # 下落安全上限（无地面兜底，超时强制落地）
@export var recover_time: float = 0.6            # 落地后硬直（秒）
@export var slam_radius: float = 180.0           # 落点正下方判定半径（水平，像素）
@export var plume_count: int = 5                 # 施放 plume 数量（领地模式下为下限，根数随领地宽度动态算）
@export var plume_spacing_min: float = 200.0     # 相邻 plume 间距下限（像素，留缝供玩家躲避）
@export var plume_spacing_max: float = 300.0     # 相邻 plume 间距上限（像素）
@export var slam_damage: int = 1                 # 下杀本体 / plume 对玩家的伤害

enum _Phase { OUT, FALL, RECOVER }

var _phase := _Phase.OUT
var _timer := 0.0
var _out_length := 1.2
var _fall_timer := 0.0
var _recover_timer := 0.0
var _left_ground := false
var _landing_x := 0.0
var _plumes: Array = []
var _plume_spacing: float = 200.0


func enter(_from: StringName) -> void:
	if boss == null:
		return
	boss.disable_melee_attack()
	_phase = _Phase.OUT
	_timer = 0.0
	_fall_timer = 0.0
	_recover_timer = 0.0
	_left_ground = false
	_plumes = []

	_out_length = anim_length(&"teleport_out", out_fallback_time)

	# 瞬移开始时即施放 boss_plume（同 down_smash 的实现）：横跨整个 BossArena 铺一排预警柱，
	# 整组居中于领地、两端内缩不越界；boss 随后瞬移到玩家头顶砸下。
	var p := boss.get_player()
	_landing_x = boss.global_position.x if p == null else p.global_position.x
	if p != null:
		boss.face_toward(p.global_position.x)
	var territory := boss.arena_rect()
	var ground_x := territory.get_center().x if territory.size.x > 0.0 else _landing_x
	var ground_y := boss.ground_y_at(ground_x, boss.global_position.y)
	# 每次攻击在 [min, max] 内随机间距，使落点排布每次都有差异。
	_plume_spacing = randf_range(plume_spacing_min, plume_spacing_max)
	_plumes = boss.spawn_plume_field(Vector2(ground_x, ground_y), plume_count, _plume_spacing, slam_damage, territory)

	# 消失：原地播放 teleport_out + 消失音效。
	play_action(&"teleport_out")
	_play_audio(&"teleport")


func update(delta: float) -> void:
	if boss == null:
		return
	match _phase:
		_Phase.OUT:
			# 消失期间原地站定（含重力落定），不漂移、不结算接触伤害。
			stand_still(delta, false)
			_timer += delta
			if _timer >= _out_length:
				_begin_fall()
		_Phase.FALL:
			_fall_update(delta)
		_Phase.RECOVER:
			stand_still(delta, false)
			_recover_timer += delta
			if _recover_timer >= recover_time:
				go_idle()


## 瞬移：把 BOSS 直接挪到玩家头顶 teleport_height 像素处，给向下初速，切到俯冲动画。
func _begin_fall() -> void:
	if boss == null:
		return
	_phase = _Phase.FALL
	_fall_timer = 0.0
	_left_ground = false
	var p := boss.get_player()
	var target_x := _landing_x
	var target_y := (p.global_position.y if p != null else boss.global_position.y) - teleport_height
	boss.global_position = Vector2(target_x, target_y)
	boss.velocity = Vector2(0.0, fall_initial_speed)
	if p != null:
		boss.face_toward(p.global_position.x)
	play_action(&"dstab_land")


func _fall_update(delta: float) -> void:
	if boss == null:
		return
	boss.velocity.y += gravity * delta
	boss._apply_movement()
	_fall_timer += delta
	# 落地（踩到地面）或下落超时（无地面兜底）都算结束，避免无限下坠。
	if boss.is_on_floor() or _fall_timer >= max_fall_time:
		_land()


func _land() -> void:
	_phase = _Phase.RECOVER
	_recover_timer = 0.0
	if boss != null:
		boss.velocity = Vector2.ZERO
		_play_audio(&"land")
		# 引爆所有 plume（plume_burst 对范围内玩家造成伤害）。
		boss.burst_plumes(_plumes)
	# 落点正下方（水平距内）的玩家追加下杀伤害。
	boss.damage_in_radius(_landing_x, slam_radius, slam_damage)


func exit(_to: StringName) -> void:
	if boss != null:
		boss.velocity = Vector2.ZERO
	# 与 down_smash 一致：已爆破的 plume 会自毁，这里只清空引用。
	_plumes = []
