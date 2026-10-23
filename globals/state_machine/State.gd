extends Node
class_name State


func enter(_from: StringName) -> void: pass

func exit(_to: StringName) -> void: pass

func update(_delta: float) -> void: pass

func handle_input(_event: InputEvent) -> void: pass

func get_transition(_delta: float) -> StringName: return &""

var elapsed: float = 0.0

var _machine: StateMachine

var machine: StateMachine:
	get:
		if _machine == null or not is_instance_valid(_machine):
			_machine = get_parent() as StateMachine
		return _machine

var host: Node:
	get: return machine.host if machine != null else null

func _play_audio(key: StringName) -> void:
	if machine == null:
		return
	machine.play_sfx(key)

func _stop_audio(key: StringName) -> void:
	if machine == null:
		return
	machine.stop_sfx(key)
