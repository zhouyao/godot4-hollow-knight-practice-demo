extends BossState
class_name SoulMasterTeleportState

## 闪现：原地播 Animation/ActionAnimationPlayer 的 teleport（1.4s），在动画中段瞬移到随机落点。
##
## 落点区域（比领地小，位置可配置）有三种配法：
##   1. 默认：BossSoulMaster.teleport_area 留空 → 按 BossArena 自动取 area_scale（默认 2/3），
##      中心落在领地的 area_anchor 处（默认 0.5, 0.5 = 居中）。改 anchor 就能整体挪动区域。
##   2. 关卡里选中 SoulMaster 实例，填「闪现 / Teleport Area」= 世界坐标 Rect2，
##      直接指定区域的左上角与宽高（BOSS 根节点导出，实例上可直接覆写）。
##   3. 区域最终都会被裁进 BossArena，保证闪现始终发生在领域内、不会跑到墙外。
## 无 BossArena 且未配置区域时退回出生点附近的兜底矩形。
##
## 动画自带逐帧、teleport_effect 特效与 Audio/teleport 音效，状态里不重复播音效。
## 唯一由状态生成的特效是「位移轨迹粒子」（effects/teleport_trail.tscn）：
## 动画里的 teleport_effect 只是原地一团光，又会跟着 BOSS 一起被搬到落点，
## 表现不出「A 点闪到 B 点」的路径，所以瞬移那一帧额外在起点与落点之间铺一条 splatter 轨迹。
## 相位用计时器推进，不依赖 animation_finished。

const ANIM: StringName = &"teleport"

## 瞬移轨迹粒子：起点炸开 + 沿线铺点 + 落点炸开，播完自毁。
const TRAIL_SCENE: PackedScene = preload(
		"res://scenes/characters/bosses/soul_master/effects/teleport_trail.tscn")

@export_group("闪现区域")
## 自动模式下，区域尺寸相对领地的比例（默认宽高各 2/3）。
@export var area_scale: Vector2 = Vector2(2.0 / 3.0, 2.0 / 3.0)
## 自动模式下，区域中心在领地内的相对位置：(0,0)=领地左上，(1,1)=右下，(0.5,0.5)=居中。
@export var area_anchor: Vector2 = Vector2(0.5, 0.5)
## 把配置 / 自动算出的区域裁进领地（推荐开启）。
@export var clamp_to_arena: bool = true
## 没有领地也没配置区域时的兜底半径（以出生点为中心）。
@export var fallback_extent: Vector2 = Vector2(600.0, 200.0)

@export_group("闪现节奏")
## 动画开始后第几秒执行瞬移：1.0s 对齐 clip 的施法音方法轨道与出现特效段。
@export var blink_time: float = 1.0
## 场景里没有 teleport clip 时的兜底时长。
@export var fallback_length: float = 1.4
## 落点距当前位置的最小距离，避免"闪了等于没闪"；0 = 不限制。
@export var min_travel: float = 240.0
## 落点与玩家的最小距离，避免直接压在玩家身上；0 = 不限制。
@export var player_clearance: float = 160.0
## 为满足上面两个约束最多重抽几次；用尽则接受最后一次候选。
@export var max_tries: int = 8
## 落点距地面顶部的净空（BOSS 碰撞圆半径约 142），0 = 不检查。
@export var ground_clearance: float = 160.0

@export_group("闪现轨迹")
## 是否生成「起点 → 落点」的粒子轨迹。
@export var trail_enabled: bool = true
## 轨迹特效相对 BOSS 的层级偏移：0 = 同层（本帧后加入，画在 BOSS 之上），-1 = 藏到身后。
@export var trail_z_offset: int = 0

var _timer := 0.0
var _duration := 1.4
var _blinked := false


func enter(_from: StringName) -> void:
	if boss == null:
		return
	boss.disable_melee_attack()
	boss.velocity = Vector2.ZERO
	_timer = 0.0
	_blinked = false
	_duration = maxf(anim_length(ANIM, fallback_length), blink_time)
	play_action(ANIM)


func update(delta: float) -> void:
	if boss == null:
		return
	# 闪现期间站定；接触伤害在下方按 _blinked 单独结算（消失阶段不该蹭到玩家）。
	stand_still(delta, false)

	_timer += delta
	if not _blinked and _timer >= blink_time:
		_blink()
	# 只在"已经出现在新位置"之后结算：消失阶段不该蹭到玩家。
	if _blinked:
		_tick_contact()
	if _timer >= _duration:
		go_idle()


func exit(_to: StringName) -> void:
	if boss != null:
		boss.velocity = Vector2.ZERO


# ---- 闪现区域 ----

## 本次闪现可用的矩形：优先用 BOSS 根节点上配置的 teleport_area，否则按领地自动算。
func _blink_rect() -> Rect2:
	var arena := boss.arena_rect()
	var has_arena := arena.size.x > 0.0 and arena.size.y > 0.0
	var sm := boss as BossSoulMaster
	var configured: Rect2 = sm.teleport_area if sm != null else Rect2()
	if configured.size.x <= 0.0 or configured.size.y <= 0.0:
		if not has_arena:
			push_warning("SoulMaster: 未找到 BossArena，闪现改用出生点兜底范围")
			return Rect2(boss.spawn_position - fallback_extent, fallback_extent * 2.0)
		configured = _auto_rect(arena)

	if has_arena and clamp_to_arena:
		var clamped := _clamp_inside(configured, arena)
		if clamped.size.x > 0.0 and clamped.size.y > 0.0:
			return clamped
		push_warning("SoulMaster: 闪现区域完全落在领地外，已回退到领地内的自动区域")
		return _auto_rect(arena)
	return configured


## 自动区域：尺寸 = 领地 × area_scale，中心 = 领地内 area_anchor 处。
func _auto_rect(arena: Rect2) -> Rect2:
	var s := Vector2(clampf(area_scale.x, 0.01, 1.0), clampf(area_scale.y, 0.01, 1.0))
	var size := arena.size * s
	var anchor := Vector2(clampf(area_anchor.x, 0.0, 1.0), clampf(area_anchor.y, 0.0, 1.0))
	var center := arena.position + arena.size * anchor
	return Rect2(center - size * 0.5, size)


## 把 rect 裁进领地：左上角夹到领地内，右下角不越过领地边界。
func _clamp_inside(rect: Rect2, arena: Rect2) -> Rect2:
	var x := clampf(rect.position.x, arena.position.x, arena.end.x)
	var y := clampf(rect.position.y, arena.position.y, arena.end.y)
	return Rect2(x, y,
			clampf(rect.end.x - x, 0.0, arena.end.x - x),
			clampf(rect.end.y - y, 0.0, arena.end.y - y))


# ---- 落点与瞬移 ----

## 抽一个随机落点：不插进地面，尽量离当前位置够远、且不压在玩家身上。
func _pick_position(rect: Rect2) -> Vector2:
	var p := boss.get_player()
	var candidate := Vector2.ZERO
	for _i in maxi(1, max_tries):
		candidate = Vector2(
				randf_range(rect.position.x, rect.end.x),
				randf_range(rect.position.y, rect.end.y))
		candidate = _above_ground(candidate, rect)
		if candidate.distance_to(boss.global_position) < min_travel:
			continue
		if p != null and player_clearance > 0.0 \
				and candidate.distance_to(p.global_position) < player_clearance:
			continue
		break
	return candidate


## 地面净空：把落点 y 收到「地面顶部 - ground_clearance」之上，且仍留在配置区域内。
func _above_ground(pos: Vector2, rect: Rect2) -> Vector2:
	if ground_clearance <= 0.0:
		return pos
	var ground_y := boss.ground_y_at(pos.x, INF)
	if is_inf(ground_y):
		return pos
	var y_max := minf(rect.end.y, ground_y - ground_clearance)
	return Vector2(pos.x, clampf(pos.y, rect.position.y, maxf(rect.position.y, y_max)))


func _blink() -> void:
	_blinked = true
	# 顺序不能反：先记住起点 → 再算落点 → 再铺轨迹 → 最后才真的瞬移。
	# 轨迹要落在「旧位置 → 新位置」这条线上，等瞬移完再取起点就晚了。
	var from_pos := boss.global_position
	var to_pos := _pick_position(_blink_rect())
	_spawn_trail(from_pos, to_pos)
	# 瞬变 + 重置所有子节点插值 + 出现后朝向玩家，统一走 Boss.teleport_to()。
	boss.teleport_to(to_pos, true)


# ---- 位移轨迹特效 ----

## 在「起点 → 落点」之间生成一条 spatter 粒子轨迹，特效播完自行销毁。
## 挂在 BOSS 的父节点上（与 entrance.gd 的黑光同一套路）：BOSS 本身会瞬移，
## 挂在 BOSS 身上轨迹会被一起搬到落点；父节点上的特效也不继承 BOSS 的 modulate。
func _spawn_trail(from_pos: Vector2, to_pos: Vector2) -> void:
	if not trail_enabled or boss == null or not is_instance_valid(boss):
		return
	# 与 BOSS 同层（z_as_relative 跟随 BOSS 配置，trail_z_offset=0）：
	# 本帧最后加入的兄弟节点，同一 z_index 下画在 BOSS 之上（设 -1 会被地面盖住）。
	var fx := boss.spawn_attached_fx(TRAIL_SCENE, from_pos, trail_z_offset) as SoulMasterTeleportTrail
	if fx == null:
		return
	fx.play_trail(from_pos, to_pos)
