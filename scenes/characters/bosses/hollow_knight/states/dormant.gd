extends BossDormantState
class_name HollowKnightDormantState

## HollowKnight 候场态：挂在四根锁链上沉睡，头会一直盯着玩家。
## 四根 BossChain 全被砍断 → dormant_end（苏醒坠落演出）；战前悬疑 BGM 按剩余链条数切轨。
##
## 领地信号、开局补查、可取消的苏醒/复位计时、整场复位由 BossDormantState 提供；
## 本状态只保留锁链、头部追踪与战前 BGM 这三块 BOSS 专有演出。

## 战前悬疑 BGM：按"已砍断链条数"选 FightAudio 下的 Chain 节点播放。
##   Chain0=砍0根/Suspence1 … Chain3=砍3根/Suspence4，Chain4=Suspence5 作第5轨备选。
const PREFIGHT_CHAIN_NODES: Array[String] = [
	"Chain0", "Chain1", "Chain2", "Chain3", "Chain4",
]

var _boss_bg_loop: AudioStreamPlayer2D
## FightAudio 节点（Boss 节点下），Chain0~4 是其子 AudioStreamPlayer2D。
var _fight_audio: Node2D
## 当前正在播放的战前悬疑轨，用于切轨/停播时停掉上一轨。
var _current_chain: AudioStreamPlayer2D

## 沉睡期间玩家进入 BossArena 后，boss 的头会一直盯着玩家。
## 头动画在 EnemyAnimatedSprite 的 "dormant" 动画里，共 N 帧；
## 把竞技场的 x 方向按"动画实际帧数 N"均分成 N 段，玩家落在哪段就显示对应帧。
## 段数跟着素材走：以后给 dormant 动画加/减帧，这里无需改代码即自动适配。
## 帧序列方向：true = 帧 0 看最左、帧 N-1 看最右（素材 0.png~5.png 即此顺序）。
@export var frames_left_to_right: bool = true

var _sprite: AnimatedSprite2D
## dormant 动画的实际帧数，惰性从 SpriteFrames 读取（按动画帧数均分的关键）。
var _frame_count: int = 0

## ---- 锁链断裂 → 触发 dormant_end ----
var _total_chains := 0
var _broken_count := 0
var _chains_connected := false


func _ready() -> void:
	# 本 BOSS 不走 trigger_entrance()，但也把入场状态名对准场景里真实存在的节点，
	# 避免基类默认的 entrance 将来被误用时切到不存在的状态。
	entrance_state = BossStateNames.DORMANT_END


func _on_dormant_enter() -> void:
	# 沉睡阶段（挂锁链）不可被玩家攻击：真正的判据是 Boss.is_cutscene_invulnerable()，
	# 这里再置一次 invincible，让玩家侧"是否命中生效"的判定也一致。
	# 顺手停掉上一轮残留的受击无敌计时：它超时会把 invincible 改回 false，
	# 让"战斗中被玩家逃出领地而重置回 dormant"的 boss 变成可攻击。
	if boss != null:
		boss.invincible = true
		if boss.hurt_invincibility_timer != null:
			boss.hurt_invincibility_timer.stop()
		# 关掉可能残留的近战命中盒：上一场若在出招途中被重置，沉睡期会误伤玩家。
		boss.disable_melee_attack()
	_ensure_refs()
	_start_dormant_sprite()
	_track_head()
	_connect_chains()
	_ensure_music()
	# 开战时停掉战前悬疑 BGM，避免与战斗 BGM 叠播（begin_fight → enter_combat）。
	if boss != null and not boss.enter_combat.is_connected(_on_boss_enter_combat):
		boss.enter_combat.connect(_on_boss_enter_combat)


func _on_dormant_update(_delta: float) -> void:
	# 沉睡期间不做重力结算：BOSS 挂在锁链上是悬空的，掉下来会破坏 dormant_end 的
	# "先上提再坠落"演出。头部追踪是这里唯一的每帧工作。
	_track_head()


func _on_arena_missing() -> void:
	# 本 BOSS 靠砍断四根锁链 / 关卡脚本唤醒，没有领地时不自动苏醒。
	pass


func _on_player_inside_arena() -> void:
	# 开局玩家已站在领地内（时序不可靠）时，按当时链条数补播对应轨。
	_play_for_current_chains()


func _on_arena_entered() -> void:
	# BOSS 已死：踏入领地不再有任何效果（不播战前 BGM、不苏醒、不重置）。
	if boss != null and boss.dead:
		return
	# 四根链子已全断：玩家再次踏入领地 → 延迟 2 秒再苏醒，让玩家看清"回到 dormant"的效果。
	if _total_chains > 0 and _broken_count >= _total_chains:
		_start_awaken_delay()
		return
	# 进入领地也按"当前已砍断的链条数"选轨（与砍链同一套映射；含 4 根全断则不播）。
	_play_for_current_chains()


func _on_arena_exited() -> void:
	# BOSS 已死：离开领地不再有任何效果（不重置、不复活、不切回 dormant）。
	if boss != null and boss.dead:
		return
	_stop_music()
	if _boss_bg_loop != null and _boss_bg_loop.playing:
		_boss_bg_loop.stop()
	# 四根链子已全断时，玩家离开领地即整场重置回 dormant（苏醒阶段或已开打都算）。
	if _total_chains > 0 and _broken_count >= _total_chains:
		reset_encounter()


func _on_reset_extra() -> void:
	if boss == null:
		return
	# 1) 取消可能挂起的苏醒计时（玩家在 2 秒缓冲内又逃出）。
	cancel_delay(&"awaken")
	# 2) 停止苏醒/战斗演出，回到 RESET（含 BOSS 身上装饰链 DormantSuspensionChains）。
	if boss.action_animation_player != null:
		boss.action_animation_player.stop()
		boss.action_animation_player.play("RESET")
	if _boss_bg_loop != null and _boss_bg_loop.playing:
		_boss_bg_loop.stop()
	# 3) 清掉无敌与上一轮战斗残留的受击无敌计时，避免它超时后把 dormant 的无敌清掉。
	boss.invincible = false
	if boss.hurt_invincibility_timer != null:
		boss.hurt_invincibility_timer.stop()
	# 4) 链子计数保持不变（仍为全断）；基类会 set_state(DORMANT, true) 重新走 enter()。


## 切到 dormant 动画并停住，由 _track_head 手动指定帧，避免自动循环播放。
func _start_dormant_sprite() -> void:
	if _sprite == null:
		return
	if _sprite.animation != &"dormant":
		_sprite.animation = &"dormant"
	_sprite.stop()


func _track_head() -> void:
	if _sprite == null or arena == null:
		return
	var player := enemy.get_player()
	if player == null:
		return

	# 惰性取帧数：跟着动画素材走，不写死。
	if _frame_count <= 0 and _sprite.sprite_frames != null:
		_frame_count = _sprite.sprite_frames.get_frame_count(&"dormant")
	var count := _frame_count if _frame_count > 0 else 1

	var rect := arena.global_rect()

	# 只按 x 方向判定（头左右转，与玩家高低无关）；竞技场 x 范围外则保持居中帧。
	if player.global_position.x < rect.position.x or player.global_position.x > rect.end.x:
		_sprite.frame = _neutral_frame(count)
		return

	# 把 [0,1] 的归一化位置按帧数 N 均分：每段等宽 1/N，floor 落帧。
	var t := clampf((player.global_position.x - rect.position.x) / rect.size.x, 0.0, 1.0)
	var frame := int(floorf(t * float(count)))
	frame = clampi(frame, 0, count - 1)
	if not frames_left_to_right:
		frame = count - 1 - frame
	_sprite.frame = frame


## 竞技场外的居中帧：count 为偶数时取中间偏右那帧（与 t=0.5 落在第 count/2 段一致）。
func _neutral_frame(count: int) -> int:
	return int(count / 2.0)


func _ensure_refs() -> void:
	if boss == null:
		return
	if _sprite == null:
		_sprite = boss.animated_sprite
	# 竞技场查找统一走 Boss.arena_zone()，赋给基类的 arena 字段。
	if arena == null:
		arena = boss.arena_zone()
	if _sprite != null and _sprite.sprite_frames != null:
		_frame_count = _sprite.sprite_frames.get_frame_count(&"dormant")


func _connect_chains() -> void:
	if _chains_connected:
		return
	var scene := enemy.get_parent()          # HollowKnightScene 节点
	if scene == null:
		return
	for child in scene.get_children():
		if child == enemy or not child.has_signal("broke"):
			continue
		_total_chains += 1
		child.broke.connect(_on_chain_broke)
	_chains_connected = true


## 按当前已砍断的链条数选轨：砍 0/1/2/3 根 → FightAudio/Chain0~3；4 根全断不播。
func _play_for_current_chains() -> void:
	if _broken_count <= _total_chains:
		_play_track(_broken_count)


## 重置后玩家再次进入领地：2 秒后再切到 dormant_end，
## 期间 boss 保持在 dormant 展示复位效果，让玩家看清"回到初始"。
func _start_awaken_delay() -> void:
	schedule_delay(&"awaken", 2.0, _on_awaken_timer_timeout)


## 2 秒到时：仅当玩家仍在场内、且 boss 没被再次重置（仍是 dormant）才真正苏醒。
func _on_awaken_timer_timeout() -> void:
	if player_in_arena and machine != null \
			and machine.current_state_name == BossStateNames.DORMANT:
		machine.set_state(BossStateNames.DORMANT_END)


func _on_chain_broke() -> void:
	_broken_count += 1
	_play_for_current_chains()
	if _broken_count >= _total_chains:
		machine.set_state(BossStateNames.DORMANT_END)


## ---- 战前 BGM 播放器 ----
func _ensure_music() -> void:
	if _fight_audio != null and is_instance_valid(_fight_audio):
		return
	if boss == null:
		return
	_fight_audio = boss.get_node_or_null("FightAudio") as Node2D
	if _fight_audio == null:
		return
	_boss_bg_loop = _fight_audio.get_node_or_null("boss_bg_loop") as AudioStreamPlayer2D


## 切到指定战前悬疑轨（index 对应 PREFIGHT_CHAIN_NODES），直接播放 FightAudio/ChainX。
func _play_track(index: int) -> void:
	if _fight_audio == null or index < 0 or index >= PREFIGHT_CHAIN_NODES.size():
		return
	var node := _fight_audio.get_node_or_null(PREFIGHT_CHAIN_NODES[index]) as AudioStreamPlayer2D
	if node == null:
		return
	# 与上一轨不同则先停掉上一轨，避免叠播。
	if _current_chain != null and _current_chain != node and _current_chain.playing:
		_current_chain.stop()
	_current_chain = node
	if not node.playing:
		node.play()


func _on_boss_enter_combat(_target: Node2D) -> void:
	_stop_music()


func _stop_music() -> void:
	if _current_chain != null and _current_chain.playing:
		_current_chain.stop()
	_current_chain = null
