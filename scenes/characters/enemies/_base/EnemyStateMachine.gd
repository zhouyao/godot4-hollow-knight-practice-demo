extends StateMachine
class_name EnemyStateMachine


func _init() -> void:
	initial_state = EnemyStateNames.PATROL

func _ready() -> void:
	super._ready()
	# 关闭巡逻的怪出生后直接进 idle 状态（而非挂着 patrol 外壳）。
	# host 已在 super._ready() 内解析完毕，此处改 initial_state 会在父节点调用 start() 前生效。
	#
	# 只在 initial_state 仍是默认值（PATROL）时才重定向：子类（如 BossStateMachine）
	# 若在 _init() 里显式指定了初始状态（dormant 等），说明它有自己的开场流程，
	# 这里再按"关巡逻 → 进 idle"覆盖就会把它顶掉。
	# 现有小怪不受影响：它们的 initial_state 都是继承来的 PATROL（没有任何子类场景覆盖）。
	# 注意守卫只包住"重定向"这一段，不能提前 return —— 下面的死亡信号连接对任何敌人都要接。
	if initial_state == EnemyStateNames.PATROL \
			and host != null and not host.patrol_enabled \
			and states.has(EnemyStateNames.IDLE):
		initial_state = EnemyStateNames.IDLE
	if host != null:
		host.enemy_death.connect(_on_enemy_death)

func _on_enemy_death() -> void:
	set_state(EnemyStateNames.DEATH)
