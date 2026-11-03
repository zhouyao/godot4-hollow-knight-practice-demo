extends BossState
class_name HollowKnightDormantState

## 战前悬疑 BGM：按"剩余链条数"选 FightAudio 下的 Chain 节点播放。
##   剩 4 根（进入领地 / 未砍）→ FightAudio/Chain0（Suspence 1）
##   剩 3 根（砍 1）→ FightAudio/Chain1（Suspence 2）
##   剩 2 根（砍 2）→ FightAudio/Chain2（Suspence 3）
##   剩 1 根（砍 3）→ FightAudio/Chain3（Suspence 4）
##   剩 0 根（砍 4）→ 不播 Chain4，沿用上一轨进入苏醒演出。
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
var _arena_connected := false

## 沉睡状态：玩家进入 BossArena 后，boss 的头会一直盯着玩家。
## 头动画在 EnemyAnimatedSprite 的 "dormant" 动画里，共 N 帧；
## 把竞技场的 x 方向按"动画实际帧数 N"均分成 N 段，玩家落在哪段就显示对应帧。
## 段数跟着素材走：以后给 dormant 动画加/减帧，这里无需改代码即自动适配。

## 帧序列方向：true = 帧 0 看最左、帧 N-1 看最右（素材 0.png~5.png 即此顺序）。
@export var frames_left_to_right: bool = true

var _arena: AuZone
var _sprite: AnimatedSprite2D
## dormant 动画的实际帧数，惰性从 SpriteFrames 读取（按动画帧数均分的关键）。
var _frame_count: int = 0


func enter(_from: StringName) -> void:
	# 沉睡阶段（挂锁链）不可被玩家攻击：真正的判据是 HollowKnight.is_cutscene_invulnerable()，
	# 这里再置一次 invincible，让玩家侧"是否命中生效"的判定也一致。
	# 顺手停掉上一轮残留的受击无敌计时：它超时会把 invincible 改回 false，
	# 让"战斗中被玩家逃出领地而重置回 dormant"的 boss 变成可攻击。
	if boss != null:
		boss.invincible = true
		if boss.hurt_invincibility_timer != null:
			boss.hurt_invincibility_timer.stop()
	_ensure_refs()
	_start_dormant_sprite()
	_track_head()
	_connect_chains()
	_connect_arena()
	_ensure_music()
	# 开战时停掉战前悬疑 BGM，避免与战斗 BGM 叠播（begin_fight → enter_combat）。
	if boss != null and not boss.enter_combat.is_connected(_on_boss_enter_combat):
		boss.enter_combat.connect(_on_boss_enter_combat)


func update(_delta: float) -> void:
	_track_head()


## 切到 dormant 动画并停住，由 _track_head 手动指定帧，避免自动循环播放。
func _start_dormant_sprite() -> void:
	if _sprite == null:
		return
	if _sprite.animation != &"dormant":
		_sprite.animation = &"dormant"
	_sprite.stop()


func _track_head() -> void:
	if _sprite == null or _arena == null:
		return
	var player := enemy.get_player()
	if player == null:
		return

	# 惰性取帧数：跟着动画素材走，不写死。
	if _frame_count <= 0 and _sprite.sprite_frames != null:
		_frame_count = _sprite.sprite_frames.get_frame_count(&"dormant")
	var count := _frame_count if _frame_count > 0 else 1

	var rect := _arena.global_rect()

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
	if _sprite == null:
		_sprite = enemy.animated_sprite
	if _arena == null:
		# 竞技场已迁移到关卡场景（HollowKnightScene 下，与 boss 平级），不再挂在 boss 节点下。
		_arena = enemy.get_node_or_null("BossArena") as AuZone
		if _arena == null:
			var scene := enemy.get_parent()
			if scene != null:
				_arena = scene.get_node_or_null("BossArena") as AuZone
	if _sprite != null and _sprite.sprite_frames != null:
		_frame_count = _sprite.sprite_frames.get_frame_count(&"dormant")


## ---- 锁链断裂 → 触发 dormant_end ----
var _total_chains := 0
var _broken_count := 0
var _chains_connected := false
## 重置后再次进入领地时，给 2 秒缓冲再苏醒（让玩家看清"回到 dormant"的效果）。
var _awaken_timer: SceneTreeTimer = null
## 玩家此刻是否在 BossArena 内（由 enter/exit 信号维护，用于苏醒计时的兜底判定）。
var _player_in_arena := false

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


## ---- 玩家踏入领地 → 播战前悬疑 1 号，并接好切轨 / 停播 ----
func _connect_arena() -> void:
	if _arena_connected or _arena == null:
		return
	if not _arena.player_entered.is_connected(_on_player_entered_arena):
		_arena.player_entered.connect(_on_player_entered_arena)
	if not _arena.player_exited.is_connected(_on_player_exited_arena):
		_arena.player_exited.connect(_on_player_exited_arena)
	_arena_connected = true
	# 开局玩家已站在领地内（时序不可靠）时，按当时链条数补播对应轨。
	for b in _arena.get_overlapping_bodies():
		if b.is_in_group("player"):
			_play_for_current_chains()
			break


func _on_player_entered_arena(_zone: Node, _player: Node2D) -> void:
	# BOSS 已死：踏入领地不再有任何效果（不播战前 BGM、不苏醒、不重置）。
	if boss != null and boss.dead:
		return
	_player_in_arena = true
	# 四根链子已全断：玩家再次踏入领地 → 延迟 2 秒再苏醒，让玩家看清"回到 dormant"的效果。
	if _total_chains > 0 and _broken_count >= _total_chains:
		_start_awaken_delay()
		return
	# 进入领地也按"当前已砍断的链条数"选轨（与砍链同一套映射；含 4 根全断则不播）。
	_play_for_current_chains()


## 按当前已砍断的链条数选轨：砍 0/1/2/3 根 → FightAudio/Chain0~3；4 根全断不播。
func _play_for_current_chains() -> void:
	if _broken_count <= _total_chains:
		_play_track(_broken_count)
	


func _on_player_exited_arena(_zone: Node, _player: Node2D) -> void:
	# BOSS 已死：离开领地不再有任何效果（不重置、不复活、不切回 dormant）。
	if boss != null and boss.dead:
		return
	_player_in_arena = false
	_stop_music()
	if _boss_bg_loop != null and _boss_bg_loop.playing:
		_boss_bg_loop.stop()
	# 四根链子已全断时，玩家离开领地即整场重置回 dormant（苏醒阶段或已开打都算）。
	if _total_chains > 0 and _broken_count >= _total_chains:
		_reset_encounter()


## 整场重置：四根链子全断后，玩家在苏醒阶段或开打后逃离领地时调用。
## 链子保持断裂（不恢复）；仅把 boss 复位到初始：退战斗 → 停演出 → 回出生点 → 满血/清阶段 → 回 dormant。
## 玩家再次踏入领地时，_on_player_entered_arena 会直接转回 dormant_end。
func _reset_encounter() -> void:
	if boss == null:
		return
	# 0) 取消可能挂起的苏醒计时（玩家在 2 秒缓冲内又逃出）。
	_cancel_awaken_delay()
	# 1) 退出战斗：清仇恨、广播 leave_combat（停 BGM / 解锁等）。
	boss._set_combat(false)
	# 2) 停止苏醒/战斗演出，回到 RESET（含 BOSS 身上装饰链 DormantSuspensionChains）。
	if boss.action_animation_player != null:
		boss.action_animation_player.stop()
		boss.action_animation_player.play("RESET")
	if _boss_bg_loop != null and _boss_bg_loop.playing:
		_boss_bg_loop.stop()
	# 3) 回出生点、清零速度/击退/无敌、阶段归零、满血。
	boss.velocity = Vector2.ZERO
	boss.knockback = Vector2.ZERO
	boss.global_position = boss.spawn_position
	boss.invincible = false
	# 停掉上一轮战斗残留的受击无敌计时，避免它超时后把 dormant 的无敌清掉。
	if boss.hurt_invincibility_timer != null:
		boss.hurt_invincibility_timer.stop()
	boss.phase_index = 0
	boss.health = boss.initial_health
	boss._refresh_health_bar()
	# 4) 链子计数保持不变（仍为全断）；切回 dormant（让 enter 重新接好领地信号）。
	_arena_connected = false
	machine.set_state(BossStateNames.DORMANT)


## 取消挂起的苏醒计时（若存在）。
func _cancel_awaken_delay() -> void:
	if _awaken_timer != null:
		if _awaken_timer.timeout.is_connected(_on_awaken_timer_timeout):
			_awaken_timer.timeout.disconnect(_on_awaken_timer_timeout)
		_awaken_timer = null


## 重置后玩家再次进入领地：2 秒后再切到 dormant_end，
## 期间 boss 保持在 dormant 展示复位效果，让玩家看清"回到初始"。
func _start_awaken_delay() -> void:
	_cancel_awaken_delay()
	_awaken_timer = get_tree().create_timer(2.0)
	_awaken_timer.timeout.connect(_on_awaken_timer_timeout)


## 2 秒到时：仅当玩家仍在场内、且 boss 没被再次重置（仍是 dormant）才真正苏醒。
func _on_awaken_timer_timeout() -> void:
	_awaken_timer = null
	if _player_in_arena and machine != null \
			and machine.current_state_name == BossStateNames.DORMANT:
		machine.set_state(BossStateNames.DORMANT_END)


func _on_chain_broke() -> void:
	_broken_count += 1
	
	_play_for_current_chains()
	if _broken_count >= _total_chains:
		
		machine.set_state(BossStateNames.DORMANT_END)
		
		#if _arena.player_entered.is_connected(_on_player_entered_arena):
		#	_arena.player_entered.disconnect(_on_player_entered_arena)
		#if _arena.player_exited.is_connected(_on_player_exited_arena):
		#	_arena.player_exited.disconnect(_on_player_exited_arena)
			
		_arena_connected = false


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
