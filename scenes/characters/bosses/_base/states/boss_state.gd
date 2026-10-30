class_name BossState
extends EnemyState


## BOSS 状态基类。
##
## 只在 EnemyState 之上加一份 Boss 类型的快捷访问 —— 其余全部沿用：
##   · update() 不重写：EnemyState.update() 已经做了
##     「垂直运动 → 位移 → 接触伤害结算」三步，BOSS 一样适用；
##     而且 _contact_opens_combat() 默认 false，接触只会扣玩家血、
##     不会误触发开战（BOSS 的开战由 BossArena / 入场演出决定）。
##   · _tuning()（三级取值）、_play_audio()（镜头可见性）、_flash_white()（受击闪白）、
##     _stop()（站定，委托给运动介质）、_face_toward()（带死区朝向）—— 统统共用一份。
##
## 唯一的使用约定：招式位移**不要**走 _step_toward() / apply_step()。
## 那套会把位移交给 EnemySteering 裁决（朝向死区 + 踏空探测），是为小怪追击设计的；
## BOSS 的位移由招式自己给定（冲刺按累计位移收尾、后撤是面朝反方向），
## 招式状态应直接写 velocity.x，再靠 Enemy._apply_movement() 统一 move_and_slide()。
## 这也是 Boss._ready() 把 facing.check_displacement 置 false 的原因。

var _boss: Boss

var boss: Boss:
	get:
		if _boss == null or not is_instance_valid(_boss):
			_boss = machine.host as Boss if machine != null else null
		return _boss


## 进入下一阶段前先问一次：血量是否跨过了阈值。
## 由 combat 在每次决策前调用；这里也放一份，方便任何招式状态在收招时顺手检查。
func _check_phase() -> void:
	if boss == null:
		return
	boss.check_phase()
