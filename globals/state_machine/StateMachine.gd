extends Node
class_name StateMachine


## 状态切换完成后发出（旧状态 exit 之后、新状态 enter 之后）。
## 参数 new_state：切换到的状态名；old_state：切换前的状态名，首次进入时为 &""。
## 注意本信号在过渡过程中发出，回调里再调 set_state() 会被暂存、等本次过渡结束后才生效。
signal state_changed(new_state: StringName, old_state: StringName)

## 宿主节点路径（状态机操作的对象）。留空则取状态机的父节点。
@export var host_path: NodePath
## 启动时进入的初始状态名（与子节点名一致）。留空则 start() 必须显式传入状态名。
@export var initial_state: StringName = &""

var host: Node

var active: bool = true

var states: Dictionary = {}
var current_state: State
var current_state_name: StringName = &""
var previous_state_name: StringName = &""

var _is_transitioning := false
var _pending_state: StringName = &""
var _pending_force := false

var _started := false
var _sfx_nodes: Dictionary = {}
var _sfx_resolved := false

func _ready() -> void:
	_collect_states()
	_resolve_host()

func start(state_name: StringName = &"") -> void:
	if state_name == &"":
		state_name = initial_state
	if state_name == &"":
		push_warning("StateMachine(%s): 未指定初始状态，请在检查器设置 initial_state 或调用 start(名字)" % name)
		return
	if not states.has(state_name):
		push_warning("StateMachine(%s): 初始状态 '%s' 不存在" % [name, state_name])
		return
	_started = true
	active = true
	set_state(state_name, true)

func is_started() -> bool:
	return _started

func _collect_states() -> void:
	states.clear()
	for child in get_children():
		if child is State:
			states[child.name] = child

func add_state(state: State) -> void:
	if state == null:
		return
	if state.get_parent() != self:
		state.name = state.name if not state.name.is_empty() else "state"
		add_child(state)
	states[state.name] = state

func remove_state(state_name: StringName) -> void:
	if not states.has(state_name):
		return
	var state := states[state_name] as State
	states.erase(state_name)
	if state == null:
		return
	if current_state == state:
		current_state = null
		current_state_name = &""
	state.queue_free()

func _resolve_host() -> void:
	if host_path.is_empty():
		host = get_parent()
	else:
		host = get_node_or_null(host_path)
	if host == null:
		push_warning("StateMachine(%s): 宿主解析失败，请检查 host_path=%s" % [name, host_path])

func _physics_process(delta: float) -> void:
	if not active or current_state == null:
		return
	current_state.elapsed += delta
	current_state.update(delta)
	var target := current_state.get_transition(delta)
	if target != &"":
		set_state(target)

func _unhandled_input(event: InputEvent) -> void:
	if not active or current_state == null:
		return
	current_state.handle_input(event)

func set_state(target: StringName, force := false) -> void:
	if not states.has(target):
		push_warning("StateMachine(%s): 未知状态 '%s'，已忽略（检查子节点名是否拼错）" % [name, target])
		return

	if target == current_state_name and not force:
		return

	if _is_transitioning:
		_pending_state = target
		_pending_force = force
		return

	_is_transitioning = true
	var old := current_state_name
	if current_state != null:
		current_state.exit(target)
	current_state = states[target]
	previous_state_name = old
	current_state_name = target
	current_state.elapsed = 0.0
	current_state.enter(old)
	state_changed.emit(target, old)
	_is_transitioning = false

	if _pending_state != &"":
		var next := _pending_state
		var next_force := _pending_force
		_pending_state = &""
		_pending_force = false
		set_state(next, next_force)

func play_sfx(key: StringName) -> void:
	_resolve_sfx_nodes()
	var stream := _sfx_nodes.get(key) as AudioStreamPlayer2D
	if stream:
		stream.play()

func stop_sfx(key: StringName) -> void:
	_resolve_sfx_nodes()
	var stream := _sfx_nodes.get(key) as AudioStreamPlayer2D
	if stream:
		stream.stop()

func _resolve_sfx_nodes() -> void:
	if _sfx_resolved or host == null:
		return
	_sfx_resolved = true
	var nodes = host.get("audio_nodes")
	_sfx_nodes = nodes if nodes is Dictionary else {}

func get_state_name() -> StringName:
	return current_state_name

func get_previous_state_name() -> StringName:
	return previous_state_name
