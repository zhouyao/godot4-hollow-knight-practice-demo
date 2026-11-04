extends BossDormantState
class_name SoulMasterDormantState

## SoulMaster 候场态（初始状态）：BOSS 完全隐藏、安静、不结算伤害。
## 玩家踏入 BossArena（AuZone）时延迟切到 entrance 开始浮现演出。
##
## 领地信号（连一次、永不断开）、开局补查、可取消的入场/复位计时、整场复位
## 全部由 BossDormantState 提供；本状态只负责"隐藏"与"何时开演"。
## 领地挂件（BossArenaBehavior）保持 auto_start_fight = false 即可。


func _on_dormant_enter() -> void:
	_prepare_hidden()


func _on_dormant_update(delta: float) -> void:
	# 候场：站定，只保留重力（飞行介质在存活期不施加纵向力），不结算接触伤害。
	stand_still(delta, false)


func _on_player_inside_arena() -> void:
	trigger_entrance()


func _on_arena_entered() -> void:
	# 已在计时时 trigger_entrance 会忽略，不会被重复触发无限推后。
	trigger_entrance()


func _on_arena_exited() -> void:
	# 仍在候场 = 还没开演：玩家又出去了，取消还没到点的开演延迟即可（基类已 cancel）。
	if machine == null or machine.get_state_name() == name:
		return
	if not reset_on_player_exit or boss == null or boss.dead:
		return
	schedule_delay(&"reset", reset_delay, _on_reset_timeout)


func _on_reset_timeout() -> void:
	if player_in_arena or boss == null or boss.dead:
		return
	reset_encounter()


## 隐藏：全透明、关接触伤害、收招，并停掉可能残留的 BGM。
## SoulMaster 是飞行 BOSS（locomotion = flying.tres），候场时悬停在场景摆位处，不受重力。
func _prepare_hidden() -> void:
	if boss == null:
		return
	boss.modulate.a = 0.0
	boss.contact_damage_enabled = false
	boss.disable_melee_attack()
	boss.velocity = Vector2.ZERO
	stop_bgm()
