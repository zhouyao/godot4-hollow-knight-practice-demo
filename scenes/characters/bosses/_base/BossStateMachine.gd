class_name BossStateMachine
extends EnemyStateMachine


## 出招节奏：每隔 decision_interval 秒重新决策一次（也是贴身追击时 idle 的喘息/前摇，
## 越小越跟手；设 0.2 即每次回到 idle 仅站 0.2s 就决策，避免跟放风筝玩家时一顿一顿）。
## 全局生效，不随具体状态重复配置（决策中枢 idle 通过 machine.decision_interval 读取）。
@export var decision_interval: float = 0.1


## BOSS 状态机。
##
## 与 EnemyStateMachine 的两点差异：
##   1. 初始状态是 dormant（沉睡 / 挂锁链），不是 patrol。
##      EnemyStateMachine._ready() 里"关巡逻 → 进 idle"的重定向只对默认 PATROL 生效，
##      不会顶掉这里指定的 dormant（见该函数的守卫注释）。
##   2. 死亡转 defeat，不是 death —— 击败演出由 BOSS 自己的状态接管。
##
## 状态分两层，但共用同一个状态机：
##   流程层  dormant / intro / combat / phase_transition / defeat
##   招式层  slashes / dash / ... 一律由 combat 选出，播完回到 combat。
## 不拆成两个 StateMachine 节点的原因：招式需要"选完立刻切"，
## 单状态机的 set_state() 天然支持；拆两个还得额外处理 active 开关与两套抢占顺序。

func _init() -> void:
	initial_state = BossStateNames.DORMANT


func _on_enemy_death() -> void:
	set_state(BossStateNames.DEFEAT)
