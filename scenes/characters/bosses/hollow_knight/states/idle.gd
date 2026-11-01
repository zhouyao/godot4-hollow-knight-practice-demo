extends BossState
class_name HollowKnightIdleState

## 吼叫结束后的待机：启动战斗 BGM、循环播放 ActionAnimationPlayer/idle，boss 站定。
## 玩家由自己的 freeze 状态在 2 秒后自行解冻回到 idle/fall，这里无需再处理玩家。

func enter(_from: StringName) -> void:
	if boss == null:
		return
	# boss 动画：ActionAnimationPlayer/idle（循环驱动精灵 idle 帧；不调 RESET，否则锁链会重新显形）。
	if boss.action_animation_player != null and boss.action_animation_player.has_animation("idle"):
		boss.action_animation_player.play("idle")
	# 启动战斗 BGM（循环 ogg；原 dormant_end 在 5.23s 启动，落地切 scream 会跳过该时间点）。
	var bg_loop := boss.get_node_or_null("FightAudio/boss_bg_loop") as AudioStreamPlayer2D
	if bg_loop != null and not bg_loop.playing:
		bg_loop.play()

func update(_delta: float) -> void:
	# 待机期间 boss 站定，不结算接触伤害。
	pass
