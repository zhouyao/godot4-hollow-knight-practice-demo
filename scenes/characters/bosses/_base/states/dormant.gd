extends BossState

class_name BossDormantState

## BOSS 候场状态（dormant）的通用骨架。
##
## 只抽"调度"，不抽"演出"：
##   · 领地（AuZone）信号连一次且**永不断开** —— 玩家离场复位后仍要能收到进入/离开；
##   · 开局玩家已站在领地内时延迟一帧补查（AuZone 自己也会补发，两条路都兜住）；
##   · 可取消的 SceneTreeTimer（入场延迟 / 离场复位 / 苏醒缓冲）；
##   · 整场复位：退战斗 → 停 BGM → 回出生点满血 → 强制重进候场。
## 各 BOSS 的差异全部落在钩子里：隐身方式、锁链、战前 BGM、头部追踪等仍是各自的演出。
##
## 注意：本状态的 update() **不**统一做运动结算。飞行 BOSS 候场要站定（只保留重力），
## 而挂锁链的 BOSS 必须保持悬空，加了重力会掉下来破坏苏醒演出 —— 由子类钩子自行决定。

@export_group("候场流程")
## 入场演出状态名（SoulMaster = entrance / HollowKnight 不走本路径，见其 _on_arena_missing）。
@export var entrance_state: StringName = BossStateNames.ENTRANCE
## 玩家入场后到入场演出的停顿（秒）：先让玩家看清候场、镜头落位。
@export var entrance_delay: float = 2.0
## 玩家离场后是否整场复位。
@export var reset_on_player_exit: bool = true
## 离场复位前的缓冲时长（秒）：玩家出界又立刻折返时不复位。
@export var reset_delay: float = 2.0
## BGM 节点（相对 BOSS 根节点）。没有单独 BGM 的 BOSS 指向不存在的节点即可，调用是空操作。
@export var bgm_path: NodePath = ^"BGM"

var arena: AuZone
var player_in_arena := false
var _arena_connected := false
## 延迟计时器：key -> SceneTreeTimer；配套保存 timeout 回调，取消时才能断开连接。
var _delays: Dictionary = {}
var _delay_callbacks: Dictionary = {}


func enter(from: StringName) -> void:
	super.enter(from)
	_on_dormant_enter()
	_connect_arena()
	_check_player_inside.call_deferred()


func exit(to: StringName) -> void:
	# 只取消挂起的计时器：领地信号永不断开（见类注释）。
	_cancel_all_delays()
	_on_dormant_exit(to)


func update(delta: float) -> void:
	_on_dormant_update(delta)


# ---- 领地信号 ----
func _connect_arena() -> void:
	if _arena_connected:
		return
	arena = boss.arena_zone() if boss != null else null
	if arena == null:
		_on_arena_missing()
		return
	if not arena.player_entered.is_connected(_on_player_entered):
		arena.player_entered.connect(_on_player_entered)
	if not arena.player_exited.is_connected(_on_player_exited):
		arena.player_exited.connect(_on_player_exited)
	_arena_connected = true


## 开局玩家已站在领地内（时序不可靠）时补一次触发。
func _check_player_inside() -> void:
	if not is_inside_tree() or arena == null or boss == null or boss.dead:
		return
	for b in arena.get_overlapping_bodies():
		if b.is_in_group("player"):
			player_in_arena = true
			_on_player_inside_arena()
			return


func _on_player_entered(_zone: Node, _player: Node2D) -> void:
	player_in_arena = true
	cancel_delay(&"reset")
	_on_arena_entered()


func _on_player_exited(_zone: Node, _player: Node2D) -> void:
	player_in_arena = false
	# 场景销毁时 area body_exited 仍会回调一次，此时本节点已出树，get_tree() 为 null。
	if not is_inside_tree():
		return
	cancel_delay(&"entrance")
	_on_arena_exited()


# ---- 可取消的延迟计时 ----
## 注册一个延迟。同名 key 会被新的计时顶掉（先取消旧的）。
## 用 SceneTreeTimer 而不是 await：exit() 时能把挂起的回调断干净，避免上一轮复位
## 在玩家立刻折返后把新一轮演出提前收尾。
func schedule_delay(key: StringName, seconds: float, callback: Callable) -> void:
	cancel_delay(key)
	if seconds <= 0.0 or not is_inside_tree():
		callback.call()
		return
	var timer := get_tree().create_timer(seconds)
	var wrapped := func():
		_delays.erase(key)
		_delay_callbacks.erase(key)
		callback.call()
	_delays[key] = timer
	_delay_callbacks[key] = wrapped
	timer.timeout.connect(wrapped)


func cancel_delay(key: StringName) -> void:
	var timer := _delays.get(key) as SceneTreeTimer
	if timer != null:
		var cb: Callable = _delay_callbacks.get(key, Callable())
		if timer.timeout.is_connected(cb):
			timer.timeout.disconnect(cb)
	_delays.erase(key)
	_delay_callbacks.erase(key)


func has_delay(key: StringName) -> bool:
	return _delays.has(key)


func _cancel_all_delays() -> void:
	for key in _delays.keys():
		cancel_delay(key)


# ---- 入场 / 复位 ----
## 切到入场演出。已在计时则忽略，避免 player_entered 与开局补查重复触发时把演出无限推后。
func trigger_entrance(delay: float = -1.0, target: StringName = &"") -> void:
	if has_delay(&"entrance"):
		return
	var to := target if target != &"" else entrance_state
	var wait := entrance_delay if delay < 0.0 else delay
	if wait <= 0.0:
		_go_entrance(to)
	else:
		schedule_delay(&"entrance", wait, func(): _go_entrance(to))


## 只有"仍在候场"时才开演：战斗中玩家折返不该重播浮现。
func _go_entrance(to: StringName) -> void:
	if boss == null or boss.dead:
		return
	if machine == null or machine.get_state_name() != name:
		return
	if not machine.states.has(to):
		push_warning("BossDormantState: 缺少入场状态节点 '%s'，无法播放入场演出" % to)
		return
	cancel_delay(&"reset")
	machine.set_state(to)


## 整场复位：只复位 BOSS 本身，关卡状态不回滚。差异交给 _on_reset_extra()。
func reset_encounter() -> void:
	if boss == null or boss.dead:
		return
	boss._set_combat(false)          # 清仇恨 + 广播 leave_combat（关卡可据此解锁 / 熄血条）
	stop_bgm()
	boss.velocity = Vector2.ZERO
	boss.knockback = Vector2.ZERO
	boss.global_position = boss.spawn_position
	boss.phase_index = 0
	boss.health = boss.initial_health
	boss._refresh_health_bar()
	_on_reset_extra()
	if machine != null:
		machine.set_state(BossStateNames.DORMANT, true)


func bgm() -> AudioStreamPlayer2D:
	if boss == null or bgm_path.is_empty():
		return null
	return boss.get_node_or_null(bgm_path) as AudioStreamPlayer2D


func stop_bgm() -> void:
	var stream := bgm()
	if stream != null and stream.playing:
		stream.stop()


# ---- 钩子（演出内容由子类提供）----
func _on_dormant_enter() -> void: pass
func _on_dormant_exit(_to: StringName) -> void: pass
func _on_dormant_update(_delta: float) -> void: pass
func _on_player_inside_arena() -> void: pass
func _on_arena_entered() -> void: pass
func _on_arena_exited() -> void: pass
func _on_reset_extra() -> void: pass

## 领地缺失时的兜底：默认直接开演（没有领地也要让 BOSS 出现）。
## 靠砍锁链 / 关卡脚本唤醒的 BOSS 应覆盖为空，避免开局自动苏醒。
func _on_arena_missing() -> void:
	trigger_entrance.call_deferred()
