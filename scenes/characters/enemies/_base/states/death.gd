extends EnemyState


## 尸体是否已处理完毕（落地 / 沉底 / 上浮到位）：由运动介质判定，只结算一次。
var _settled := false

func enter(_from: StringName) -> void:
	machine.active = true
	_flash_white()
	_play_action(EnemyStateNames.DEATH)
	_play_audio(EnemyStateNames.DEATH)
	# 躯体的落地 / 悬停 / 上浮交给运动介质：飞行怪要切回 GROUNDED 才落得下来，
	# 水下怪则可能反过来上浮。基类不再写死"死后一律吃重力"。
	if enemy.locomotion != null:
		enemy.locomotion.on_death(enemy)

func update(delta: float) -> void:
	super.update(delta)
	if _settled or not _corpse_settled():
		return
	_settled = true
	enemy.collision_shape.set_deferred("disabled", true)
	machine.active = false
	_apply_corpse_offset()


## 尸体是否处理完毕：交给运动介质（地面 / 飞行判"落地"，水下判"沉底 / 上浮到位"）。
## 不能写死 is_on_floor() —— 水中没有"地"可落，那种怪会永远走不到这一步，
## 导致碰撞不禁用、corpse_y_offset 不生效、状态机一直空转。
func _corpse_settled() -> bool:
	if enemy.locomotion != null:
		return enemy.locomotion.is_corpse_settled(enemy, elapsed)
	return enemy.is_on_floor()


## 尸体纵向偏移：落地后把尸体精灵沿 y 轴挪动 corpse_y_offset，微调躺尸位置。
## 直接改精灵节点坐标（不动根节点，避免连带位移残留的掉落点 / 计时器逻辑）。
func _apply_corpse_offset() -> void:
	if not is_zero_approx(enemy.corpse_y_offset):
		enemy.animated_sprite.position.y += enemy.corpse_y_offset

func get_transition(_delta: float) -> StringName:
	return &""
