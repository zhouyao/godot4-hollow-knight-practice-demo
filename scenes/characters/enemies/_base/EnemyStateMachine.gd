extends StateMachine
class_name EnemyStateMachine


func _init() -> void:
	initial_state = EnemyStateNames.PATROL

func _ready() -> void:
	super._ready()
	# 关闭巡逻的怪出生后直接进 idle 状态（而非挂着 patrol 外壳）。
	# host 已在 super._ready() 内解析完毕，此处改 initial_state 会在父节点调用 start() 前生效。
	if host != null and not host.patrol_enabled \
			and states.has(EnemyStateNames.IDLE):
		initial_state = EnemyStateNames.IDLE
	if host != null:
		host.enemy_death.connect(_on_enemy_death)

func _on_enemy_death() -> void:
	set_state(EnemyStateNames.DEATH)
