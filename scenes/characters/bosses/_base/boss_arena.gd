class_name BossArena
extends Area2D


## BOSS 竞技场：玩家踏入即开战。
##
## 用 Area2D 而不是纯 Node —— 进出判定直接吃物理层，不必自己每帧算距离。
## 需要在检查器给本节点配一个 CollisionShape2D，并把 collision_mask 勾上 Player 层（第 1 位），
## 否则收不到进出信号。
##
## 开战走 Enemy 现成的 enter_combat_zone()（由 EnemyAggro 提供），并因此广播 enter_combat
## 信号 —— 与领地（EnemyZone / AuZone）开战是同一条路径，不需要为 BOSS 另开一套。

## 玩家踏入竞技场。
signal player_entered_arena
## 玩家离开竞技场。
signal player_exited_arena

## 玩家踏入时自动开战。
## 关掉则由关卡脚本在演出结束时（如锁链全部砍断、过场播完）手动调 boss.begin_fight()。
@export var auto_start_fight: bool = true

## 宿主 BOSS。本节点是 boss.tscn 的直接子节点，故取父节点。
@onready var boss: Boss = get_parent() as Boss


func _ready() -> void:
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)
	if not body_exited.is_connected(_on_body_exited):
		body_exited.connect(_on_body_exited)


func _on_body_entered(body: Node2D) -> void:
	if body == null or not body.is_in_group("player"):
		return
	player_entered_arena.emit()
	if auto_start_fight and boss != null:
		boss.begin_fight()


func _on_body_exited(body: Node2D) -> void:
	if body == null or not body.is_in_group("player"):
		return
	player_exited_arena.emit()
