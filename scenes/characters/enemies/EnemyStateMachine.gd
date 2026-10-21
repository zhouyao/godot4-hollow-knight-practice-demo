extends StateMachine

## 与 PlayerInitialStateMachine 同构：初始状态写死在 _init 里，
## 宿主的 enemy_death 信号直接切到 death 状态（玩家侧是 player_death → death）。

func _init() -> void:
	initial_state = EnemyStateNames.IDLE

func _ready() -> void:
	super._ready()
	if host != null:
		host.enemy_death.connect(_on_enemy_death)

func _on_enemy_death() -> void:
	set_state(EnemyStateNames.DEATH)
