class_name EnemyAggro
extends RefCounted


## 敌人感知与仇恨的全部状态与实现：视线、牵引（leash）、领地绑定、丢失计时、出界宽限。
##
## 原先堆在 Enemy 里（约 180 行）。搬走之后 Enemy 只保留：
##   · 配置导出项（leash_range / combat_lose_time / enemy_zone …），
##   · 信号的广播点 _set_combat()，
##   · 一行转发。
## 因此 8 个状态脚本（chase / patrol / return …）的调用面完全不变。
##
## 为什么 _set_combat() 留在 Enemy 上：enter_combat / leave_combat 是 Enemy 的信号，
## 由信号的拥有者负责广播，子系统只管计时与判定 —— 这样"谁拥有信号谁广播"不会被打破。

## 战斗丢失计时器：累计"目标丢失 / 出 leash / 无视线"的时长，达到 combat_lose_time 即丢战。
var combat_timer: float = 0.0
## 当前是否处于战斗（仇恨）状态。
var combat_active: bool = false

## 绑定的领地节点（setup 时解析并缓存），null = 没配 / 路径失效。
var _zone_node: Node = null
## 玩家此刻是否在领地里。由领地的 player_entered / player_exited 维护。
## 领地是"持续条件"而不是一次性的"进场事件"：只要这个值为 true，本敌人既不会因为
## 超出 leash 而追丢，也会在待机状态下自动重新开战 —— 否则玩家开局就站在领地里时，
## 第一次开战一旦被丢弃（超出 leash / 够不到人 / 视线中断），就再也不会重新开战。
var _player_in_zone: bool = false
## 离开领地后的追击宽限剩余时长（秒）：> 0 表示玩家已出领地、本敌人仍在追。
## 归零的那一帧由 tick_combat() 收兵回巢；玩家重新踏进领地时由 enter 回调清零。
var _zone_exit_timer: float = 0.0

## 宿主敌人引用。故意不标类型（不用 `: Enemy`），否则会与 enemy.gd 形成
## class_name 循环引用，导致本脚本解析失败（"Cyclic reference"）。所有字段 / 方法
## 访问都走动态派发，运行期行为完全一致。
var _enemy


## 绑定宿主并接上领地信号。必须在 _ready() 内、早于 state_machine.start()。
func setup(enemy) -> void:
	_enemy = enemy
	_bind_enemy_zone()


## ---- 感知 ----

## 视线检测用的碰撞层：默认沿用 collision_mask。
## 水下怪等可在 Locomotion.sight_mask 上单独指定（例如让视线穿过水体本身），0 = 沿用。
func _sight_mask() -> int:
	var loc = _enemy.locomotion
	if loc != null:
		return loc.get_sight_mask(_enemy.collision_mask)
	return _enemy.collision_mask


## 玩家是否在视线内（无遮挡）。use_line_of_sight = false 时恒为 true。
func has_line_of_sight() -> bool:
	if not _enemy.use_line_of_sight:
		return true
	var p = _enemy.get_player()
	if p == null:
		return false
	var space = _enemy.get_world_2d().direct_space_state
	var query := PhysicsRayQueryParameters2D.create(_enemy.global_position, p.global_position)
	query.collision_mask = _sight_mask()
	query.exclude = [_enemy.get_rid()]
	var result = space.intersect_ray(query)
	if result.is_empty():
		return true
	return result.get("collider", null) == p


## 目标是否仍在牵引范围内（出生点 leash_range 内）。未开战时视为在范围内。
## 三种情况不参与判定：
##   1. 玩家还在领地内 —— 领地即防区，一律算"没追丢"。这一条是必须的：领地宽度常常
##      远大于 leash_range（level_1 的 EnemyZone / EnemyZone2 宽 1000 / 1200px，leash 默认 700），
##      只按出生点算半径会把"站在自己领地里的玩家"判成追丢，怪当场收兵，
##      看起来就是"玩家进了领地，怪根本不攻击"。
##   2. 玩家刚出领地、仍在 zone_exit_chase_time 宽限内 —— 见 tick_combat() 的短路分支，
##      本函数在宽限期内根本不会被调用。
##   3. 宽限结束、战斗已结束 —— combat_active 为 false，走第一个分支直接返回 true。
## 所以 leash_range 对绑了领地的怪只在"被偷袭开战且玩家不在领地内"时真正起作用。
func is_within_leash() -> bool:
	if not combat_active:
		return true
	var p = _enemy.get_player()
	if p == null:
		return false
	if player_in_zone():
		return true
	return _enemy.spawn_position.distance_to(p.global_position) <= _enemy.leash_range


## ---- 仇恨状态 ----

## 切换战斗状态并复位两个计时器。
## 返回 true 表示真的发生了切换（宿主据此更新 target 并广播信号），false = 新旧一致、无副作用。
func set_combat(active: bool, new_target: Node2D) -> bool:
	if combat_active == active:
		return false
	combat_active = active
	combat_timer = 0.0
	# 开战 / 收兵都清掉领地追击宽限，避免上一轮的残留计时把新一轮追击提前掐断。
	_zone_exit_timer = 0.0
	if active and new_target != null:
		_enemy.target = new_target
	return true


## 令本敌人开战。三个调用方：领地（EnemyZone/AuZone）进入、接触命中
## （EnemyState._tick_contact → idle / patrol 的 _contact_opens_combat）、受击（take_damage）。
## 名字带 zone 是历史原因（最早只有领地会触发），现在不是领地专用。
func enter_combat_zone() -> void:
	if _enemy.dead:
		return
	_enemy._set_combat(true)


## ---- 逐帧：领地 ----

## 领地是持续条件：玩家还在领地内、而本敌人正处在休息状态（idle / patrol）时，
## 重新开战。只从休息状态重启，是为了避免 chase 因为"够不到人 / 视线中断"丢战之后
## 被逐帧拉回 chase，导致 chase ↔ return 每帧互切、动作动画疯狂闪。
## 丢战后敌人先回家（return），回到休息状态时若玩家仍在领地内就会再次扑上来。
func tick_zone_aggro() -> void:
	if combat_active or _enemy.dead or not _player_in_zone or _enemy.state_machine == null:
		return
	if not _enemy.state_machine.is_started() \
			or _enemy.state_machine.get_state_name() != _enemy.resting_state():
		return
	enter_combat_zone()


## 领地追击宽限的计时与收尾，逐物理帧跑。
## 放在这里而不是 tick_combat：tick_combat 只有 chase / attack 调用，
## 玩家消失时 chase 会提前 return，idle 播 appear 演出、hurt 硬直期间也完全不调用它 ——
## 计时若挂在 tick_combat 里，这些情况下宽限永远推不完，怪会一直挂着仇恨。
## 另外"宽限"只服务于"继续追"：目标已经不存在（死亡 / 切场景）就没必要等满时间，
## 否则怪会在原地发呆整整 zone_exit_chase_time 才回巢。
func tick_exit_grace(delta: float) -> void:
	if _zone_exit_timer <= 0.0:
		return
	if _enemy.dead:
		_zone_exit_timer = 0.0  # 尸体不追击，也别在死后补发一次 leave_combat
		return
	if not combat_active:
		_zone_exit_timer = 0.0  # 战斗已被别处结束（出介质 / 够不到人）：宽限一并作废
		return
	if _enemy.get_player() == null:
		_enemy._set_combat(false)  # _set_combat 内部会清零宽限
		return
	_zone_exit_timer -= delta
	if _zone_exit_timer <= 0.0:
		_zone_exit_timer = 0.0
		_enemy._set_combat(false)  # 宽限用完：收兵回巢（chase / attack 下一帧转 RETURN）


## 领地绑定：进场 / 离场两个信号都要接。
## 只接 player_entered 是旧实现的缺陷 —— 那让"领地"退化成一次性事件，
## 玩家一直在领地内但敌人中途丢了战（超出 leash、够不到人、视线中断）后就不会再开战。
## 用 has_signal 鸭子类型判定：旧版 EnemyZone 与 AuZone 都提供这一对同名信号，
## 插件缺席时也只是退化为"不通过领地开战"，不会编译失败。
func _bind_enemy_zone() -> void:
	_zone_node = null
	_player_in_zone = false
	if _enemy.enemy_zone.is_empty():
		return
	_zone_node = _enemy.get_node_or_null(_enemy.enemy_zone)
	if _zone_node == null:
		push_warning("%s: 绑定的领地 %s 解析失败，领地开战不会生效"
				% [_enemy.name, _enemy.enemy_zone])
		return
	if _zone_node.has_signal("player_entered") \
			and not _zone_node.player_entered.is_connected(_on_zone_player_entered):
		_zone_node.player_entered.connect(_on_zone_player_entered)
	if _zone_node.has_signal("player_exited") \
			and not _zone_node.player_exited.is_connected(_on_zone_player_exited):
		_zone_node.player_exited.connect(_on_zone_player_exited)


## 领地（EnemyZone/AuZone）进入回调：玩家踏入本敌人绑定的领地时开战。
## 中途折返也要清掉上一轮留下的追击宽限，否则玩家"出界又回来"会被旧倒计时当场掐断。
func _on_zone_player_entered(_zone: Node, _player: Node2D) -> void:
	_player_in_zone = true
	_zone_exit_timer = 0.0
	enter_combat_zone()


## 领地离开回调：玩家走出领地后不立刻罢手，先按 zone_exit_chase_time 再追一段。
## 旧实现在这里直接 _set_combat(false)，表现为"玩家一跨出边界，怪瞬间原地转身回家"，
## 手感上很割裂 —— 玩家刚被追到边界，逃离的动作还没做完，威胁就凭空消失了。
## 现在改为宽限计时：宽限内照常追击，计时归零（见 tick_exit_grace）才收兵回巢；
## 宽限期内玩家若重新踏回领地，enter 回调会把计时清零，追击无缝延续。
## zone_exit_chase_time = 0 时退回旧行为（立刻罢手）。
func _on_zone_player_exited(_zone: Node, _player: Node2D) -> void:
	_player_in_zone = false
	if _enemy.dead or not combat_active:
		return
	if _enemy.zone_exit_chase_time <= 0.0:
		_enemy._set_combat(false)
		return
	_zone_exit_timer = _enemy.zone_exit_chase_time


## ---- 战斗丢失计时 ----

## 推进战斗丢失计时：目标丢失 / 出 leash / 无视线时累计，达到 combat_lose_time 则丢战。
## 玩家刚出领地的那段追击（zone_exit_chase_time）单独计时，优先级高于上面三条，
## 期间不判任何"追丢"条件 —— 见下面的短路分支。
func tick_combat(delta: float) -> void:
	if not combat_active:
		return
	# 领地追击宽限：玩家已踏出领地但仍允许再追一会儿。
	# 这段计时必须优先于下面的 leash / 视线判定 —— 玩家刚出边界时往往已超出 leash，
	# 若照旧累计 combat_timer，宽限期会被"追丢"逻辑提前掐掉。
	# 宽限的计时与收尾不在这里做，见 tick_exit_grace()：本函数只在 chase / attack
	# 里被调用，玩家消失时 chase 会提前 return，宽限将永远推不完。
	if _zone_exit_timer > 0.0:
		return
	var p = _enemy.get_player()
	var lost := false
	if p == null:
		lost = true
	elif not is_within_leash():
		lost = true
	elif _enemy.use_line_of_sight and not has_line_of_sight():
		lost = true
	if lost:
		combat_timer += delta
	else:
		combat_timer = 0.0
	if combat_timer >= _enemy.combat_lose_time:
		_enemy._set_combat(false)


## 玩家此刻是否在本敌人绑定的领地里。没配领地 / 领地已失效时为 false。
func player_in_zone() -> bool:
	if _zone_node == null or not is_instance_valid(_zone_node):
		return false
	return _player_in_zone
