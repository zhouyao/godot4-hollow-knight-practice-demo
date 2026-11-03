extends BossState
class_name SoulMasterDormantState

## SoulMaster 候场态（初始状态）：BOSS 完全隐藏、安静、不结算伤害。
## 玩家踏入 BossArena（AuZone）时切到 entrance 开始浮现演出。
##
## 职责划分与 HollowKnight 的 dormant 一致：状态自己监听领地，演出归 BOSS 自己，
## 领地挂件（BossArenaBehavior）保持 auto_start_fight = false 即可。
##
## 重要：领地信号连上后**永不断开**。玩家离场时 BOSS 多半已经在 idle，
## 复位逻辑必须还能收到 player_exited，所以不能跟着 exit() 一起解绑。

## 玩家离开领地后是否整场复位（隐身回到候场），再次踏入会重新浮现。
@export var reset_on_player_exit: bool = true
## 离场复位前的缓冲时长（秒）：玩家出界又立刻折返时不复位。
@export var reset_delay: float = 2.0
## BGM 节点（相对 BOSS 根节点）。
@export var bgm_path: NodePath = ^"BGM"

var _arena: AuZone
var _arena_connected := false
var _reset_timer: SceneTreeTimer = null
var _player_in_arena := false


func enter(_from: StringName) -> void:
	if boss == null:
		return
	_prepare_hidden()
	_connect_arena()
	_check_player_inside.call_deferred()


func exit(_to: StringName) -> void:
	# 去 entrance：只取消挂起的离场复位，不解除领地信号（见类注释）。
	_cancel_reset()


func update(delta: float) -> void:
	# 候场：站定，只保留重力（让悬空摆位的 BOSS 落回地面）。
	if boss == null:
		return
	boss.velocity.x = 0.0
	boss._apply_vertical_motion(delta)
	boss._apply_movement()


# ---- 隐藏与触发 ----

## 隐藏：全透明、关接触伤害、收招，并停掉可能残留的 BGM。
## SoulMaster 是飞行 BOSS（locomotion = flying.tres），候场时就悬停在场景摆位处，不受重力。
func _prepare_hidden() -> void:
	boss.modulate.a = 0.0
	boss.contact_damage_enabled = false
	boss.disable_melee_attack()
	boss.velocity = Vector2.ZERO
	var bgm := _bgm()
	if bgm != null and bgm.playing:
		bgm.stop()


## 领地信号只连一次；同时延迟一帧补查"开局玩家已在区域内"。
## AuZone 自己也是延迟一帧补发 player_entered，两条路都兜住。
func _connect_arena() -> void:
	if _arena_connected:
		return
	_arena = boss.arena_zone() if boss != null else null
	if _arena == null:
		# 没有领地的老布局：直接开演，别让 BOSS 永远不出现。
		_go_entrance.call_deferred()
		return
	if not _arena.player_entered.is_connected(_on_player_entered):
		_arena.player_entered.connect(_on_player_entered)
	if not _arena.player_exited.is_connected(_on_player_exited):
		_arena.player_exited.connect(_on_player_exited)
	_arena_connected = true


func _check_player_inside() -> void:
	if not is_inside_tree() or _arena == null or boss == null or boss.dead:
		return
	for b in _arena.get_overlapping_bodies():
		if b.is_in_group("player"):
			_player_in_arena = true
			_go_entrance()
			return


func _on_player_entered(_zone: Node, _player: Node2D) -> void:
	_player_in_arena = true
	_cancel_reset()
	_go_entrance()


## 切到入场演出。只有"仍在候场"时才开演：
## 战斗中玩家折返（出界又进来）不该重播浮现。
func _go_entrance() -> void:
	if boss == null or boss.dead:
		return
	if machine == null or machine.get_state_name() != name:
		return
	if not machine.states.has(BossStateNames.ENTRANCE):
		push_warning("SoulMaster: 缺少 entrance 状态节点，无法播放入场演出")
		return
	_cancel_reset()
	machine.set_state(BossStateNames.ENTRANCE)


# ---- 离场复位 ----

func _on_player_exited(_zone: Node, _player: Node2D) -> void:
	_player_in_arena = false
	# 场景销毁时 area body_exited 仍会回调一次，此时本节点已出树，get_tree() 为 null。
	if not is_inside_tree():
		return
	if not reset_on_player_exit or boss == null or boss.dead:
		return
	# 仍在候场 = 没有需要复位的东西（玩家只是进来又出去）。
	if machine == null or machine.get_state_name() == name:
		return
	_start_reset_delay()


func _start_reset_delay() -> void:
	if not is_inside_tree():
		return
	_cancel_reset()
	_reset_timer = get_tree().create_timer(reset_delay)
	_reset_timer.timeout.connect(_on_reset_timeout)


func _cancel_reset() -> void:
	if _reset_timer != null:
		if _reset_timer.timeout.is_connected(_on_reset_timeout):
			_reset_timer.timeout.disconnect(_on_reset_timeout)
		_reset_timer = null


func _on_reset_timeout() -> void:
	_reset_timer = null
	if _player_in_arena or boss == null or boss.dead:
		return
	_reset_encounter()


## 整场复位：退战斗 → 停 BGM → 回出生点满血 → 强制重进候场（enter() 重新隐身）。
## 约定与 HollowKnight 的 _reset_encounter 一致：只复位 BOSS 本身，关卡状态不回滚。
func _reset_encounter() -> void:
	if boss == null or boss.dead:
		return
	boss._set_combat(false)          # 清仇恨 + 广播 leave_combat（关卡可据此解锁 / 熄血条）
	var bgm := _bgm()
	if bgm != null and bgm.playing:
		bgm.stop()
	boss.velocity = Vector2.ZERO
	boss.knockback = Vector2.ZERO
	boss.global_position = boss.spawn_position
	boss.phase_index = 0
	boss.health = boss.initial_health
	boss._refresh_health_bar()
	if machine != null:
		machine.set_state(BossStateNames.DORMANT, true)


func _bgm() -> AudioStreamPlayer2D:
	if boss == null:
		return null
	return boss.get_node_or_null(bgm_path) as AudioStreamPlayer2D
