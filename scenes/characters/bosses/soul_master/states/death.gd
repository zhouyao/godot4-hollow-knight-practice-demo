extends BossState
class_name SoulMasterDeathState

## 击败演出：BOSS 失去浮力坠向地面 → 落地瞬间爆出金币 → 尸体缓缓淡出后移除。
##
## 与 HollowKnight 的"升空消散"相反：SoulMaster 是飞行 BOSS，
## 坠落由飞行介质的 death_gravity 接管（FlyingLocomotion.apply_vertical 只在 dead 时施加重力），
## 本状态只负责逐帧结算位移，以及落地后的收尾（掉落 / 淡出 / 释放节点）。

## 落地后先停顿多久再开始淡出（秒）：留给金币散开、看清死亡姿态。
@export var fade_delay: float = 0.6
## 从全亮到全透明所需的时长（秒）。
@export var fade_time: float = 1.6
## 迟迟不落地时的兜底（秒）：防止掉出地图 / 脚下没有地形时永远不结算。
@export var fall_timeout: float = 5.0
## BGM 节点（相对 BOSS 根节点）。
@export var bgm_path: NodePath = ^"BGM"
## 死亡音效（有 stream 才播；SoulMaster 目前没配，留空不影响流程）。
@export var sfx_path: NodePath = ^"Audio/death"

var _settled := false
var _fade_elapsed := 0.0


func enter(_from: StringName) -> void:
	if boss == null:
		return
	# 击败后不再参与战斗结算。
	boss.invincible = true
	boss.velocity = Vector2.ZERO
	boss.contact_damage_enabled = false
	boss.disable_melee_attack()
	# 死亡姿态：走 ActionAnimationPlayer 的 death（精灵逐帧，与其它 BOSS 同款）。
	if boss.animated_sprite != null:
		boss.animated_sprite.stop()
		boss.animated_sprite.animation = &"death"
		boss.animated_sprite.frame = 0
	play_action(&"death")
	# 尸体要落得下来：FlyingLocomotion.on_death() 会把 motion_mode 切回 GROUNDED，
	# 之后 apply_vertical() 才会走 death_gravity 分支。
	if boss.locomotion != null:
		boss.locomotion.on_death(boss)
	var sfx := boss.get_node_or_null(sfx_path) as AudioStreamPlayer2D
	if sfx != null and sfx.stream != null:
		sfx.play()
	var bgm := boss.get_node_or_null(bgm_path) as AudioStreamPlayer2D
	if bgm != null and bgm.playing:
		bgm.stop()


func update(delta: float) -> void:
	if boss == null or not is_instance_valid(boss):
		return
	if not _settled:
		# 下坠：垂直力由飞行介质的 death_gravity 提供，位移仍走统一的 move_and_slide。
		boss._apply_vertical_motion(delta)
		boss._apply_movement()
		if boss.is_on_floor() or elapsed >= fall_timeout:
			_land()
		return
	# 落地后：先停一会儿，再缓缓消失。
	_fade_elapsed += delta
	var t := clampf((_fade_elapsed - fade_delay) / maxf(fade_time, 0.01), 0.0, 1.0)
	boss.modulate.a = 1.0 - t
	if t >= 1.0:
		_finish()


## 落地瞬间：爆金币 + 关碰撞，并开始淡出计时。
func _land() -> void:
	if _settled:
		return
	_settled = true
	_fade_elapsed = 0.0
	boss.velocity = Vector2.ZERO
	# 金币就在落点爆开（掉落表在场景里配，Boss.drop_loot → DropSpawner.spawn_table）。
	boss.drop_loot(boss.global_position)
	# 尸体不再挡路：落地即关碰撞，否则玩家会被隐形尸体卡住。
	var shape := boss.get_node_or_null("BodyCollisionShape2D") as CollisionShape2D
	if shape != null:
		shape.set_deferred("disabled", true)


## 完全消失后释放节点：Boss._start_corpse_fade 是空实现（留给 death 状态收尾），
## 不主动释放就会在场景里留一个隐形的 BOSS 节点。
func _finish() -> void:
	if machine != null:
		machine.active = false
	if boss != null and is_instance_valid(boss):
		boss.queue_free()
