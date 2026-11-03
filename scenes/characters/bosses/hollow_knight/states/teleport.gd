extends BossState
class_name HollowKnightTeleportState

## 瞬移 + 接劈砍连招。
## 两段相位（用计时器推进，不依赖 animation_finished，避免信号链路断掉卡死）：
##   1) OUT  消失：播 teleport_out + 音效 Audio/teleport，原地站定消失；
##   2) IN   出现：在玩家附近挑"脚下有地、不卡墙"的点瞬移过去（贴地），
##                 播 teleport_in，落定后立刻切到 slash 状态接劈砍。
##
## 触发条件与 dash 完全相同（见 idle._filter_actions），冷却也复用 2 秒。

# ---- 可调参数 ----
@export var appear_distance: float = 130.0      ## 出现在玩家两侧的基础横距（< slash 半径 200，保证能接上劈砍）
@export var max_appear_distance: float = 200.0  ## 基础点被墙/悬崖占住时向外扩展的上限（仍 ≤ slash 半径）
@export var out_fallback_time: float = 1.2      ## 无 teleport_out 动画时的消失兜底时长（与动画一致）
@export var in_fallback_time: float = 1.2       ## 无 teleport_in 动画时的出现兜底时长

enum _Phase { OUT, IN }

var _phase := _Phase.OUT
var _timer: float = 0.0
var _out_length: float = 1.2
var _in_length: float = 1.2


func enter(_from: StringName) -> void:
	if boss == null:
		return
	boss.disable_melee_attack()

	_phase = _Phase.OUT
	_timer = 0.0
	var ap := boss.action_animation_player
	_out_length = _anim_length(ap, &"teleport_out", out_fallback_time)
	_in_length = _anim_length(ap, &"teleport_in", in_fallback_time)

	# 消失：原地播放 teleport_out，并播消失音效（仅在屏幕内才发声，由 _play_audio 把关）。
	if ap != null and ap.has_animation(&"teleport_out"):
		ap.play(&"teleport_out")
	_play_audio(&"teleport")


func update(delta: float) -> void:
	if boss == null:
		return
	# 瞬移期间完全站定（含重力落定），不漂移、不结算接触伤害。
	boss.velocity.x = 0.0
	boss._apply_vertical_motion(delta)
	boss._apply_movement()

	match _phase:
		_Phase.OUT:
			_timer += delta
			if _timer >= _out_length:
				_do_teleport()
				_begin_in()
		_Phase.IN:
			_timer += delta
			if _timer >= _in_length and machine != null:
				machine.set_state(BossStateNames.SLASH)


func exit(_to: StringName) -> void:
	if boss != null:
		boss.velocity.x = 0.0


## 在玩家附近挑一个合法落点并瞬移过去。非法（卡墙 / 悬崖）就换另一侧 / 向外扩展，
## 直至 max_appear_distance；全失败则退化为"玩家同侧略偏"的兜底点。
func _do_teleport() -> void:
	var p := boss.get_player()
	if p == null:
		return
	var mask := 4
	if boss.ledge_detector != null:
		mask = boss.ledge_detector.collision_mask
	var space := boss.get_world_2d().direct_space_state
	if space == null:
		return

	var px := p.global_position.x
	var feet := _feet_offset()
	# 候选（横距, 朝向）：从近到远、左右交替；都 ≤ max_appear_distance（≤ slash 半径 200）。
	var candidates := [
		Vector2(appear_distance, 1.0),
		Vector2(appear_distance, -1.0),
		Vector2(max_appear_distance, 1.0),
		Vector2(max_appear_distance, -1.0),
	]
	var chosen := Vector2.ZERO
	for cand_off: Vector2 in candidates:
		var cand_x := px + cand_off.x * cand_off.y
		var ground_y := _ground_y(space, cand_x, mask)
		if is_nan(ground_y):
			continue  # 悬崖：脚下没地，跳过
		var cand := Vector2(cand_x, ground_y - feet)
		if _blocked_by_wall(cand, mask):
			continue  # 卡墙：跳过
		chosen = cand
		break

	if chosen == Vector2.ZERO:
		# 兜底：直接落到玩家同侧（不保证贴地，交给后续重力落定）。
		var side := 1.0 if p.global_position.x >= boss.global_position.x else -1.0
		chosen = Vector2(px + appear_distance * side, p.global_position.y)

	boss.global_position = chosen
	boss.velocity = Vector2.ZERO
	boss.face_toward(p.global_position.x)  # 瞬移后朝向玩家，劈砍自然朝玩家


## 往下打一条射线，返回该 x 处地面顶部的 y；没地返回 NAN（悬崖）。
func _ground_y(space: PhysicsDirectSpaceState2D, x: float, mask: int) -> float:
	var from := Vector2(x, boss.global_position.y - 800.0)
	var to := Vector2(x, boss.global_position.y + 1200.0)
	var query := PhysicsRayQueryParameters2D.create(from, to)
	query.collision_mask = mask
	query.exclude = [boss.get_rid()]
	var res := space.intersect_ray(query)
	if res.is_empty():
		return NAN
	return float(res.position.y)


## 候选点身体中段高度向左右各打一条短水平射线，命中地形即视为卡墙。
## 取中段高度（避开脚下地面），避免"贴地"被误判成卡墙。
func _blocked_by_wall(cand: Vector2, mask: int) -> bool:
	var half_w := _body_half_width()
	var probe_y := cand.y - _feet_offset() * 0.5
	var space := boss.get_world_2d().direct_space_state
	for dir in [-1.0, 1.0]:
		var from := Vector2(cand.x, probe_y)
		var to := Vector2(cand.x + dir * (half_w + 8.0), probe_y)
		var query := PhysicsRayQueryParameters2D.create(from, to)
		query.collision_mask = mask
		query.exclude = [boss.get_rid()]
		if not space.intersect_ray(query).is_empty():
			return true
	return false


## boss 碰撞胶囊底部相对身体原点的偏移（用于把脚贴到地面）。
func _feet_offset() -> float:
	var shape_node := boss.collision_shape
	if shape_node != null and shape_node.shape is CapsuleShape2D:
		var cap := shape_node.shape as CapsuleShape2D
		return cap.height * 0.5 + cap.radius + shape_node.position.y
	return 0.0


## 胶囊半径 = 身体半宽。
func _body_half_width() -> float:
	var shape_node := boss.collision_shape
	if shape_node != null and shape_node.shape is CapsuleShape2D:
		return (shape_node.shape as CapsuleShape2D).radius
	return 100.0


func _begin_in() -> void:
	if _phase != _Phase.OUT:
		return
	_phase = _Phase.IN
	_timer = 0.0
	var ap := boss.action_animation_player if boss != null else null
	if ap != null and ap.has_animation(&"teleport_in"):
		ap.play(&"teleport_in")


## 取动画时长，取不到就用兜底值（保证相位推进不被缺动画卡住）。
func _anim_length(ap: AnimationPlayer, anim_name: StringName, fallback: float) -> float:
	if ap != null and ap.has_animation(anim_name):
		return ap.get_animation(anim_name).length
	return fallback
