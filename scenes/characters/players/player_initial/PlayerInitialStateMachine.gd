extends StateMachine

## 玩家状态机：只负责"宿主特有的接线"，通用能力都在 StateMachine / PlayerState 里。
## 初始状态通过检查器的 initial_state（或场景里写死）指定，不要再在代码里硬编码。

func _init() -> void:
	initial_state = PlayerStateNames.IDLE

func _ready() -> void:
	super._ready()
	if host != null:
		host.player_death.connect(_on_player_death)

# 以后加"任意状态下都能进"的状态（受击 / 冲刺 / 复活），优先改成 StateMachine 的全局过渡，
# 而不是在这里一条条连线。
func _on_player_death() -> void:
	set_state(PlayerStateNames.DEATH)
