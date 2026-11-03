extends BossState
class_name HollowKnightSlashState

## 近身挥砍：仅在玩家进入 attack_range 内才被决策选出（idle 的硬门槛保证）。
## 播放 slash 动画，并启用基类提供的近战命中盒（enable_melee_attack 负责命中结算），
## 动画播完回 idle 重新决策。
##
## 命中盒的开启 / 关闭 / 对玩家造成伤害（boss.melee_damage）全部沉淀在 Boss 基类，
## 本状态只管"播动画 + 在 enter/exit 切换命中盒"。


const ATTACK_RANGE := 200.0  ## 与 idle.attack_range 同义：进入才合法


func enter(_from: StringName) -> void:
	if boss == null:
		return
	var p := boss.get_player()

	# 兜底：决策后玩家已闪出范围，不出招。
	if p != null and absf(p.global_position.x - boss.global_position.x) > ATTACK_RANGE:
		machine.set_state(BossStateNames.IDLE)
		return

	if p != null:
		boss.face_toward(p.global_position.x)

	# 命中盒不再于 enter 立即开启：改由 slash 动画上的 Call Method 关键帧，
	# 在"刀到位"帧调用 boss.enable_melee_attack()、在"收刀"帧调用 boss.disable_melee_attack()，
	# 从而只在指定帧窗口内才可能对玩家结算伤害。

	# 播放挥砍动画，结束后回 idle。
	var ap := boss.action_animation_player
	if ap != null and ap.has_animation("slash"):
		if not ap.animation_finished.is_connected(_on_slash_finished):
			ap.animation_finished.connect(_on_slash_finished)
		ap.play("slash")


func _on_slash_finished(anim_name: StringName) -> void:
	if anim_name != BossStateNames.SLASH:
		return
	if machine != null and machine.get_state_name() == BossStateNames.SLASH:
		machine.set_state(BossStateNames.IDLE)


func exit(_to: StringName) -> void:
	# 关闭命中盒，断开动画信号。
	boss.disable_melee_attack()
	var ap := boss.action_animation_player if boss != null else null
	if ap != null and ap.animation_finished.is_connected(_on_slash_finished):
		ap.animation_finished.disconnect(_on_slash_finished)
