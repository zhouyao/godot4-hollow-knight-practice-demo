extends BossState
class_name SoulMasterEntranceState

## SoulMaster 入场演出：先让 BOSS 从完全透明缓缓浮现（透明度 + 起止震屏）+ 起 BGM，
## 完全现身之后才放黑光扩散，演出结束后 begin_fight() 开战并转入 idle。
##
## 两个必须处理的点，否则整段演出都看不见 BOSS：
##   1. 场景里主精灵默认停在 teleport 第 6 帧（几乎全透明的"消失帧"），
##      候场 / 入场都不播主动画 —— 必须先切到 idle，modulate 淡入才有东西可显。
##   2. 黑光是绝对置顶层，会连 BOSS 一起盖住 —— 演出期间把 BOSS 临时抬到它之上。
## 另外两段必须串行：黑光若与浮现同时放，玩家只看得到黑光。
##
## 本状态只负责"出现"这一段；候场等待与离场复位都在 dormant（见 dormant.gd）。

## 黑光扩散用的环形贴图（半透明黑色光环）。
const BLACK_LIGHT_TEXTURE := preload("res://assets/animations/characters/bosses/soul_master/_environment/roar_effect.png")

## 浮现时长（秒）。缩短可让黑光更早开始（黑光在浮现完成后才放）。
@export var fade_duration: float = 2.0
## 浮现前的停顿（秒）：让镜头先落位，避免刚踏进边界就闪出来。
@export var appear_delay: float = 0.4
## BGM 节点（相对 BOSS 根节点）。
@export var bgm_path: NodePath = ^"BGM"
## 入场音效（Audio/entrance = roar.ogg）。
@export var sfx_path: NodePath = ^"Audio/entrance"
## 浮现开始 / 结束时的震屏强度（0 = 不震）。
@export var shake_on_appear: float = 8.0
@export var shake_on_finish: float = 20.0
## 浮现结束后是否自动开战。
@export var start_fight_on_finish: bool = true

# ---- 黑光扩散（入场冲击波）参数 ----
## 黑光扩散持续多久（秒）。等 Boss 完全浮现之后才开始，默认 4.5 秒。
@export var black_light_duration: float = 4.5
## 每隔多少秒在 Boss 身上生成一圈黑色光环。
@export var black_light_interval: float = 0.2
## 单圈光环从生成到膨胀到最大倍数并销毁的时长（秒）。
@export var black_light_lifetime: float = 0.3
## 单圈光环最终放大倍数（相对初始 1 倍）。
@export var black_light_max_scale: float = 10.0
## 单圈光环初始透明度（半透明）。
@export var black_light_alpha: float = 1
## 光环置顶层级（绝对 z，盖住场景其它元素；BOSS 演出期间会临时抬到它上面）。
@export var black_light_z_index: int = 100

var _tween: Tween
var _playing := false
## 入场前 BOSS 的绘制层级，收尾还原用。
var _saved_z_index: int = 0
var _saved_z_as_relative: bool = true
## 黑光扩散：是否正在按间隔生成冲击波。
var _black_light_active := false
## 黑光扩散：距下一次生成光环的剩余计时。
var _black_light_accum := 0.0
## 演出代次：exit() 自增，让上一轮挂起的计时器协程失效，
## 避免玩家离场复位又立刻重进时旧协程把新一轮演出提前收尾。
var _play_id := 0


func enter(_from: StringName) -> void:
	if boss == null:
		return
	# 黑光不在这里启动：要等 Boss 先浮现完成（见 _play 里的黑光阶段）。
	_prepare_appearing()
	_play()


func exit(_to: StringName) -> void:
	# 中途被打断（离场复位 / 死亡）：停演出，把 BOSS 还原成可见可打。
	_play_id += 1          # 让上一轮挂起的计时器协程全部失效
	_playing = false
	_black_light_active = false
	_black_light_accum = 0.0
	_kill_tween()
	_restore()


func update(delta: float) -> void:
	# 整段演出（浮现 + 黑光）都站定，不移动、不结算接触伤害。
	if boss == null:
		return

	# 黑光扩散：按间隔在 Boss 身上生成一圈圈向外脉冲的黑色冲击波。
	if _black_light_active:
		_black_light_accum += delta
		while _black_light_accum >= black_light_interval:
			_black_light_accum -= black_light_interval
			_spawn_black_ring()


# ---- 演出 ----

func _prepare_appearing() -> void:
	# 场景里 EnemyAnimatedSprite 默认 animation=&"teleport"、frame=6，
	# 那一帧几乎全透明（瞬移的"消失帧"）。候场和入场都没播主动画，
	# 不先切到 idle 的话，modulate 淡到 1 也看不见 BOSS，
	# 只有演出收尾进 idle 状态才突然冒出来。
	play_action(BossStateNames.IDLE)

	# 黑光 z=100 是绝对置顶层，会连 BOSS 一起盖黑；演出期间把 BOSS 临时抬到它之上，
	# 让"先出现 → 再放黑光"整段里 BOSS 始终清晰可见，_restore() 还原。
	_saved_z_index = boss.z_index
	_saved_z_as_relative = boss.z_as_relative
	boss.z_as_relative = false
	boss.z_index = black_light_z_index + 1

	boss.modulate.a = 0.0
	boss.contact_damage_enabled = false
	boss.disable_melee_attack()
	# 飞行 BOSS：浮现就在悬停位置发生，不需要落地。
	boss.velocity = Vector2.ZERO


func _play() -> void:
	if _playing or boss == null or not is_inside_tree():
		return
	_playing = true
	var play_id := _play_id

	await get_tree().create_timer(appear_delay).timeout
	# is_inside_tree 一并判：场景销毁后本节点可能已出树，此时 get_tree() 为 null。
	if play_id != _play_id or not _playing or not is_inside_tree() or boss == null or not is_instance_valid(boss):
		return

	# BGM（loop 已在 bgm.ogg.import 里打开）+ 入场吼叫。
	var bgm := _bgm()
	if bgm != null and not bgm.playing:
		bgm.play()
	var sfx := boss.get_node_or_null(sfx_path) as AudioStreamPlayer2D
	if sfx != null:
		sfx.play()
	if shake_on_appear > 0.0:
		AuCameraDirector.shake(shake_on_appear, 0.4)

	# 阶段一：只浮现，不放黑光 —— 玩家先看清 BOSS 现身。
	_kill_tween()
	_tween = boss.create_tween()
	_tween.tween_property(boss, "modulate:a", 1.0, fade_duration) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	# 用计时器而不是 await tween.finished：Tween 被 kill 时不会发 finished，协程会永远挂着。
	await get_tree().create_timer(fade_duration).timeout
	if play_id != _play_id or not _playing or not is_inside_tree() or boss == null or not is_instance_valid(boss):
		return
	boss.modulate.a = 1.0       # 计时器与 Tween 可能差一帧，确保完全现身后再放黑光

	# 阶段二：BOSS 已经出现，再放黑光扩散；放完才收尾开战。
	if black_light_duration > 0.0:
		_black_light_active = true
		_black_light_accum = 0.0
		_spawn_black_ring()      # 立刻第一圈，不必等一个 interval
		await get_tree().create_timer(black_light_duration).timeout
		if play_id != _play_id or not _playing or not is_inside_tree() or boss == null or not is_instance_valid(boss):
			return
		_stop_black_light()

	_finish()


func _finish() -> void:
	_playing = false
	_black_light_active = false
	_black_light_accum = 0.0
	_restore()
	if shake_on_finish > 0.0:
		AuCameraDirector.shake(shake_on_finish, 0.35)
	if start_fight_on_finish:
		boss.begin_fight()          # → enter_combat 信号（关卡可据此锁门 / 亮血条）
	goto_if_current(BossStateNames.IDLE)


## 黑光持续时间到点：停止继续生成光环（已生成的光环会自行膨胀淡出后销毁）。
func _stop_black_light() -> void:
	_black_light_active = false
	_black_light_accum = 0.0


func _restore() -> void:
	if boss == null or not is_instance_valid(boss):
		return
	boss.z_as_relative = _saved_z_as_relative
	boss.z_index = _saved_z_index
	boss.modulate.a = 1.0
	# 按 Boss 上记录的"设计值"还原：dormant 会把 contact_damage_enabled 关掉，
	# 直接还原"进入本状态时的值"只会得到 false，Boss 就永远不蹭人了。
	boss.restore_contact_damage()


# ---- 特效 ----



## 黑光扩散：在 Boss 当前位置生成一圈半透明、置顶的黑色光环。
## 光环挂在 Boss 的父节点上（不受 Boss 自身淡入 modulate 影响），
## 0.2s 内放大到 black_light_max_scale 倍并淡出后自动销毁。
## 配合每 0.2s 一次的发放节奏，高刷新率下连成一串向外脉冲的黑色冲击波。
## BOSS 根节点在演出期间被抬到 black_light_z_index + 1，因此光环盖住场景其它元素，
## 但不会盖住 BOSS 自己。
func _spawn_black_ring() -> void:
	if boss == null or not is_instance_valid(boss):
		return
	var parent := boss.get_parent()
	if parent == null:
		return
	var ring := Sprite2D.new()
	ring.texture = BLACK_LIGHT_TEXTURE
	ring.centered = true
	ring.modulate = Color(0.0, 0.0, 0.0, black_light_alpha)
	ring.z_as_relative = false          # 绝对 z，避免被父节点层级抵消，保证置顶
	ring.z_index = black_light_z_index
	ring.scale = Vector2.ONE
	parent.add_child(ring)
	ring.global_position = boss.global_position
	# 0.2s 内膨胀到 10 倍并淡出，随后销毁。
	var tween := ring.create_tween()
	tween.tween_property(ring, "scale", Vector2.ONE * black_light_max_scale, black_light_lifetime) \
			.set_trans(Tween.TRANS_LINEAR)
	tween.parallel().tween_property(ring, "modulate:a", 0.0, black_light_lifetime) \
			.set_trans(Tween.TRANS_LINEAR)
	tween.tween_callback(ring.queue_free)


func _kill_tween() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null


func _bgm() -> AudioStreamPlayer2D:
	if boss == null:
		return null
	return boss.get_node_or_null(bgm_path) as AudioStreamPlayer2D
