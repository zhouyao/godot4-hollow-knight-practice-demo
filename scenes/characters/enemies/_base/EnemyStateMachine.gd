extends StateMachine
class_name EnemyStateMachine


func _init() -> void:
	initial_state = EnemyStateNames.PATROL

func _ready() -> void:
	super._ready()
	if host != null:
		host.enemy_death.connect(_on_enemy_death)

func _on_enemy_death() -> void:
	set_state(EnemyStateNames.DEATH)
