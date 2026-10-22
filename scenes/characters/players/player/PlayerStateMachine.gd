extends StateMachine


func _init() -> void:
	initial_state = PlayerStateNames.IDLE

func _ready() -> void:
	super._ready()
	if host != null:
		host.player_death.connect(_on_player_death)

func _on_player_death() -> void:
	set_state(PlayerStateNames.DEATH)
