extends BossState
class_name HollowKnightScreamState

## 苏醒落地后的"吼叫"演出：播放 ActionAnimationPlayer/scream + 音效，重震屏，冻结玩家 2 秒，随后进入 idle。

const SCREAM_DURATION := 2.0

func enter(_from: StringName) -> void:
	if boss == null:
		return
	# 让玩家进入自己的 freeze 状态（该状态自行计时 2 秒后解冻回到 idle/fall）。
	var p := enemy.get_player() as PlayerInitial
	if p != null and p.state_machine != null:
		p.state_machine.set_state(PlayerStateNames.FREEZE, true)
	AuCameraDirector.shake_heavy()
	# boss 动画：ActionAnimationPlayer/scream（驱动精灵切到 scream 并逐帧播放）。
	if boss.action_animation_player != null and boss.action_animation_player.has_animation("scream"):
		boss.action_animation_player.play("scream")
	boss.velocity = Vector2.ZERO  # 落地残留速度清零，boss 站定。
	# 音效：Audio/scream。
	var scream_audio := boss.get_node_or_null("Audio/scream") as AudioStreamPlayer2D
	if scream_audio != null:
		scream_audio.play()
	# 冻结 2 秒后转入 idle（中断兜底：若中途被切走则不强行跳转）。
	await get_tree().create_timer(SCREAM_DURATION).timeout
	if machine != null and machine.get_state_name() == BossStateNames.SCREAM:
		machine.set_state(BossStateNames.IDLE)

func update(_delta: float) -> void:
	# 演出期间 boss 完全静止，且不结算接触伤害（玩家已冻结）。
	pass
