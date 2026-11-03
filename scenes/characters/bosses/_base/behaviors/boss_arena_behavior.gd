extends AuZoneBehavior
class_name BossArenaBehavior


## BOSS 竞技场行为：玩家踏入即开战。
##
## 替代原 boss_arena.gd（BossArena）里的"踏入 → boss.begin_fight()"逻辑。
## 宿主 AuZone 已用 target_group="player" + detect_mask 过滤，这里只管触发，
## 业务不写在 AuZone 里（AuZone 刻意保持无业务逻辑）。
##
## 开战走 Boss.begin_fight()（→ EnemyAggro.enter_combat_zone → enter_combat 信号），
## 与领地（AuZone / EnemyZone）开战是同一条路径。begin_fight() 自身会防重入 / 死亡。


## 玩家踏入竞技场时自动开战。
## 关掉则由关卡脚本在演出结束时（如锁链全部砍断、过场播完）手动调 boss.begin_fight()。
@export var auto_start_fight: bool = true


## 绑定的 BOSS：玩家踏入竞技场时调用其 begin_fight()。
## 留空则退回旧逻辑（取宿主 AuZone 的父节点作为 BOSS），兼容尚未迁移的场景。
@export var boss_node: NodePath = NodePath()


## 目标进入宿主区域：触发 BOSS 开战。
func on_entered(_body: Node2D) -> void:
	if not auto_start_fight:
		return
	var zone := get_zone()
	if zone == null:
		return
	var boss := _resolve_boss()
	if boss != null and boss.has_method("begin_fight"):
		boss.begin_fight()


## 解析绑定的 BOSS：优先用 boss_node；为空时兼容"竞技场挂在 BOSS 下"的旧布局。
func _resolve_boss() -> Node:
	if boss_node != null and not boss_node.is_empty():
		return get_node_or_null(boss_node)
	var zone := get_zone()
	if zone != null:
		return zone.get_parent()
	return null
