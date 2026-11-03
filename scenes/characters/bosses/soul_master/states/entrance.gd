extends BossState
class_name SoulMasterEntranceState

## SoulMaster 入场演出：从完全透明缓缓浮现（透明度 + 瞬移特效 + 起止震屏）+ 起 BGM，
## 演出结束后 begin_fight() 开战并转入 idle。
##
## 本状态只负责"出现"这一段；候场等待与离场复位都在 dormant（见 dormant.gd）。

## 浮现时长（秒）。
@export var fade_duration: float = 3.0
## 浮现前的停顿（秒）：让镜头先落位，避免刚踏进边界就闪出来。
@export var appear_delay: float = 0.4
## BGM 节点（相对 BOSS 根节点）。
@export var bgm_path: NodePath = ^"BGM"
## 入场音效（Audio/entrance = roar.ogg）。
@export var sfx_path: NodePath = ^"Audio/entrance"
## 浮现特效精灵（播放 teleport_effect）。
@export var effect_sprite_path: NodePath = ^"Animation/EffectAnimatedSprite"
## 浮现开始 / 结束时的震屏强度（0 = 不震）。
@export var shake_on_appear: float = 8.0
@export var shake_on_finish: float = 20.0
## 浮现结束后是否自动开战。
@export var start_fight_on_finish: bool = true

var _tween: Tween
var _playing := false


func enter(_from: StringName) -> void:
	if boss == null:
		return
	_prepare_appearing()
	_play()


func exit(_to: StringName) -> void:
	# 中途被打断（离场复位 / 死亡）：停演出，把 BOSS 还原成可见可打。
	_playing = false
	_kill_tween()
	_stop_effect()
	_restore()


func update(delta: float) -> void:
	# 浮现期间站定，只保留重力。
	if boss == null:
		return
	#boss.velocity.x = 0.0
	#boss._apply_vertical_motion(delta)
	#boss._apply_movement()


# ---- 演出 ----

func _prepare_appearing() -> void:
	boss.modulate.a = 0.0
	boss.contact_damage_enabled = false
	boss.disable_melee_attack()
	# 飞行 BOSS：浮现就在悬停位置发生，不需要落地。
	boss.velocity = Vector2.ZERO


func _play() -> void:
	if _playing or boss == null or not is_inside_tree():
		return
	_playing = true

	await get_tree().create_timer(appear_delay).timeout
	# is_inside_tree 一并判：场景销毁后本节点可能已出树，此时 get_tree() 为 null。
	if not _playing or not is_inside_tree() or boss == null or not is_instance_valid(boss):
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

	_play_effect()

	# 从"消失"慢慢浮现。
	_kill_tween()
	_tween = boss.create_tween()
	_tween.tween_property(boss, "modulate:a", 1.0, fade_duration) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	# 用计时器而不是 await tween.finished：Tween 被 kill 时不会发 finished，协程会永远挂着。
	await get_tree().create_timer(fade_duration).timeout
	if not _playing or not is_inside_tree() or boss == null or not is_instance_valid(boss):
		return
	_finish()


func _finish() -> void:
	_playing = false
	_stop_effect()
	_restore()
	if shake_on_finish > 0.0:
		AuCameraDirector.shake(shake_on_finish, 0.35)
	if start_fight_on_finish:
		boss.begin_fight()          # → enter_combat 信号（关卡可据此锁门 / 亮血条）
	goto_if_current(BossStateNames.IDLE)


func _restore() -> void:
	if boss == null or not is_instance_valid(boss):
		return
	boss.modulate.a = 1.0
	# 按 BOSS 上记录的"设计值"还原：dormant 会把 contact_damage_enabled 关掉，
	# 直接还原"进入本状态时的值"只会得到 false，Boss 就永远不蹭人了。
	var sm := boss as BossSoulMaster
	boss.contact_damage_enabled = sm.base_contact_damage if sm != null else true


# ---- 特效 ----

## 浮现特效：把 teleport_effect 的播放速度按 fade_duration 缩放，
## 让整段动画正好铺满淡入时长（素材本身 4 帧 / speed 5 ≈ 0.8 秒）。
func _play_effect() -> void:
	var fx := _effect_sprite()
	if fx == null or fx.sprite_frames == null:
		return
	if not fx.sprite_frames.has_animation(&"teleport_effect"):
		return
	var frames := fx.sprite_frames
	var count := frames.get_frame_count(&"teleport_effect")
	var speed := frames.get_animation_speed(&"teleport_effect")
	var length := float(count) / speed if speed > 0.0 else 0.0
	fx.speed_scale = length / fade_duration if fade_duration > 0.0 and length > 0.0 else 1.0
	fx.play(&"teleport_effect")


## 收尾：停特效并还原播放速度（teleport 技能复用的是同一个精灵，speed_scale 必须复原）。
func _stop_effect() -> void:
	var fx := _effect_sprite()
	if fx == null:
		return
	fx.stop()
	fx.speed_scale = 1.0
	if fx.sprite_frames != null and fx.sprite_frames.has_animation(&"teleport_effect"):
		fx.frame = maxi(fx.sprite_frames.get_frame_count(&"teleport_effect") - 1, 0)


func _effect_sprite() -> AnimatedSprite2D:
	if boss == null:
		return null
	return boss.get_node_or_null(effect_sprite_path) as AnimatedSprite2D


func _kill_tween() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null


func _bgm() -> AudioStreamPlayer2D:
	if boss == null:
		return null
	return boss.get_node_or_null(bgm_path) as AudioStreamPlayer2D
