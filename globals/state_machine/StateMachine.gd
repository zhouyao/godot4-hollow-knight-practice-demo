extends Node
class_name StateMachine

## 状态变化时发出，供 UI / 音频 / 动画等外部系统订阅
signal state_changed(new_state: StringName, old_state: StringName)

## 宿主节点，不绑定具体类型，敌人 / NPC / UI 都能复用
## 默认取父节点；也可在场景中通过 host_path 指定，解除对节点层级的隐式依赖
@export var host_path: NodePath
## 初始状态名。留空则不在 _ready 自动进入，由宿主在自身 _ready 末尾调用 start()/start(名字)。
## 之所以不自动启动：子节点的 _ready 先于宿主的 @onready 赋值，此时 enter() 会拿到未就绪的成员。
@export var initial_state: StringName = &""
## 可选调试输出：把当前状态名写进该 Label（相对于本节点）；留空则不输出任何 UI。
@export var debug_label: NodePath

var host: Node

## 运行状态开关；玩家死亡 / 对话 / 过场时置 false 可挂起整个状态机
var active: bool = true

## 子状态节点表：状态名(StringName) -> State 节点
var states: Dictionary = {}
var current_state: State
var current_state_name: StringName = &""
var previous_state_name: StringName = &""

## 过渡期间的重入保护：enter / exit / state_changed 回调中再次调用 set_state 时暂存，
## 待本次过渡结束后统一应用，避免嵌套过渡搅乱状态（last-wins 语义）
var _is_transitioning := false
var _pending_state: StringName = &""
var _pending_force := false

var _started := false
var _debug_label: Label
var _sfx_nodes: Dictionary = {}
var _sfx_resolved := false

func _ready() -> void:
	_collect_states()
	_resolve_host()
	_resolve_debug_label()

## 由宿主在自己的 _ready 末尾调用（此时宿主的 @onready 已就绪），进入初始状态。
## 传空则使用导出的 initial_state。重复调用等价于重启到该状态。
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

## 是否已完成启动（进入过初始状态）
func is_started() -> bool:
	return _started

## 自动收集直接子节点中继承自 State 的节点（也可由子类在 super._ready() 前 add_child 注入）
func _collect_states() -> void:
	states.clear()
	for child in get_children():
		if child is State:
			states[child.name] = child

## 运行时注册 / 注销状态（技能、Buff 带来的临时状态等动态场景）
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

func _resolve_debug_label() -> void:
	_debug_label = null
	if debug_label.is_empty():
		return
	var node := get_node_or_null(debug_label)
	if node is Label:
		_debug_label = node
	else:
		push_warning("StateMachine(%s): debug_label 指向的不是 Label：%s" % [name, debug_label])

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

## 切换状态：force 为 true 时允许重新进入当前状态（连击等需要重触发的场景）。
## 目标状态不存在会告警；过渡中的重入调用会被暂存到本次过渡结束后应用。
func set_state(target: StringName, force := false) -> void:
	if not states.has(target):
		push_warning("StateMachine(%s): 未知状态 '%s'，已忽略（检查子节点名是否拼错）" % [name, target])
		return

	if target == current_state_name and not force:
		return

	# 过渡未结束（重入）：暂存目标，本次过渡结束后再应用
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
	_update_debug_label(target)
	_is_transitioning = false

	if _pending_state != &"":
		var next := _pending_state
		var next_force := _pending_force
		_pending_state = &""
		_pending_force = false
		set_state(next, next_force)

func _update_debug_label(new_state: StringName) -> void:
	if _debug_label != null:
		_debug_label.text = new_state

## 播放宿主侧音效；宿主用 Dictionary 类型的 audio_nodes 声明即可（{名字: AudioStreamPlayer2D}）。
## 首次调用时解析一次并缓存，不做每帧的动态属性查找。
func play_sfx(key: StringName) -> void:
	_resolve_sfx_nodes()
	var stream := _sfx_nodes.get(key) as AudioStreamPlayer2D
	if stream:
		stream.play()

## 停止宿主侧音效；节点不存在则安全跳过。
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

## 供外部（UI / 调试）读取当前 / 上一状态名
func get_state_name() -> StringName:
	return current_state_name

func get_previous_state_name() -> StringName:
	return previous_state_name
