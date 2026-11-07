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
	_out_length = anim_length(&"teleport_out", out_fallback_time)
	_in_length = anim_length(&"teleport_in", in_fallback_time)

	# 消失：原地播放 teleport_out，并播消失音效（仅在屏幕内才发声，由 _play_audio 把关）。
	play_action(&"teleport_out")
	_play_audio(&"teleport")


func update(delta: float) -> void:
	if boss == null:
		return
	# 瞬移期间完全站定（含重力落定），不漂移、不结算接触伤害。
	stand_still(delta, false)

	match _phase:
		_Phase.OUT:
			_timer += delta
			if _timer >= _out_length:
				_do_teleport()
				_begin_in()
		_Phase.IN:
			_timer += delta
			if _timer >= _in_length:
				goto_if_current(BossStateNames.SLASH)


func exit(_to: StringName) -> void:
	if boss != null:
		boss.velocity.x = 0.0


## 在玩家附近挑一个合法落点并瞬移过去。非法（卡墙 / 悬崖）就换另一侧 / 向外扩展，
## 直至 max_appear_distance；全失败则退化为"玩家同侧略偏"的兜底点。
## 落点搜索本身（射线 / 胶囊脚高 / 卡墙探测）已沉淀在 Boss.find_ground_position_near。
func _do_teleport() -> void:
	var p := boss.get_player()
	if p == null:
		return

	var chosen := boss.find_ground_position_near(
			p.global_position.x, appear_distance, max_appear_distance)
	if chosen == Vector2.ZERO:
		# 兜底：直接落到玩家同侧（不保证贴地，交给后续重力落定）。
		var side := 1.0 if p.global_position.x >= boss.global_position.x else -1.0
		chosen = Vector2(p.global_position.x + appear_distance * side, p.global_position.y)

	# 落点裁进领地（防御贴边 / 兜底点越界），并走统一瞬变重置物理插值。
	boss.teleport_to(boss.clamp_position_to_arena(chosen), true)


func _begin_in() -> void:
	if _phase != _Phase.OUT:
		return
	_phase = _Phase.IN
	_timer = 0.0
	play_action(&"teleport_in")
